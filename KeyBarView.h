#import <UIKit/UIKit.h>

@class KeyBarView;

@protocol KeyBarDelegate <NSObject>
- (void)keyBar:(KeyBarView *)bar didTapText:(NSString *)text;
- (void)keyBarDidTapEscape:(KeyBarView *)bar;
- (void)keyBarDidTapTab:(KeyBarView *)bar;
- (void)keyBarDidTapSettings:(KeyBarView *)bar;
/* Press and hold on the settings key: command / session panel. */
- (void)keyBarDidLongPressSettings:(KeyBarView *)bar;
/* Finger dragged across the bar: positive dx = right, positive dy = down (in cursor steps). */
- (void)keyBar:(KeyBarView *)bar moveByDX:(NSInteger)dx dy:(NSInteger)dy;
@end

/* Key bar built from a standard UIToolbar (black opaque style) with bordered UIBarButtonItems:
 * Esc, sticky Ctrl/Alt (lit blue via tintColor), Tab, a few symbols and the gear on the right.
 * Dragging a finger over the bar moves the terminal cursor; press and hold the gear for the panel. */
@interface KeyBarView : UIToolbar

@property (nonatomic, assign) id<KeyBarDelegate> delegate;
@property (nonatomic, readonly) BOOL ctrlActive;
@property (nonatomic, readonly) BOOL altActive;

- (void)clearModifiers;

@end
