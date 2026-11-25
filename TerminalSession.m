#import "TerminalSession.h"
#import "Settings.h"
#import "TermTheme.h"
#import "TermEncoding.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <limits.h>

#include "proto.h"
#include "ptyspawn.h"

#define MAX_SCROLLBACK 2000

@interface TerminalSession () {
    VTerm       *_vt;
    VTermScreen *_screen;

    int   _rows, _cols;
    int   _cursorRow, _cursorCol;
    BOOL  _cursorVisible;
    BOOL  _altScreen;

    int   _fd;                    /* pty master (local) or unix socket (daemon) */
    pid_t _pid;
    BOOL  _daemonMode;
    BOOL  _connected;
    BOOL  _ended;
    BOOL  _wantNewSession;        /* attach failed: ask the daemon for a fresh session */
    BOOL  _awaitingAttach;        /* an ATTACH request is in flight */
    uint32_t _rxOffset;           /* daemon mode: bytes of output we have processed */

    dispatch_source_t _readSrc;
    dispatch_source_t _writeSrc;
    BOOL _writeSrcActive;

    NSMutableData *_wbuf;         /* bytes waiting to be written to _fd */
    NSMutableData *_rbuf;         /* daemon mode: partial frames */
    NSMutableArray *_scrollback;  /* NSData blobs of VTermScreenCell[cols] */
    NSMutableData *_decodeCarry;  /* incomplete multi-byte sequence from the previous chunk */
    NSStringEncoding _carryEncoding;

    int _dirtyMin, _dirtyMax;
    BOOL _stateDirty;
}
@end

static int cbDamage(VTermRect rect, void *user);
static int cbMoveCursor(VTermPos pos, VTermPos oldpos, int visible, void *user);
static int cbSetProp(VTermProp prop, VTermValue *val, void *user);
static int cbBell(void *user);
static int cbPushLine(int cols, const VTermScreenCell *cells, void *user);
static int cbPopLine(int cols, VTermScreenCell *cells, void *user);
static int cbSbClear(void *user);
static void cbOutput(const char *s, size_t len, void *user);

static const VTermScreenCallbacks kScreenCallbacks = {
    .damage      = cbDamage,
    .moverect    = NULL,
    .movecursor  = cbMoveCursor,
    .settermprop = cbSetProp,
    .bell        = cbBell,
    .resize      = NULL,
    .sb_pushline = cbPushLine,
    .sb_popline  = cbPopLine,
    .sb_clear    = cbSbClear,
};

#define SELF(u) ((__bridge TerminalSession *)(u))

@implementation TerminalSession

@synthesize rows = _rows, cols = _cols;
@synthesize cursorRow = _cursorRow, cursorCol = _cursorCol;
@synthesize cursorVisible = _cursorVisible, altScreen = _altScreen;
@synthesize usingDaemon = _daemonMode;
@synthesize screen = _screen;

