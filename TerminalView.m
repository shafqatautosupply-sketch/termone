#import "TerminalView.h"
#import "Settings.h"
#import "TermTheme.h"
#import "Term6Application.h"

#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPad = 3.0f;

#pragma mark - SelectionHandle (iOS 6 style grabber: a line with a knob)

@interface SelectionHandle : UIView
@property (nonatomic, assign) BOOL isStart;
@property (nonatomic, assign) CGFloat lineHeight;
@end

@implementation SelectionHandle

- (id)initWithStart:(BOOL)isStart lineHeight:(CGFloat)h
{
    self = [super initWithFrame:CGRectMake(0, 0, 30, h + 9)];
    if (self) {
        _isStart = isStart;
        _lineHeight = h;
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat cx = self.bounds.size.width / 2;
    CGContextSetRGBFillColor(c, 0.18f, 0.42f, 0.90f, 1);
    CGRect line, knob;
    if (_isStart) {
        knob = CGRectMake(cx - 4.5f, 0, 9, 9);
        line = CGRectMake(cx - 1, 8, 2, _lineHeight + 1);
    } else {
        line = CGRectMake(cx - 1, 0, 2, _lineHeight);
        knob = CGRectMake(cx - 4.5f, _lineHeight, 9, 9);
    }
    CGContextFillRect(c, line);
    CGContextFillEllipseInRect(c, knob);
    CGContextSetRGBStrokeColor(c, 1, 1, 1, 0.9f);
    CGContextSetLineWidth(c, 1);
    CGContextStrokeEllipseInRect(c, CGRectInset(knob, 0.5f, 0.5f));
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e
{
    return CGRectContainsPoint(CGRectInset(self.bounds, -10, -10), p);      /* generous touch target */
}

@end

#pragma mark - TerminalView

@interface TerminalView () {
    CTFontRef _ctFont, _ctBold;
    CGFontRef _cgFont, _cgBold;
    UIFont   *_fallbackFont;
    CGFloat   _fontSize, _cellW, _cellH, _ascent;
    CGGlyph   _ascii[2][128];

    CGFloat    _scrollPos;             /* points scrolled back into history, 0 = live screen (pixel precise) */
    int        _scrollOffset;          /* whole lines of _scrollPos */
    CGFloat    _scrollFrac;            /* leftover points, 0 ..< cellH: the whole picture is shifted down by this */
    UIScrollView *_scroller;           /* transparent overlay: supplies the drag, momentum, snapping and indicator */
    BOOL       _syncingScroll;         /* ignore scrollViewDidScroll: while we move the offset ourselves */
    UIPanGestureRecognizer *_altPan;   /* drag = arrow keys, only on the alternate screen */
    NSUInteger _lastScrollbackCount;
    CGFloat    _panAccum;
    CGFloat    _pinchBase;

    BOOL     _blinkOn;
    NSTimer *_blinkTimer;

    TerminalSession *_session;
    KeyBarView *_keyBar;

    BOOL   _keyboardHidden;
    UIView *_emptyInput;

    /* selection: absolute line numbers (0 = oldest scrollback line), inclusive cell range */
    BOOL _hasSelection;
    NSInteger _selStartLine, _selEndLine;
    int _selStartCol, _selEndCol;
    SelectionHandle *_startHandle, *_endHandle;
    BOOL _draggingStart;
    CGPoint _dragOrigin;

    /* key repeat for Backspace */
    NSTimer *_deleteHoldTimer, *_deleteRepeatTimer;
    BOOL _deleteRepeating;
    int _deleteRepeatCount;
}
@end

@implementation TerminalView

@synthesize session = _session;
@synthesize keyBar = _keyBar;
@synthesize keyboardHidden = _keyboardHidden;

#pragma mark - Setup

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = YES;
        self.clearsContextBeforeDrawing = NO;
        self.contentMode = UIViewContentModeRedraw;
        _blinkOn = YES;
        [self rebuildFont];
        self.backgroundColor = [[TermTheme current] bgColor];

        _emptyInput = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];   /* "no keyboard" input view */
        _emptyInput.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _emptyInput.backgroundColor = [UIColor clearColor];

        _scroller = [[UIScrollView alloc] initWithFrame:self.bounds];
        _scroller.delegate = self;
        _scroller.backgroundColor = [UIColor clearColor];
        _scroller.opaque = NO;
        _scroller.bounces = YES;                                   /* native rubber band at both ends of the history */
        _scroller.alwaysBounceVertical = YES;
        _scroller.showsHorizontalScrollIndicator = NO;
        _scroller.panGestureRecognizer.maximumNumberOfTouches = 1; /* two fingers are the pinch */
        [self addSubview:_scroller];
        [self updateIndicatorStyle];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        pan.delegate = self;
        pan.enabled = NO;                                          /* on only while the alternate screen is up */
        _altPan = pan;
        [self addGestureRecognizer:pan];

        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        pinch.delegate = self;
        [self addGestureRecognizer:pinch];

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.5;
        lp.delegate = self;
        [self addGestureRecognizer:lp];
    }
    return self;
}

- (void)dealloc
{
    _scroller.delegate = nil;                      /* the delegate is not a weak reference on iOS 5/6 */
    [_blinkTimer invalidate];
    [_deleteHoldTimer invalidate];
    [_deleteRepeatTimer invalidate];
    if (_ctFont) CFRelease(_ctFont);
    if (_ctBold) CFRelease(_ctBold);
    if (_cgFont) CGFontRelease(_cgFont);
    if (_cgBold) CGFontRelease(_cgBold);
}

