#import <UIKit/UIKit.h>

@class CommandPanelView;

@protocol CommandPanelDelegate <NSObject>
- (void)commandPanel:(CommandPanelView *)panel didSelectCommand:(NSString *)command;
- (void)commandPanel:(CommandPanelView *)panel didSelectSessionAtIndex:(NSInteger)index;
- (void)commandPanelDidAddSession:(CommandPanelView *)panel;
- (void)commandPanelDidCloseSession:(CommandPanelView *)panel;
@end

/* Pop-up box: session tabs (+ to add, x to close) on top, saved commands below. */
@interface CommandPanelView : UIView <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) id<CommandPanelDelegate> delegate;

- (void)setSessionCount:(NSInteger)count selected:(NSInteger)selected commands:(NSArray *)commands;

@end