- (id)initWithRows:(int)rows cols:(int)cols
{
    self = [super init];
    if (self) {
        _rows = rows;
        _cols = cols;
        _fd = -1;
        _cursorVisible = YES;
        _wbuf = [NSMutableData data];
        _rbuf = [NSMutableData data];
        _scrollback = [NSMutableArray array];
        _decodeCarry = [NSMutableData data];
        _dirtyMin = INT_MAX;
        _dirtyMax = -1;

        _vt = vterm_new(rows, cols);
        vterm_set_utf8(_vt, 1);
        _screen = vterm_obtain_screen(_vt);
        vterm_screen_enable_altscreen(_screen, 1);
        vterm_screen_set_callbacks(_screen, &kScreenCallbacks, (__bridge void *)self);
        vterm_screen_set_damage_merge(_screen, VTERM_DAMAGE_ROW);
        vterm_output_set_callback(_vt, cbOutput, (__bridge void *)self);
        vterm_screen_reset(_screen, 1);
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [self teardownTransport];
    if (_vt) vterm_free(_vt);
}

- (NSUInteger)scrollbackCount { return [_scrollback count]; }

#pragma mark - Theme

static void setColor(VTermColor *c, uint32_t hex)
{
    vterm_color_rgb(c, (hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF);
}

- (void)applyTheme
{
    TermTheme *t = [TermTheme current];
    VTermState *state = vterm_obtain_state(_vt);
    VTermColor fg, bg, c;
    int i;
    setColor(&fg, t.fgHex);
    setColor(&bg, t.bgHex);
    for (i = 0; i < 16; i++) {
        setColor(&c, [t ansiHex:i]);
        vterm_state_set_palette_color(state, i, &c);
    }
    vterm_screen_set_default_colors(_screen, &fg, &bg);
    [self markRowsFrom:0 to:_rows - 1];
    [self flushNotifications];
}

#pragma mark - Dirty tracking

- (void)markRowsFrom:(int)a to:(int)b
{
    if (a < _dirtyMin) _dirtyMin = a;
    if (b > _dirtyMax) _dirtyMax = b;
}

- (void)flushNotifications
{
    id<TerminalSessionDelegate> d = self.delegate;
    if (_dirtyMax >= _dirtyMin) {
        int a = _dirtyMin < 0 ? 0 : _dirtyMin;
        int b = _dirtyMax >= _rows ? _rows - 1 : _dirtyMax;
        _dirtyMin = INT_MAX;
        _dirtyMax = -1;
        if (b >= a) [d terminalSession:self didUpdateRows:NSMakeRange(a, b - a + 1)];
    }
    if (_stateDirty) {
        _stateDirty = NO;
        [d terminalSessionDidChangeState:self];
    }
}

#pragma mark - libvterm callbacks

static int cbDamage(VTermRect rect, void *user)
{
    [SELF(user) markRowsFrom:rect.start_row to:rect.end_row - 1];
    return 1;
}

static int cbMoveCursor(VTermPos pos, VTermPos oldpos, int visible, void *user)
{
    TerminalSession *s = SELF(user);
    [s markRowsFrom:oldpos.row to:oldpos.row];
    [s markRowsFrom:pos.row to:pos.row];
    s->_cursorRow = pos.row;
    s->_cursorCol = pos.col;
    s->_cursorVisible = visible ? YES : NO;
    s->_stateDirty = YES;
    return 1;
}

static int cbSetProp(VTermProp prop, VTermValue *val, void *user)
{
    TerminalSession *s = SELF(user);
    switch (prop) {
    case VTERM_PROP_CURSORVISIBLE:
        s->_cursorVisible = val->boolean ? YES : NO;
        s->_stateDirty = YES;
        [s markRowsFrom:s->_cursorRow to:s->_cursorRow];
        break;
    case VTERM_PROP_ALTSCREEN:
        s->_altScreen = val->boolean ? YES : NO;
        s->_stateDirty = YES;
        [s markRowsFrom:0 to:s->_rows - 1];
        break;
    default:
        break;
    }
    return 1;
}

static int cbBell(void *user) { return 1; }

static int cbPushLine(int cols, const VTermScreenCell *cells, void *user)
{
    TerminalSession *s = SELF(user);
    [s->_scrollback addObject:[NSData dataWithBytes:cells length:sizeof(VTermScreenCell) * cols]];
    if ([s->_scrollback count] > MAX_SCROLLBACK + 100)
        [s->_scrollback removeObjectsInRange:NSMakeRange(0, 100)];
    return 1;
}

static int cbPopLine(int cols, VTermScreenCell *cells, void *user)
{
    TerminalSession *s = SELF(user);
    if ([s->_scrollback count] == 0) return 0;
    NSData *line = [s->_scrollback lastObject];
    int have = (int)([line length] / sizeof(VTermScreenCell));
    const VTermScreenCell *src = (const VTermScreenCell *)[line bytes];
    int i;
    for (i = 0; i < cols; i++) {
        if (i < have) {
            cells[i] = src[i];
        } else {
            memset(&cells[i], 0, sizeof(VTermScreenCell));
            cells[i].width = 1;
            cells[i].fg.type = VTERM_COLOR_DEFAULT_FG;
            cells[i].bg.type = VTERM_COLOR_DEFAULT_BG;
        }
    }
    [s->_scrollback removeLastObject];
    return 1;
}

static int cbSbClear(void *user)
{
    [SELF(user)->_scrollback removeAllObjects];
    return 1;
}

static void cbOutput(const char *s, size_t len, void *user)
{
    [SELF(user) sendBytes:s length:len];
}

#pragma mark - Reading screen contents

- (BOOL)getCell:(VTermScreenCell *)cell row:(int)row col:(int)col
{
    VTermPos pos;
    pos.row = row;
    pos.col = col;
    return vterm_screen_get_cell(_screen, pos, cell) ? YES : NO;
}

- (const VTermScreenCell *)scrollbackLine:(NSUInteger)index cols:(int *)cols
{
    if (index >= [_scrollback count]) { *cols = 0; return NULL; }
    NSData *d = [_scrollback objectAtIndex:index];
    *cols = (int)([d length] / sizeof(VTermScreenCell));
    return (const VTermScreenCell *)[d bytes];
}

- (NSString *)screenText
{
    NSMutableString *out = [NSMutableString string];
    int r, c, i;
    for (r = 0; r < _rows; r++) {
        NSMutableString *line = [NSMutableString string];
        for (c = 0; c < _cols; c++) {
            VTermScreenCell cell;
            if (![self getCell:&cell row:r col:c]) continue;
            if (cell.chars[0] == 0) { [line appendString:@" "]; continue; }
            for (i = 0; i < VTERM_MAX_CHARS_PER_CELL && cell.chars[i]; i++) {
                uint32_t cp = cell.chars[i];
                NSString *ch = [[NSString alloc] initWithBytes:&cp length:4 encoding:NSUTF32LittleEndianStringEncoding];
                if (ch) [line appendString:ch];
            }
            if (cell.width == 2) c++;
        }
        NSRange tail = [line rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@" "] invertedSet]
                                             options:NSBackwardsSearch];
        [out appendString:(tail.location == NSNotFound) ? @"" : [line substringToIndex:tail.location + tail.length]];
        [out appendString:@"\n"];
    }
    return out;
}