- (void)setSession:(TerminalSession *)session
{
    if (_session == session) return;
    _session.delegate = nil;
    _session = session;
    session.delegate = self;
    [self resetScroll];
    [self stopInertia];
    [self clearSelection];
    _lastScrollbackCount = session.scrollbackCount;
    [self syncGridSize];
    [self updateScrollMode];
    [self updateScrollerGeometry];
    [self setNeedsDisplay];
}

- (void)setKeyBar:(KeyBarView *)keyBar
{
    _keyBar = keyBar;
    keyBar.delegate = self;
}

/* "Keyboard hidden" while this view is first responder (needed for the Copy / Paste menu) is shown
   with an empty 1pt input view, so no keyboard appears. */
- (UIView *)inputView { return _keyboardHidden ? _emptyInput : nil; }

/* Hide = resign first responder, show = become first responder: UIKit animates both natively.
   The key bar lives in the view controller, so it stays visible either way. */
- (void)setKeyboardHidden:(BOOL)hidden
{
    if (_keyboardHidden == hidden) {
        if (!hidden && ![self isFirstResponder]) [self becomeFirstResponder];
        return;
    }
    if (hidden) {
        /* Resign BEFORE flipping the flag: while the keyboard is leaving, inputView must still be nil.
           If it already returned the empty view, UIKit treats the hide as "the input view was swapped",
           and the next show comes up without its slide-up animation. */
        if ([self isFirstResponder]) [self resignFirstResponder];
        _keyboardHidden = YES;
    } else if ([self isFirstResponder]) {                    /* currently first responder with the empty input view */
        [self resignFirstResponder];
        _keyboardHidden = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ if (!_keyboardHidden) [self becomeFirstResponder]; });
    } else {
        _keyboardHidden = NO;
        [self becomeFirstResponder];
    }
}

#pragma mark - Fonts and metrics

- (void)rebuildFont
{
    if (_ctFont) { CFRelease(_ctFont); _ctFont = NULL; }
    if (_ctBold) { CFRelease(_ctBold); _ctBold = NULL; }
    if (_cgFont) { CGFontRelease(_cgFont); _cgFont = NULL; }
    if (_cgBold) { CGFontRelease(_cgBold); _cgBold = NULL; }

    _fontSize = [Settings shared].fontSize;
    BOOL haveMenlo = ([UIFont fontWithName:@"Menlo-Regular" size:_fontSize] != nil);
    CFStringRef reg  = haveMenlo ? CFSTR("Menlo-Regular") : CFSTR("Courier");
    CFStringRef bold = haveMenlo ? CFSTR("Menlo-Bold")    : CFSTR("Courier-Bold");

    _ctFont = CTFontCreateWithName(reg,  _fontSize, NULL);
    _ctBold = CTFontCreateWithName(bold, _fontSize, NULL);
    _cgFont = CTFontCopyGraphicsFont(_ctFont, NULL);
    _cgBold = CTFontCopyGraphicsFont(_ctBold, NULL);
    _fallbackFont = [UIFont systemFontOfSize:_fontSize];

    UniChar m = 'M';
    CGGlyph gm = 0;
    CGSize adv = CGSizeZero;
    CTFontGetGlyphsForCharacters(_ctFont, &m, &gm, 1);
    CTFontGetAdvancesForGlyphs(_ctFont, kCTFontDefaultOrientation, &gm, &adv, 1);
    _cellW = adv.width > 0 ? adv.width : ceilf(_fontSize * 0.6f);

    _ascent = CTFontGetAscent(_ctFont);
    _cellH = ceilf(_ascent + CTFontGetDescent(_ctFont) + CTFontGetLeading(_ctFont));

    int b, i;
    for (b = 0; b < 2; b++) {
        CTFontRef f = b ? _ctBold : _ctFont;
        for (i = 0; i < 128; i++) {
            UniChar u = (UniChar)i;
            CGGlyph g = 0;
            if (i >= 0x20 && i < 0x7F) CTFontGetGlyphsForCharacters(f, &u, &g, 1);
            _ascii[b][i] = g;
        }
    }

    [_startHandle removeFromSuperview]; _startHandle = nil;       /* sized for the old font */
    [_endHandle removeFromSuperview];   _endHandle = nil;
}

- (int)visibleCols
{
    if (_cellW <= 0) return 80;
    int c = (int)floorf((self.bounds.size.width - 2 * kPad) / _cellW);
    return c < 10 ? 10 : c;
}

- (int)visibleRows
{
    if (_cellH <= 0) return 24;
    int r = (int)floorf((self.bounds.size.height - 2 * kPad) / _cellH);
    return r < 2 ? 2 : r;
}

- (void)reloadAppearance
{
    [self rebuildFont];
    [self updateIndicatorStyle];
    [self resetScroll];
    self.backgroundColor = [[TermTheme current] bgColor];
    [_session applyTheme];
    [self syncGridSize];
    [self updateSelectionHandles];
    [self setNeedsDisplay];
}

- (void)syncGridSize
{
    int rows = self.visibleRows, cols = self.visibleCols;
    [_session resizeRows:rows cols:cols];
    if (self.onGridChange) self.onGridChange(rows, cols);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self syncGridSize];
    [self updateScrollerGeometry];
    [self updateSelectionHandles];
}

