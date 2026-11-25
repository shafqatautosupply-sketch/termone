#import <UIKit/UIKit.h>
#import "TerminalSession.h"

@interface TerminalViewController : UIViewController
@property (nonatomic, readonly) TerminalSession *session;   /* the tab that is showing */
- (void)reconnectAll;                                       /* after the app comes back to the foreground */
@end