#pragma mark - Transport lifecycle

+ (BOOL)daemonReachable
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    snprintf(a.sun_path, sizeof a.sun_path, "%s", T6_SOCK_PATH);
    BOOL ok = (connect(fd, (struct sockaddr *)&a, sizeof a) == 0);
    close(fd);
    return ok;
}

- (void)start
{
    if (_fd >= 0) return;
    _ended = NO;

    if ([Settings shared].useDaemon) {
        if ([self connectDaemon]) return;
        [self feedString:@"\x1b[33m[term6] daemon (term6d) not reachable - using a local shell\x1b[0m\r\n"];
    }
    [self startLocal];
}

- (BOOL)connectDaemon
{
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_un a;
    memset(&a, 0, sizeof a);
    a.sun_family = AF_UNIX;
    snprintf(a.sun_path, sizeof a.sun_path, "%s", T6_SOCK_PATH);
    if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) { close(fd); return NO; }
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    fcntl(fd, F_SETFD, FD_CLOEXEC);

    _fd = fd;
    _daemonMode = YES;
    _connected = YES;
    [_rbuf setLength:0];
    [_wbuf setLength:0];
    [self installSources];

    NSUInteger sid = _daemonId;
    if (sid && !_wantNewSession) {
        unsigned char p[8];
        p[0] = sid >> 24; p[1] = sid >> 16; p[2] = sid >> 8; p[3] = sid;
        p[4] = _rxOffset >> 24; p[5] = _rxOffset >> 16; p[6] = _rxOffset >> 8; p[7] = _rxOffset;
        _awaitingAttach = YES;
        [self sendFrame:T6_C_ATTACH payload:p length:8];
    } else {
        [self sendNewSessionRequest];
    }
    return YES;
}

- (void)sendNewSessionRequest
{
    _wantNewSession = NO;
    _awaitingAttach = NO;
    _rxOffset = 0;
    const char *shell = [[Settings shared].shellPath UTF8String];
    const char *lang  = [[TermEncoding current].lang UTF8String];
    size_t sl = strlen(shell), ll = strlen(lang);
    if (sl > 200) sl = 200;
    if (ll > 40) ll = 40;
    unsigned char p[5 + 200 + 1 + 40];
    p[0] = _cols >> 8; p[1] = _cols;
    p[2] = _rows >> 8; p[3] = _rows;
    p[4] = [Settings shared].runAsRoot ? 1 : 0;
    memcpy(p + 5, shell, sl);
    p[5 + sl] = 0;                                   /* "shell\0LANG" */
    memcpy(p + 5 + sl + 1, lang, ll);
    [self sendFrame:T6_C_NEW payload:p length:(uint32_t)(5 + sl + 1 + ll)];
}