#pragma mark - Cursor blink / focus

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [_blinkTimer invalidate];
    _blinkTimer = nil;
    if (!self.window) [self stopInertia];
    if (self.window) {
        _blinkTimer = [NSTimer scheduledTimerWithTimeInterval:0.55 target:self selector:@selector(blink:) userInfo:nil repeats:YES];
    }
}

- (void)blink:(NSTimer *)t
{
    if (!([self isFirstResponder] || _keyboardHidden) || !_session) return;
    _blinkOn = !_blinkOn;
    [self invalidateRow:_session.cursorRow];
}

- (void)invalidateRow:(int)row
{
    if (_scrollPos > 0) return;
    if (_scrollPos < 0) { [self setNeedsDisplay]; return; }       /* rubber-banding: the picture is shifted */
    [self setNeedsDisplayInRect:CGRectMake(0, kPad + row * _cellH, self.bounds.size.width, _cellH)];
}

- (BOOL)canBecomeFirstResponder { return YES; }

- (BOOL)becomeFirstResponder
{
    BOOL ok = [super becomeFirstResponder];
    _blinkOn = YES;
    [self setNeedsDisplay];
    return ok;
}

- (BOOL)resignFirstResponder
{
    [self stopDeleteRepeat];
    BOOL ok = [super resignFirstResponder];
    [self setNeedsDisplay];
    return ok;
}

#pragma mark - Drawing

static void cellColors(VTermScreen *scr, const VTermScreenCell *cell, uint32_t *fg, uint32_t *bg)
{
    VTermColor f = cell->fg, b = cell->bg;
    vterm_screen_convert_color_to_rgb(scr, &f);
    vterm_screen_convert_color_to_rgb(scr, &b);
    uint32_t F = ((uint32_t)f.rgb.red << 16) | ((uint32_t)f.rgb.green << 8) | f.rgb.blue;
    uint32_t B = ((uint32_t)b.rgb.red << 16) | ((uint32_t)b.rgb.green << 8) | b.rgb.blue;
    if (cell->attrs.reverse) { *fg = B; *bg = F; } else { *fg = F; *bg = B; }
}

static void setFill(CGContextRef ctx, uint32_t hex)
{
    CGContextSetRGBFillColor(ctx, ((hex >> 16) & 0xFF) / 255.0f, ((hex >> 8) & 0xFF) / 255.0f, (hex & 0xFF) / 255.0f, 1.0f);
}

static void blankCell(VTermScreenCell *c)
{
    memset(c, 0, sizeof *c);
    c->width = 1;
    c->fg.type = VTERM_COLOR_DEFAULT_FG;
    c->bg.type = VTERM_COLOR_DEFAULT_BG;
}

- (CGGlyph)glyphForCodepoint:(uint32_t)cp bold:(BOOL)bold
{
    if (cp >= 0x20 && cp < 0x7F) return _ascii[bold ? 1 : 0][cp];
    if (cp > 0xFFFF) return 0;
    UniChar u = (UniChar)cp;
    CGGlyph g = 0;
    if (!CTFontGetGlyphsForCharacters(bold ? _ctBold : _ctFont, &u, &g, 1)) return 0;
    return g;
}

- (void)drawRun:(CGContextRef)ctx x:(CGFloat)x baseline:(CGFloat)yb count:(int)n
         glyphs:(CGGlyph *)g advances:(CGSize *)a fg:(uint32_t)fg bold:(BOOL)bold
{
    if (n <= 0) return;
    setFill(ctx, fg);
    CGContextSetFont(ctx, bold ? _cgBold : _cgFont);
    CGContextSetFontSize(ctx, _fontSize);
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(1, 0, 0, -1, x, yb));   /* flipped: UIKit has y pointing down */
    CGContextShowGlyphsWithAdvances(ctx, g, a, n);
}

- (void)drawRect:(CGRect)dirty
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    TermTheme *theme = [TermTheme current];
    setFill(ctx, theme.bgHex);
    CGContextFillRect(ctx, dirty);

    if (!_session || _cellH <= 0) return;

    int first = (int)floorf((dirty.origin.y - kPad - _scrollFrac) / _cellH);
    int last  = (int)floorf((CGRectGetMaxY(dirty) - kPad - _scrollFrac) / _cellH);
    if (first < 0) first = (_scrollFrac > 0) ? -1 : 0;
    if (last >= _session.rows) last = _session.rows - 1;
    int r;
    for (r = first; r <= last; r++) [self drawRow:r context:ctx theme:theme];
}

