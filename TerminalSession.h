#import <Foundation/Foundation.h>
#include "vterm.h"

@class TerminalSession;

@protocol TerminalSessionDelegate <NSObject>
/* Rows [location, location+length) changed (or everything, if length == rows). */
- (void)terminalSession:(TerminalSession *)session didUpdateRows:(NSRange)rows;
/* Cursor moved, cursor visibility or alt-screen state changed. */
- (void)terminalSessionDidChangeState:(TerminalSession *)session;
@end

/* One shell + one libvterm emulator. Talks to the shell either directly through
 * a pty (local mode) or through term6d (daemon mode, sessions survive the app). */
@interface TerminalSession : NSObject

@property (nonatomic, weak) id<TerminalSessionDelegate> delegate;

@property (nonatomic, readonly) int rows;
@property (nonatomic, readonly) int cols;
@property (nonatomic, readonly) int cursorRow;
@property (nonatomic, readonly) int cursorCol;
@property (nonatomic, readonly) BOOL cursorVisible;
@property (nonatomic, readonly) BOOL altScreen;
@property (nonatomic, readonly) BOOL usingDaemon;
@property (nonatomic, readonly) VTermScreen *screen;
@property (nonatomic, readonly) NSUInteger scrollbackCount;

/* Id of this session inside term6d (0 = none yet). Persisted by the owner so tabs survive app restarts. */
@property (nonatomic, assign) NSUInteger daemonId;
/* Called whenever daemonId changes. */
@property (nonatomic, copy) void (^onIdentityChange)(void);

- (id)initWithRows:(int)rows cols:(int)cols;

- (void)start;                    /* connect to / spawn the shell according to Settings */
- (void)restart;                  /* kill the current shell and start a fresh one */
- (void)closeSession;             /* kill the shell and disconnect for good (tab closed) */
- (void)reconnectIfNeeded;        /* daemon mode: re-attach after the app was suspended */
- (void)applyTheme;               /* push the current theme colours into the emulator */
- (void)resizeRows:(int)rows cols:(int)cols;

- (void)sendString:(NSString *)string;        /* same as sendText: */
- (void)sendText:(NSString *)text;            /* typed/pasted text, encoded with the chosen text encoding */
- (NSData *)encodeString:(NSString *)string;  /* string -> bytes in the chosen text encoding */
- (void)sendBytes:(const void *)bytes length:(size_t)length;
- (void)sendKey:(VTermKey)key;                /* arrows etc., honours application-cursor mode */

- (BOOL)getCell:(VTermScreenCell *)cell row:(int)row col:(int)col;
/* Scrollback line 0 is the oldest. The pointer stays valid until the next input is processed. */
- (const VTermScreenCell *)scrollbackLine:(NSUInteger)index cols:(int *)cols;
- (NSString *)screenText;

+ (BOOL)daemonReachable;

@end