/* Types the startup commands into a brand-new shell (not when re-attaching to an existing one). */
- (void)runStartupCommands
{
    NSArray *cmds = [Settings shared].startupCommands;
    if ([cmds count] == 0) return;
    NSMutableString *all = [NSMutableString string];
    for (NSString *c in cmds) [all appendFormat:@"%@\r", c];
    __weak TerminalSession *ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TerminalSession *s = ws;
        if (s && s->_connected) [s sendText:all];     /* the pty buffers it until the shell is ready to read */
    });
}

- (void)startLocal
{
    int master = -1;
    BOOL wantRoot = [Settings shared].runAsRoot;
    if (wantRoot && access(T6_ROOT_HELPER, X_OK) != 0) {
        [self feedString:@"\x1b[33m[term6] root helper missing - starting a normal (mobile) shell\x1b[0m\r\n"];
        wantRoot = NO;
    }
    pid_t pid = t6_spawn(&master, [[Settings shared].shellPath UTF8String], _cols, _rows, wantRoot ? 1 : 0,
                         [[TermEncoding current].lang UTF8String]);
    if (pid < 0) {
        [self feedString:@"\x1b[31m[term6] could not start a shell\x1b[0m\r\n"];
        _ended = YES;
        return;
    }
    _fd = master;
    _pid = pid;
    _daemonMode = NO;
    _connected = YES;
    [self installSources];
    [self runStartupCommands];
}

- (void)installSources
{
    __weak TerminalSession *weakSelf = self;
    int fd = _fd;
    dispatch_queue_t q = dispatch_get_main_queue();

    _readSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, q);
    dispatch_source_set_event_handler(_readSrc, ^{ [weakSelf readable]; });
    dispatch_source_set_cancel_handler(_readSrc, ^{ close(fd); });
    dispatch_resume(_readSrc);

    _writeSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, q);
    dispatch_source_set_event_handler(_writeSrc, ^{ [weakSelf flushWrites]; });
    _writeSrcActive = NO;                       /* created suspended; resumed on demand */
}

- (void)teardownTransport
{
    if (_writeSrc) {
        dispatch_source_cancel(_writeSrc);
        if (!_writeSrcActive) dispatch_resume(_writeSrc);   /* a suspended source must be resumed before release */
        _writeSrc = nil;
        _writeSrcActive = NO;
    }
    if (_readSrc) {
        dispatch_source_cancel(_readSrc);       /* cancel handler closes the fd */
        _readSrc = nil;
    }
    _fd = -1;
    _connected = NO;
    [_wbuf setLength:0];
}

- (void)restart
{
    if (_connected) {
        if (_daemonMode) {
            [self sendFrame:T6_C_KILL payload:NULL length:0];
            [self flushWrites];
        } else if (_pid > 0) {
            kill(_pid, SIGHUP);
        }
    }
    [self teardownTransport];
    [self setDaemonIdValue:0];
    _wantNewSession = YES;
    _rxOffset = 0;
    [self feedString:@"\033c"];                 /* RIS: full terminal reset */
    [_scrollback removeAllObjects];
    _stateDirty = YES;
    [self markRowsFrom:0 to:_rows - 1];
    [self flushNotifications];
    [self start];
}

- (void)setDaemonIdValue:(NSUInteger)v
{
    if (_daemonId == v) return;
    _daemonId = v;
    if (self.onIdentityChange) self.onIdentityChange();
}

- (void)closeSession
{
    if (_connected) {
        if (_daemonMode) {
            [self sendFrame:T6_C_KILL payload:NULL length:0];
            [self flushWrites];
        } else if (_pid > 0) {
            kill(_pid, SIGHUP);
        }
    }
    [self teardownTransport];
    _ended = YES;
    self.delegate = nil;
    [self setDaemonIdValue:0];
}

- (void)reconnectIfNeeded
{
    if (!_daemonMode || _ended) return;
    /* After a suspend the socket may be stale; re-attach and ask only for what we missed. */
    [self teardownTransport];
    if (![self connectDaemon]) {
        [self feedString:@"\r\n\x1b[33m[term6] lost connection to term6d\x1b[0m\r\n"];
        _ended = YES;
    }
}

- (void)sessionEnded:(NSString *)why
{
    [self teardownTransport];
    [self setDaemonIdValue:0];
    _ended = YES;
    [self feedString:[NSString stringWithFormat:@"\r\n\x1b[2m[%@ - press any key to restart]\x1b[0m\r\n", why]];
}

#pragma mark - Reading from the shell / daemon