- (void)drawRow:(int)r context:(CGContextRef)ctx theme:(TermTheme *)theme
{
    TerminalSession *s = _session;
    int cols = s.cols;
    if (cols <= 0) return;
    VTermScreen *scr = s.screen;

    VTermScreenCell buf[cols];
    VTermScreenCell blank;
    blankCell(&blank);

    const VTermScreenCell *cells = buf;
    int have = cols;
    int v = r - _scrollOffset;                       /* >= 0: live screen row, < 0: history */
    int c;
    if (v >= 0) {
        for (c = 0; c < cols; c++)
            if (![s getCell:&buf[c] row:v col:c]) buf[c] = blank;
    } else {
        NSInteger idx = (NSInteger)s.scrollbackCount + v;
        if (idx < 0) return;
        cells = [s scrollbackLine:(NSUInteger)idx cols:&have];
        if (!cells) return;
    }
#define CELL(i) ((i) < have ? &cells[(i)] : &blank)

    BOOL cursorHere = (_scrollOffset <= 0 && v == s.cursorRow && s.cursorVisible && s.cursorCol < cols);
    BOOL focused = [self isFirstResponder] || _keyboardHidden;
    BOOL solidCursor = cursorHere && focused && _blinkOn && !_hasSelection;

    uint32_t fgs[cols], bgs[cols];
    for (c = 0; c < cols; c++) cellColors(scr, CELL(c), &fgs[c], &bgs[c]);
    if (solidCursor) {
        int cc = s.cursorCol;
        int span = (CELL(cc)->width == 2 && cc + 1 < cols) ? 2 : 1;
        int k;
        for (k = 0; k < span; k++) {
            uint32_t t = fgs[cc + k]; fgs[cc + k] = bgs[cc + k]; bgs[cc + k] = t;
        }
    }

    CGFloat y = kPad + r * _cellH + _scrollFrac;

    /* 1. backgrounds (only where they differ from the theme background) */
    c = 0;
    while (c < cols) {
        int start = c;
        uint32_t b = bgs[c];
        while (c < cols && bgs[c] == b) c++;
        if (b != theme.bgHex) {
            CGFloat x0 = floorf(kPad + start * _cellW);
            CGFloat x1 = ceilf(kPad + c * _cellW);
            setFill(ctx, b);
            CGContextFillRect(ctx, CGRectMake(x0, y, x1 - x0, _cellH));
        }
    }

    /* 1b. selection highlight (under the text) */
    if (_hasSelection) {
        NSInteger absLine = (NSInteger)s.scrollbackCount - _scrollOffset + r;
        if (absLine >= _selStartLine && absLine <= _selEndLine) {
            int c0 = (absLine == _selStartLine) ? _selStartCol : 0;
            int c1 = (absLine == _selEndLine) ? _selEndCol : cols - 1;
            if (c1 >= cols) c1 = cols - 1;
            if (c1 >= c0) {
                CGContextSetRGBFillColor(ctx, 0.25f, 0.50f, 1.0f, 0.38f);
                CGFloat x0 = floorf(kPad + c0 * _cellW);
                CGFloat x1 = ceilf(kPad + (c1 + 1) * _cellW);
                CGContextFillRect(ctx, CGRectMake(x0, y, x1 - x0, _cellH));
            }
        }
    }

    /* 2. text, one Core Graphics call per run of equally styled cells */
    CGGlyph glyphs[cols];
    CGSize advs[cols];
    int runCount = 0;
    CGFloat runX = 0;
    uint32_t runFg = 0;
    BOOL runBold = NO;
    CGFloat baseline = y + _ascent;

    for (c = 0; c < cols; c++) {
        const VTermScreenCell *cell = CELL(c);
        uint32_t cp = cell->chars[0];
        CGFloat x = kPad + c * _cellW;

        if (cell->attrs.underline) {
            setFill(ctx, fgs[c]);
            CGContextFillRect(ctx, CGRectMake(x, baseline + 1.5f, _cellW * (cell->width == 2 ? 2 : 1), 1.0f));
        }
        if (cell->attrs.conceal) cp = 0;

        if (cp == (uint32_t)-1) continue;                    /* right half of a wide character */
        if (cp == 0 || cp == ' ') {
            if (runCount > 0) {                              /* keep the run contiguous across spaces */
                glyphs[runCount] = _ascii[0][' '];
                advs[runCount] = CGSizeMake(_cellW, 0);
                runCount++;
            }
            continue;
        }

        BOOL bold = cell->attrs.bold ? YES : NO;
        CGGlyph g = (cell->width == 2) ? 0 : [self glyphForCodepoint:cp bold:bold];
        if (g == 0) {                                        /* wide or missing glyph: draw it on its own */
            [self drawRun:ctx x:runX baseline:baseline count:runCount glyphs:glyphs advances:advs fg:runFg bold:runBold];
            runCount = 0;
            NSString *str = nil;
            if (cp > 0xFFFF) str = [[NSString alloc] initWithBytes:&cp length:4 encoding:NSUTF32LittleEndianStringEncoding];
            else { unichar u = (unichar)cp; str = [NSString stringWithCharacters:&u length:1]; }
            if (str) {
                setFill(ctx, fgs[c]);
                [str drawAtPoint:CGPointMake(x, y) withFont:_fallbackFont];
            }
            continue;
        }

        if (runCount > 0 && (runFg != fgs[c] || runBold != bold)) {
            [self drawRun:ctx x:runX baseline:baseline count:runCount glyphs:glyphs advances:advs fg:runFg bold:runBold];
            runCount = 0;
        }
        if (runCount == 0) { runX = x; runFg = fgs[c]; runBold = bold; }
        glyphs[runCount] = g;
        advs[runCount] = CGSizeMake(_cellW, 0);
        runCount++;
    }
    [self drawRun:ctx x:runX baseline:baseline count:runCount glyphs:glyphs advances:advs fg:runFg bold:runBold];

    /* 3. hollow cursor while the view is not first responder */
    if (cursorHere && !focused) {
        CGContextSetRGBStrokeColor(ctx, ((theme.fgHex >> 16) & 0xFF) / 255.0f, ((theme.fgHex >> 8) & 0xFF) / 255.0f, (theme.fgHex & 0xFF) / 255.0f, 1.0f);
        CGContextStrokeRect(ctx, CGRectMake(kPad + s.cursorCol * _cellW + 0.5f, y + 0.5f, _cellW - 1.0f, _cellH - 1.0f));
    }
#undef CELL
}

