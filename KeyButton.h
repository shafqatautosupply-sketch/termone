#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

/* Shared iOS 6 "black toolbar" styling helpers. */
id   KBColor(CGFloat r, CGFloat g, CGFloat b);                                   /* 0...255 -> CGColor as id */
void KBSetGloss(CAGradientLayer *g, id t0, id t1, id b0, id b1);                 /* hard split in the middle */

/* Dark bordered bar-button with a blue lit state (selected). */
@interface KeyButton : UIButton
@end
