#import <UIKit/UIKit.h>
#import "TerminalSession.h"

@interface SettingsViewController : UITableViewController <UIAlertViewDelegate>
/* Called instead of a modal dismiss: the owner slides Settings away. */
@property (nonatomic, copy) void (^onDone)(void);
- (id)initWithSession:(TerminalSession *)session;
@end