#pragma mark - TerminalSessionDelegate

- (void)terminalSession:(TerminalSession *)session didUpdateRows:(NSRange)rows
{
    if (session != _session) return;

    NSUInteger sb = session.scrollbackCount;
    BOOL historyChanged = (sb != _lastScrollbackCount);
    if (sb < _lastScrollbackCount) [self clearSelection];          /* oldest history was trimmed: indices moved */
    if (_scrollPos > 0 && sb > _lastScrollbackCount)
        _scrollPos += (CGFloat)(sb - _lastScrollbackCount) * _cellH;   /* keep what the user is reading in place */
    _lastScrollbackCount = sb;
    [self applyScrollPos:_scrollPos];
    if (historyChanged) [self updateScrollerGeometry];             /* the scrollable height follows the history */

    if (_hasSelection) [self updateSelectionHandles];
    if (_scrollPos != 0 || _hasSelection) { [self setNeedsDisplay]; return; }
    [self setNeedsDisplayInRect:CGRectMake(0, kPad + rows.location * _cellH, self.bounds.size.width, rows.length * _cellH + 1)];
}

- (void)terminalSessionDidChangeState:(TerminalSession *)session
{
    if (session != _session) return;
    [self updateScrollMode];
    if (session.altScreen && _scrollPos > 0) [self resetScroll];
    _blinkOn = YES;
    [self invalidateRow:session.cursorRow];
}

#pragma mark - Gestures

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch
{
    return ![touch.view isKindOfClass:[SelectionHandle class]];      /* selection handles have their own pan */
}

- (void)handleTap:(UITapGestureRecognizer *)g
{
    [[UIMenuController sharedMenuController] setMenuVisible:NO animated:YES];
    if (_hasSelection) { [self clearSelection]; return; }
    if (!_keyboardHidden && ![self isFirstResponder]) { [self becomeFirstResponder]; return; }
    [self setKeyboardHidden:!_keyboardHidden];                       /* tap = slide the keyboard away / back */
}

/* Only enabled on the alternate screen (vim, less, man): a drag turns into arrow keys. */
- (void)handlePan:(UIPanGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) _panAccum = 0;
    if (g.state != UIGestureRecognizerStateBegan && g.state != UIGestureRecognizerStateChanged) return;

    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    _panAccum += t.y;
    int lines = (int)(_panAccum / _cellH);
    if (lines == 0) return;
    _panAccum -= lines * _cellH;
    int i, n = abs(lines);
    for (i = 0; i < n; i++) [_session sendKey:(lines > 0 ? VTERM_KEY_UP : VTERM_KEY_DOWN)];
}

#pragma mark - Scrolling (a UIScrollView supplies drag, momentum, snapping and the indicator)

/* The scroll view's content is as tall as the view plus the history. Offset 0 = oldest line,
   offset maxPos = live screen, so   _scrollPos = maxPos - contentOffset.y . */

- (CGFloat)maxScrollPos { return (CGFloat)_session.scrollbackCount * _cellH; }

- (void)resetScroll
{
    _scrollPos = 0;
    _scrollOffset = 0;
    _scrollFrac = 0;
    [self updateScrollerGeometry];
}

/* Derives whole lines + leftover points from a position in points. Not clamped: while the scroll
   view rubber-bands, p is below 0 (pulled past the live screen) or above the history size
   (pulled past the oldest line), and the picture is drawn shifted accordingly. */
- (void)applyScrollPos:(CGFloat)p
{
    _scrollPos = p;
    int whole = (_cellH > 0) ? (int)floorf(p / _cellH) : 0;
    _scrollOffset = whole;
    _scrollFrac = p - whole * _cellH;
    if (_scrollFrac < 0.01f) _scrollFrac = 0;
}

/* Size / offset of the scroll view after a resize, a font change or the history growing. */
- (void)updateScrollerGeometry
{
    CGSize bs = self.bounds.size;
    CGFloat maxPos = [self maxScrollPos];
    BOOL busy = _scroller.dragging || _scroller.decelerating;
    if (!busy) {                                                   /* at rest the position must lie inside the history */
        CGFloat p = _scrollPos;
        if (p > maxPos) p = maxPos;
        if (p < 0) p = 0;
        if (p != _scrollPos) [self applyScrollPos:p];
    }
    CGFloat wanted = maxPos - _scrollPos;

    _syncingScroll = YES;
    _scroller.frame = self.bounds;
    _scroller.contentSize = CGSizeMake(bs.width, bs.height + maxPos);
    if ((!busy || _scrollPos <= 0) && fabsf(_scroller.contentOffset.y - wanted) > 0.01f)
        _scroller.contentOffset = CGPointMake(0, wanted);          /* sticks to the live screen while output scrolls */
    _syncingScroll = NO;
}

- (void)updateScrollMode
{
    BOOL alt = _session.altScreen;
    _scroller.scrollEnabled = !alt;
    _altPan.enabled = alt;
}

- (void)updateIndicatorStyle
{
    uint32_t bg = [TermTheme current].bgHex;
    CGFloat lum = (((bg >> 16) & 0xFF) * 0.299f + ((bg >> 8) & 0xFF) * 0.587f + (bg & 0xFF) * 0.114f) / 255.0f;
    _scroller.indicatorStyle = (lum > 0.5f) ? UIScrollViewIndicatorStyleBlack : UIScrollViewIndicatorStyleWhite;
}

