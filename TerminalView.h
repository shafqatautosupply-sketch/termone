#import <UIKit/UIKit.h>
#import "TerminalSession.h"
#import "KeyBarView.h"

/* Draws the terminal grid with Core Graphics, takes keyboard input (UIKeyInput) and handles:
 *  tap            show / hide the on-screen keyboard (the key bar stays)
 *  drag           scrollback through a UIScrollView: native momentum, snapping and scroll indicator
 *                 (arrow keys inside vim / less)
 *  pinch          font size
 *  long press     select a word (iOS-style handles + Copy / Paste menu)
 */
@interface TerminalView : UIView <UIKeyInput, TerminalSessionDelegate, KeyBarDelegate, UIGestureRecognizerDelegate, UIScrollViewDelegate>

@property (nonatomic, strong) TerminalSession *session;
@property (nonatomic, strong) KeyBarView *keyBar;

/* Grid that fits into the current bounds. */
@property (nonatomic, readonly) int visibleRows;
@property (nonatomic, readonly) int visibleCols;

/* YES = system keyboard collapsed, key bar still visible. */
@property (nonatomic, assign) BOOL keyboardHidden;

/* Gear key on the key bar: tap / press and hold. */
@property (nonatomic, copy) void (^onSettingsTap)(void);
@property (nonatomic, copy) void (^onSettingsLongPress)(void);
/* Called whenever the grid size is re-evaluated, so other tabs can be resized too. */
@property (nonatomic, copy) void (^onGridChange)(int rows, int cols);

- (void)reloadAppearance;           /* call after theme / font size changed */
- (void)typeText:(NSString *)text;  /* as if typed (applies sticky Ctrl/Alt) */
- (void)clearSelection;

@end
