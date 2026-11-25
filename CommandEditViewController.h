#import <UIKit/UIKit.h>

/* Edit one command: an optional Title and the Command itself. */
@interface CommandEditViewController : UITableViewController <UITextFieldDelegate>

/* askTitle = NO: only the command field (startup commands have no title). */
- (id)initWithTitle:(NSString *)title
            command:(NSString *)command
           askTitle:(BOOL)askTitle
             onSave:(void (^)(NSString *title, NSString *command))onSave;

@end