/* Typing, switching tabs, a long press: stop a coasting scroll right where it is. */
- (void)stopInertia
{
    if (!_scroller.decelerating) return;
    _syncingScroll = YES;
    [_scroller setContentOffset:_scroller.contentOffset animated:NO];
    _syncingScroll = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)sv
{
    if (_syncingScroll || !_session) return;
    [self applyScrollPos:[self maxScrollPos] - sv.contentOffset.y];
    [self updateSelectionHandles];
    [self setNeedsDisplay];
}

/* Come to rest on a whole line, so the text is never left sitting between two lines. */
- (CGFloat)snappedOffset:(CGFloat)y
{
    y = roundf(y / _cellH) * _cellH;
    CGFloat maxPos = [self maxScrollPos];
    if (y > maxPos) y = maxPos;
    if (y < 0) y = 0;
    return y;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)sv withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target
{
    target->y = [self snappedOffset:target->y];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate
{
    if (decelerate) return;
    CGFloat off = sv.contentOffset.y;
    if (off < 0 || off > [self maxScrollPos]) return;             /* released past an end: the scroll view springs back itself */
    CGFloat y = [self snappedOffset:off];
    if (fabsf(y - off) > 0.5f) [sv setContentOffset:CGPointMake(0, y) animated:YES];
}

- (void)handlePinch:(UIPinchGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) {
        _pinchBase = [Settings shared].fontSize;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat n = roundf(_pinchBase * g.scale);
        if (n < 7) n = 7;
        if (n > 28) n = 28;
        if (n != [Settings shared].fontSize) [Settings shared].fontSize = n;   /* posts a notification -> reloadAppearance */
    }
}

#pragma mark - Selection

- (NSInteger)topAbsoluteLine { return (NSInteger)_session.scrollbackCount - _scrollOffset; }

- (void)lineAtPoint:(CGPoint)p line:(NSInteger *)line col:(int *)col
{
    int r = (int)floorf((p.y - kPad - _scrollFrac) / _cellH);
    int c = (int)floorf((p.x - kPad) / _cellW);
    if (r < 0) r = 0;
    if (r >= _session.rows) r = _session.rows - 1;
    if (c < 0) c = 0;
    if (c >= _session.cols) c = _session.cols - 1;
    *line = [self topAbsoluteLine] + r;
    *col = c;
}

/* Fills buf[0..cols) with the cells of an absolute line (scrollback first, then screen rows). */
- (void)loadLine:(NSInteger)absLine into:(VTermScreenCell *)buf
{
    int cols = _session.cols, c;
    NSInteger sb = (NSInteger)_session.scrollbackCount;
    if (absLine >= sb) {
        int row = (int)(absLine - sb);
        for (c = 0; c < cols; c++) {
            if (row >= _session.rows || ![_session getCell:&buf[c] row:row col:c]) blankCell(&buf[c]);
        }
    } else {
        int have = 0;
        const VTermScreenCell *src = (absLine >= 0) ? [_session scrollbackLine:(NSUInteger)absLine cols:&have] : NULL;
        for (c = 0; c < cols; c++) {
            if (src && c < have) buf[c] = src[c]; else blankCell(&buf[c]);
        }
    }
}

static BOOL isBlankCell(const VTermScreenCell *c) { return c->chars[0] == 0 || c->chars[0] == ' '; }

- (BOOL)selectWordAtLine:(NSInteger)line col:(int)col
{
    int cols = _session.cols;
    VTermScreenCell buf[cols];
    [self loadLine:line into:buf];
    if (isBlankCell(&buf[col])) return NO;
    int a = col, b = col;
    while (a > 0 && !isBlankCell(&buf[a - 1])) a--;
    while (b < cols - 1 && !isBlankCell(&buf[b + 1])) b++;
    _selStartLine = _selEndLine = line;
    _selStartCol = a;
    _selEndCol = b;
    _hasSelection = YES;
    return YES;
}

- (NSString *)selectedText
{
    if (!_hasSelection) return nil;
    int cols = _session.cols, c;
    VTermScreenCell buf[cols];
    NSMutableString *out = [NSMutableString string];
    NSInteger l;
    for (l = _selStartLine; l <= _selEndLine; l++) {
        [self loadLine:l into:buf];
        int c0 = (l == _selStartLine) ? _selStartCol : 0;
        int c1 = (l == _selEndLine) ? _selEndCol : cols - 1;
        if (c1 >= cols) c1 = cols - 1;
        NSMutableString *line = [NSMutableString string];
        for (c = c0; c <= c1; c++) {
            uint32_t cp = buf[c].chars[0];
            if (cp == (uint32_t)-1) continue;
            if (cp == 0) { [line appendString:@" "]; continue; }
            int i;
            for (i = 0; i < VTERM_MAX_CHARS_PER_CELL && buf[c].chars[i]; i++) {
                uint32_t u = buf[c].chars[i];
                NSString *ch = [[NSString alloc] initWithBytes:&u length:4 encoding:NSUTF32LittleEndianStringEncoding];
                if (ch) [line appendString:ch];
            }
        }
        while ([line length] > 0 && [line characterAtIndex:[line length] - 1] == ' ')   /* trim trailing blanks */
            [line deleteCharactersInRange:NSMakeRange([line length] - 1, 1)];
        [out appendString:line];
        if (l < _selEndLine) [out appendString:@"\n"];
    }
    return out;
}

