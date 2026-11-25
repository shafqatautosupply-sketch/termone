#import "EncodingViewController.h"
#import "TermEncoding.h"
#import "Settings.h"

@implementation EncodingViewController

- (id)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = @"Text Encoding";
    return self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)[[TermEncoding all] count]; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    return @"How output from the shell is read and typed text is sent. Applies immediately to every tab. "
           @"New shells also get a matching LANG; already running shells keep the one they started with.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    TermEncoding *e = [[TermEncoding all] objectAtIndex:(NSUInteger)ip.row];
    cell.textLabel.text = e.name;
    cell.accessoryType = [e.name isEqualToString:[TermEncoding current].name]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    TermEncoding *e = [[TermEncoding all] objectAtIndex:(NSUInteger)ip.row];
    [Settings shared].encodingName = e.name;
    [tv deselectRowAtIndexPath:ip animated:YES];
    [tv reloadData];
}

@end
