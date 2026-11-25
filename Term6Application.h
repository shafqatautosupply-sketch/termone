#import <UIKit/UIKit.h>

/* UIApplication subclass that watches touches landing on the system keyboard window.
 * The keyboard only tells us "delete pressed"; this lets us know the key is still held down,
 * so we can auto-repeat Backspace like iOS does. */
@interface Term6Application : UIApplication
@property (nonatomic, readonly) BOOL keyboardTouchActive;
@end