- (void)clearSelection
{
    BOOL had = _hasSelection;
    _hasSelection = NO;
    _startHandle.hidden = YES;
    _endHandle.hidden = YES;
    if (had) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        [self setNeedsDisplay];
    }
}

- (SelectionHandle *)makeHandleStart:(BOOL)isStart
{
    SelectionHandle *h = [[SelectionHandle alloc] initWithStart:isStart lineHeight:_cellH];
    UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleHandlePan:)];
    [h addGestureRecognizer:p];
    [self addSubview:h];
    return h;
}

- (void)updateSelectionHandles
{
    if (!_hasSelection || !_session) { _startHandle.hidden = YES; _endHandle.hidden = YES; return; }
    if (!_startHandle) _startHandle = [self makeHandleStart:YES];
    if (!_endHandle)   _endHandle   = [self makeHandleStart:NO];

    NSInteger top = [self topAbsoluteLine];
    NSInteger rs = _selStartLine - top, re = _selEndLine - top;
    BOOL visS = (rs >= 0 && rs < _session.rows);
    BOOL visE = (re >= 0 && re < _session.rows);

    _startHandle.hidden = !visS;
    _endHandle.hidden = !visE;
    if (visS) _startHandle.frame = CGRectMake(kPad + _selStartCol * _cellW - 15, kPad + rs * _cellH + _scrollFrac - 9, 30, _cellH + 9);
    if (visE) _endHandle.frame   = CGRectMake(kPad + (_selEndCol + 1) * _cellW - 15, kPad + re * _cellH + _scrollFrac, 30, _cellH + 9);
}

- (void)handleHandlePan:(UIPanGestureRecognizer *)g
{
    SelectionHandle *h = (SelectionHandle *)g.view;
    NSInteger top = [self topAbsoluteLine];

    if (g.state == UIGestureRecognizerStateBegan) {
        _draggingStart = h.isStart;
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
        NSInteger line = _draggingStart ? _selStartLine : _selEndLine;
        int col = _draggingStart ? _selStartCol : _selEndCol;
        _dragOrigin = CGPointMake(kPad + (col + 0.5f) * _cellW, kPad + (line - top + 0.5f) * _cellH + _scrollFrac);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:self];
        NSInteger line;
        int col;
        [self lineAtPoint:CGPointMake(_dragOrigin.x + t.x, _dragOrigin.y + t.y) line:&line col:&col];
        if (_draggingStart) {                                       /* handles may not cross each other */
            if (line > _selEndLine || (line == _selEndLine && col > _selEndCol)) { line = _selEndLine; col = _selEndCol; }
            _selStartLine = line; _selStartCol = col;
        } else {
            if (line < _selStartLine || (line == _selStartLine && col < _selStartCol)) { line = _selStartLine; col = _selStartCol; }
            _selEndLine = line; _selEndCol = col;
        }
        [self updateSelectionHandles];
        [self setNeedsDisplay];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        [self showSelectionMenu];
    }
}

- (void)showSelectionMenu
{
    if (!_hasSelection) return;
    NSInteger rs = _selStartLine - [self topAbsoluteLine];
    if (rs < 0) rs = 0;
    if (rs >= _session.rows) rs = _session.rows - 1;
    CGRect r = CGRectMake(kPad + _selStartCol * _cellW, kPad + rs * _cellH + _scrollFrac, MAX(_cellW, 24.0f), _cellH);
    UIMenuController *m = [UIMenuController sharedMenuController];
    m.menuItems = nil;
    [m setTargetRect:r inView:self];
    [m setMenuVisible:YES animated:YES];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) {
        [self stopInertia];
        if (![self isFirstResponder]) [self becomeFirstResponder];
        NSInteger line;
        int col;
        [self lineAtPoint:[g locationInView:self] line:&line col:&col];
        _hasSelection = NO;
        if ([self selectWordAtLine:line col:col]) [self updateSelectionHandles];
        else { _startHandle.hidden = YES; _endHandle.hidden = YES; }
        [self setNeedsDisplay];
    } else if (g.state == UIGestureRecognizerStateEnded) {
        if (_hasSelection) {
            [self showSelectionMenu];
        } else {                                                    /* blank spot: Paste / Select All */
            UIMenuController *m = [UIMenuController sharedMenuController];
            m.menuItems = nil;
            CGPoint p = [g locationInView:self];
            [m setTargetRect:CGRectMake(p.x, p.y, 0, 0) inView:self];
            [m setMenuVisible:YES animated:YES];
        }
    }
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(copy:))      return _hasSelection;
    if (action == @selector(paste:))     return [[UIPasteboard generalPasteboard] string] != nil;
    if (action == @selector(selectAll:)) return _session != nil;
    return NO;
}

- (void)copy:(id)sender
{
    NSString *t = [self selectedText];
    if (t) [[UIPasteboard generalPasteboard] setString:t];
    [self clearSelection];
}

- (void)paste:(id)sender
{
    NSString *s = [[UIPasteboard generalPasteboard] string];
    if (s) [self typeText:s];
}

- (void)selectAll:(id)sender
{
    _selStartLine = 0;
    _selStartCol = 0;
    _selEndLine = (NSInteger)_session.scrollbackCount + _session.rows - 1;
    _selEndCol = _session.cols - 1;
    _hasSelection = YES;
    [self updateSelectionHandles];
    [self setNeedsDisplay];
    [self showSelectionMenu];
}

#pragma mark - Keyboard input (UIKeyInput)

- (BOOL)hasText { return YES; }                              /* always YES so Backspace is always delivered */