/* Bytes from the shell: convert from the chosen text encoding to UTF-8 (which is what libvterm
   is always fed). UTF-8 passes straight through. */
- (void)feedHostBytes:(const void *)bytes length:(size_t)len
{
    TermEncoding *enc = [TermEncoding current];
    if (enc.encoding == NSUTF8StringEncoding) {
        [_decodeCarry setLength:0];
        [self feedBytes:bytes length:len];
        return;
    }

    NSMutableData *in = [NSMutableData data];
    if ([_decodeCarry length] > 0 && _carryEncoding == enc.encoding) [in appendData:_decodeCarry];
    [_decodeCarry setLength:0];
    [in appendBytes:bytes length:len];

    NSString *str = [[NSString alloc] initWithData:in encoding:enc.encoding];
    if (!str) {                                   /* maybe a multi-byte character was cut at the end: hold it back */
        NSUInteger n = [in length], cut;
        for (cut = 1; cut <= 3 && cut < n && !str; cut++) {
            NSData *head = [in subdataWithRange:NSMakeRange(0, n - cut)];
            str = [[NSString alloc] initWithData:head encoding:enc.encoding];
            if (str) {
                [_decodeCarry appendBytes:(const unsigned char *)[in bytes] + (n - cut) length:cut];
                _carryEncoding = enc.encoding;
            }
        }
    }
    if (!str) str = [[NSString alloc] initWithData:in encoding:NSISOLatin1StringEncoding];   /* never fails */
    if (!str) return;
    NSData *u = [str dataUsingEncoding:NSUTF8StringEncoding];
    [self feedBytes:[u bytes] length:[u length]];
}

- (void)feedString:(NSString *)s
{
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    [self feedBytes:[d bytes] length:[d length]];
}

static BOOL containsSeq(const unsigned char *b, size_t n, const char *seq)
{
    size_t m = strlen(seq), i;
    if (n < m) return NO;
    for (i = 0; i + m <= n; i++)
        if (memcmp(b + i, seq, m) == 0) return YES;
    return NO;
}

- (void)feedBytes:(const void *)bytes length:(size_t)len
{
    vterm_input_write(_vt, (const char *)bytes, len);
    vterm_screen_flush_damage(_screen);

    /* `clear`, `reset`, ESC[J ... : make sure every row is repainted, so no stale pixels of the
       old screen can survive a partial invalidation. */
    const unsigned char *b = (const unsigned char *)bytes;
    if (containsSeq(b, len, "\033[2J") || containsSeq(b, len, "\033[J") || containsSeq(b, len, "\033[0J") ||
        containsSeq(b, len, "\033[3J") || containsSeq(b, len, "\033c"))
        [self markRowsFrom:0 to:_rows - 1];

    [self flushNotifications];
}

- (void)readable
{
    unsigned char buf[16384];
    ssize_t n = read(_fd, buf, sizeof buf);
    if (n < 0 && (errno == EAGAIN || errno == EINTR)) return;

    if (!_daemonMode) {
        if (n > 0) [self feedHostBytes:buf length:(size_t)n];
        else [self sessionEnded:@"Process completed"];
        return;
    }

    if (n <= 0) {                                  /* daemon went away or the app was suspended */
        [self teardownTransport];
        return;                                    /* reconnectIfNeeded / next keypress re-attaches */
    }
    [_rbuf appendBytes:buf length:(NSUInteger)n];
    [self parseFrames];
}

