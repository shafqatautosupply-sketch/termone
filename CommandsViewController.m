#import "CommandsViewController.h"
#import "CommandEditViewController.h"
#import "Settings.h"

@interface CommandsViewController () {
    NSMutableArray *_cmds;      /* saved commands: NSDictionary {title, command}; startup commands: NSString */
    BOOL _startup;
}
@end

@implementation CommandsViewController

- (id)init { return [self initWithStartup:NO]; }

- (id)initWithStartup:(BOOL)startup
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _startup = startup;
        self.title = startup ? @"Startup Commands" : @"Saved Commands";
        _cmds = [(startup ? [[Settings shared] startupCommands] : [[Settings shared] commands]) mutableCopy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addCommand:)];

    /* Always in edit mode: the grips on the right are always there to drag rows up and down. */
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

- (void)save
{
    if (_startup) [Settings shared].startupCommands = [_cmds copy];
    else          [Settings shared].commands = [_cmds copy];
}

#pragma mark Add / edit

- (void)addCommand:(id)sender { [self editItemAtIndex:-1]; }

- (void)editItemAtIndex:(NSInteger)i
{
    NSString *title = nil, *cmd = nil;
    if (i >= 0) {
        id item = [_cmds objectAtIndex:(NSUInteger)i];
        if (_startup) cmd = item;
        else { title = [item objectForKey:@"title"]; cmd = [item objectForKey:@"command"]; }
    }
    __weak CommandsViewController *ws = self;
    CommandEditViewController *vc = [[CommandEditViewController alloc]
        initWithTitle:title command:cmd askTitle:!_startup
               onSave:^(NSString *t, NSString *c) { [ws storeTitle:t command:c atIndex:i]; }];
    vc.title = (i >= 0) ? @"Edit Command" : @"New Command";
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)storeTitle:(NSString *)title command:(NSString *)cmd atIndex:(NSInteger)i
{
    id item = _startup ? (id)cmd : (id)[NSDictionary dictionaryWithObjectsAndKeys:title, @"title", cmd, @"command", nil];
    if (i >= 0 && i < (NSInteger)[_cmds count]) [_cmds replaceObjectAtIndex:(NSUInteger)i withObject:item];
    else [_cmds addObject:item];
    [self save];
    [self.tableView reloadData];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)[_cmds count]; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    if (_startup)
        return [_cmds count] ? @"Typed into every new session, top to bottom, as soon as its shell starts. Drag the grips to reorder; tap to edit."
                             : @"No startup commands yet. Tap + to add one. They run in every new session, top to bottom.";
    return [_cmds count] ? @"Press and hold the gear key on the keyboard bar to use these. Drag the grips to reorder; tap to edit."
                         : @"No commands yet. Tap + to add one. Press and hold the gear key on the keyboard bar to use them.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    id item = [_cmds objectAtIndex:(NSUInteger)ip.row];
    UIFont *mono = [UIFont fontWithName:@"Menlo-Regular" size:13];
    UITableViewCell *cell;
    if (_startup) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.font = mono ? mono : [UIFont systemFontOfSize:14];
        cell.textLabel.text = item;
    } else {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        cell.textLabel.text = [item objectForKey:@"title"];
        cell.detailTextLabel.font = mono ? mono : [UIFont systemFontOfSize:13];
        cell.detailTextLabel.text = [item objectForKey:@"command"];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self editItemAtIndex:ip.row];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip
{
    if (style != UITableViewCellEditingStyleDelete) return;
    [_cmds removeObjectAtIndex:(NSUInteger)ip.row];
    [self save];
    [tv deleteRowsAtIndexPaths:[NSArray arrayWithObject:ip] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to
{
    id item = [_cmds objectAtIndex:(NSUInteger)from.row];
    [_cmds removeObjectAtIndex:(NSUInteger)from.row];
    [_cmds insertObject:item atIndex:(NSUInteger)to.row];
    [self save];
}

@end