- (void)insertText:(NSString *)text { [self typeText:text]; }

- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UIKeyboardType)keyboardType { return UIKeyboardTypeASCIICapable; }

static int ctrlCode(unichar c)
{
    if (c >= 'a' && c <= 'z') return c - 'a' + 1;
    if (c >= 'A' && c <= 'Z') return c - 'A' + 1;
    switch (c) {
        case '@': case ' ': case '2': return 0;
        case '[': return 27;
        case '\\': return 28;
        case ']': return 29;
        case '^': return 30;
        case '_': return 31;
        case '?': return 127;
        default: return -1;
    }
}

- (void)sendRaw:(const void *)bytes length:(size_t)len
{
    if (_hasSelection) [self clearSelection];
    if (_scrollPos > 0) { [self stopInertia]; [self resetScroll]; [self setNeedsDisplay]; }   /* typing jumps back to the prompt */
    [_session sendBytes:bytes length:len];
}

- (void)typeText:(NSString *)text
{
    BOOL ctrl = _keyBar.ctrlActive, alt = _keyBar.altActive;

    if ((ctrl || alt) && [text length] == 1) {
        NSMutableData *out = [NSMutableData data];
        if (alt) { unsigned char esc = 0x1B; [out appendBytes:&esc length:1]; }
        int cc = ctrl ? ctrlCode([text characterAtIndex:0]) : -1;
        if (cc >= 0) { unsigned char b = (unsigned char)cc; [out appendBytes:&b length:1]; }
        else { [out appendData:[_session encodeString:text]]; }
        [self sendRaw:[out bytes] length:[out length]];
        [_keyBar clearModifiers];
        return;
    }

    NSString *t = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\r"];
    t = [t stringByReplacingOccurrencesOfString:@"\n" withString:@"\r"];
    NSData *d = [_session encodeString:t];
    [self sendRaw:[d bytes] length:[d length]];
}

#pragma mark Backspace with key repeat

- (void)sendDelete
{
    unsigned char del = 0x7F;
    [self sendRaw:&del length:1];
}

- (BOOL)keyboardKeyStillDown
{
    UIApplication *app = [UIApplication sharedApplication];
    return [app respondsToSelector:@selector(keyboardTouchActive)] && [(Term6Application *)app keyboardTouchActive];
}

/* The system keyboard reports one deleteBackward per press. If a finger is still on the keyboard
   0.45 s later, the key is being held: repeat like iOS does (and faster after a while). If the
   keyboard does send its own repeats, each one restarts the hold timer, so ours never kicks in. */
- (void)deleteBackward
{
    if (_deleteRepeating) return;
    [self sendDelete];
    [_deleteHoldTimer invalidate];
    _deleteHoldTimer = [NSTimer scheduledTimerWithTimeInterval:0.45 target:self selector:@selector(deleteHoldCheck:) userInfo:nil repeats:NO];
}

- (void)deleteHoldCheck:(NSTimer *)t
{
    _deleteHoldTimer = nil;
    if (![self keyboardKeyStillDown]) return;
    _deleteRepeating = YES;
    _deleteRepeatCount = 0;
    _deleteRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.09 target:self selector:@selector(deleteRepeatTick:) userInfo:nil repeats:YES];
}

- (void)deleteRepeatTick:(NSTimer *)t
{
    if (![self isFirstResponder] || ![self keyboardKeyStillDown] || _deleteRepeatCount > 800) { [self stopDeleteRepeat]; return; }
    [self sendDelete];
    _deleteRepeatCount++;
    if (_deleteRepeatCount == 14) {                              /* speed up while held */
        [_deleteRepeatTimer invalidate];
        _deleteRepeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(deleteRepeatTick:) userInfo:nil repeats:YES];
    }
}

- (void)stopDeleteRepeat
{
    [_deleteHoldTimer invalidate];
    [_deleteRepeatTimer invalidate];
    _deleteHoldTimer = nil;
    _deleteRepeatTimer = nil;
    _deleteRepeating = NO;
}

#pragma mark - KeyBarDelegate

- (void)keyBar:(KeyBarView *)bar didTapText:(NSString *)text { [self typeText:text]; }

- (void)keyBarDidTapEscape:(KeyBarView *)bar
{
    unsigned char esc = 0x1B;
    [self sendRaw:&esc length:1];
    [_keyBar clearModifiers];
}

- (void)keyBarDidTapTab:(KeyBarView *)bar
{
    unsigned char tab = '\t';
    [self sendRaw:&tab length:1];
    [_keyBar clearModifiers];
}

- (void)keyBarDidTapSettings:(KeyBarView *)bar
{
    if (self.onSettingsTap) self.onSettingsTap();
}

- (void)keyBarDidLongPressSettings:(KeyBarView *)bar
{
    if (self.onSettingsLongPress) self.onSettingsLongPress();
}

- (void)keyBar:(KeyBarView *)bar moveByDX:(NSInteger)dx dy:(NSInteger)dy
{
    if (_scrollPos > 0) { [self stopInertia]; [self resetScroll]; [self setNeedsDisplay]; }
    NSInteger i;
    for (i = 0; i < labs(dx); i++) [_session sendKey:(dx > 0 ? VTERM_KEY_RIGHT : VTERM_KEY_LEFT)];
    for (i = 0; i < labs(dy); i++) [_session sendKey:(dy > 0 ? VTERM_KEY_DOWN  : VTERM_KEY_UP)];
}

@end
