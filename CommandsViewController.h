#import <UIKit/UIKit.h>

/* Add / edit / delete / reorder the saved commands shown in the long-press panel. */
@interface CommandsViewController : UITableViewController
/* startup = YES: commands that run when a new session starts; NO: the long-press panel list. */
- (id)initWithStartup:(BOOL)startup;
@end