static uint32_t rd32(const unsigned char *p)
{ return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

- (void)parseFrames
{
    for (;;) {
        NSUInteger have = [_rbuf length];
        if (have < 5) return;
        const unsigned char *b = (const unsigned char *)[_rbuf bytes];
        uint32_t len = rd32(b + 1);
        if (have < 5 + (NSUInteger)len) return;

        unsigned char type = b[0];
        NSData *payload = [NSData dataWithBytes:b + 5 length:len];   /* copy: _rbuf is about to change */
        [_rbuf replaceBytesInRange:NSMakeRange(0, 5 + len) withBytes:NULL length:0];
        [self handleFrame:type payload:payload];
        if (!_connected) return;
    }
}

- (void)handleFrame:(unsigned char)type payload:(NSData *)payload
{
    const unsigned char *p = (const unsigned char *)[payload bytes];
    NSUInteger len = [payload length];

    switch (type) {
    case T6_S_SESSION:
        _awaitingAttach = NO;
        if (len >= 4) {
            [self setDaemonIdValue:rd32(p)];
            _rxOffset = 0;
            [self runStartupCommands];                   /* a new daemon session, not a re-attach */
        }
        break;
    case T6_S_ATTACHED:
        _awaitingAttach = NO;
        if (len >= 5) {
            if (p[0]) {                                 /* history was cut: start from a clean slate */
                [self feedString:@"\033c"];
                [_scrollback removeAllObjects];
            }
            _rxOffset = rd32(p + 1);
        }
        break;
    case T6_S_OUTPUT:
        _rxOffset += (uint32_t)len;
        [self feedHostBytes:p length:len];
        break;
    case T6_S_EXIT:
        [self sessionEnded:@"Process completed"];
        break;
    case T6_S_ERROR:
        if (_awaitingAttach) {
            /* Session is gone (daemon restarted, phone rebooted...): start a new one. */
            [self setDaemonIdValue:0];
            [self feedString:@"\r\n\x1b[33m[term6] previous session is gone - starting a new one\x1b[0m\r\n"];
            [self sendNewSessionRequest];
        } else {
            [self sessionEnded:@"Daemon error"];
        }
        break;
    default:
        break;
    }
}

#pragma mark - Writing to the shell / daemon

- (void)sendFrame:(unsigned char)type payload:(const void *)payload length:(uint32_t)len
{
    if (!_connected || !_daemonMode) return;
    unsigned char hdr[5] = { type, len >> 24, len >> 16, len >> 8, len };
    [_wbuf appendBytes:hdr length:5];
    if (len) [_wbuf appendBytes:payload length:len];
    [self flushWrites];
}

- (void)flushWrites
{
    while ([_wbuf length] > 0 && _fd >= 0) {
        ssize_t n = write(_fd, [_wbuf bytes], [_wbuf length]);
        if (n > 0) {
            [_wbuf replaceBytesInRange:NSMakeRange(0, (NSUInteger)n) withBytes:NULL length:0];
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;                                   /* EAGAIN (or error): wait for writability */
        }
    }
    if (_writeSrc) {
        BOOL need = ([_wbuf length] > 0);
        if (need && !_writeSrcActive)  { dispatch_resume(_writeSrc);  _writeSrcActive = YES; }
        if (!need && _writeSrcActive)  { dispatch_suspend(_writeSrc); _writeSrcActive = NO; }
    }
}

- (void)sendBytes:(const void *)bytes length:(size_t)length
{
    if (length == 0) return;

    if (_ended) { [self restart]; return; }           /* any key restarts a finished session */
    if (!_connected) {
        if (_daemonMode) { [self reconnectIfNeeded]; }
        if (!_connected) return;
    }

    if (_daemonMode) {
        size_t off = 0;
        while (off < length) {
            size_t chunk = length - off;
            if (chunk > 16384) chunk = 16384;
            [self sendFrame:T6_C_INPUT payload:(const unsigned char *)bytes + off length:(uint32_t)chunk];
            off += chunk;
        }
    } else {
        [_wbuf appendBytes:bytes length:length];
        [self flushWrites];
    }
}

- (NSData *)encodeString:(NSString *)string
{
    NSData *d = [string dataUsingEncoding:[TermEncoding current].encoding allowLossyConversion:YES];
    return d ? d : [string dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)sendText:(NSString *)text
{
    NSData *d = [self encodeString:text];
    [self sendBytes:[d bytes] length:[d length]];
}

- (void)sendString:(NSString *)string { [self sendText:string]; }

- (void)sendKey:(VTermKey)key
{
    vterm_keyboard_key(_vt, key, VTERM_MOD_NONE);      /* comes back through cbOutput */
}

#pragma mark - Resize

- (void)resizeRows:(int)rows cols:(int)cols
{
    if (rows < 2 || cols < 10) return;
    if (rows == _rows && cols == _cols) return;
    _rows = rows;
    _cols = cols;
    vterm_set_size(_vt, rows, cols);
    vterm_screen_flush_damage(_screen);
    [self markRowsFrom:0 to:rows - 1];
    _stateDirty = YES;
    [self flushNotifications];

    if (_connected) {
        if (_daemonMode) {
            unsigned char p[4] = { cols >> 8, cols, rows >> 8, rows };
            [self sendFrame:T6_C_RESIZE payload:p length:4];
        } else {
            t6_set_winsize(_fd, cols, rows);
        }
    }
}

@end
