#import "SettingsViewController.h"
#import "Settings.h"
#import "TermTheme.h"
#import "CommandsViewController.h"
#import "EncodingViewController.h"
#import "TermEncoding.h"

enum { kSecPersist = 0, kSecShell, kSecCommands, kSecFont, kSecTheme, kSecCount };
enum { kTagShellAlert = 1, kTagNewSessionAlert = 2 };

@interface SettingsViewController () {
    TerminalSession *_session;
    UILabel *_fontLabel;
    NSString *_daemonStatus;      /* checked once the slide-in has finished, not while building the table */
}
@end

@implementation SettingsViewController

- (id)initWithSession:(TerminalSession *)session
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _session = session;
        self.title = @"Settings";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    NSString *now = [TerminalSession daemonReachable] ? @"Running" : @"Not running";
    if (![now isEqualToString:_daemonStatus]) {
        _daemonStatus = now;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSecPersist] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];             /* refreshes the daemon status row */
}

- (void)finish
{
    if (self.onDone) self.onDone();
    else [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)done:(id)sender { [self finish]; }

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return kSecCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case kSecPersist: return 3;
        case kSecShell:   return 3;
        case kSecCommands: return 3;
        case kSecFont:    return 1;
        case kSecTheme:   return (NSInteger)[[TermTheme allThemes] count];
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kSecPersist: return @"Background Sessions";
        case kSecShell:   return @"Shell";
        case kSecCommands: return @"Commands";
        case kSecFont:    return @"Font Size";
        case kSecTheme:   return @"Theme";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section
{
    if (section == kSecCommands)
        return @"Saved Commands: press and hold the gear key on the keyboard bar to open them. "
               @"Startup Commands run by themselves in every new session.";
    if (section == kSecPersist)
        return @"Persistent Sessions keeps your shells in term6d, a root background daemon, so they keep running "
               @"when Term6 is suspended or closed. Run Shell as Root works with or without it (without it, through "
               @"the setuid helper term6root). Changes apply to the next new session.";
    return nil;
}

- (UISwitch *)switchWithTag:(NSInteger)tag on:(BOOL)on enabled:(BOOL)enabled
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.tag = tag;
    sw.on = on;
    sw.enabled = enabled;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    Settings *st = [Settings shared];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    switch (ip.section) {
    case kSecPersist:
        if (ip.row == 0) {
            cell.textLabel.text = @"Persistent Sessions";
            cell.accessoryView = [self switchWithTag:1 on:st.useDaemon enabled:YES];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (ip.row == 1) {
            cell.textLabel.text = @"Run Shell as Root";
            cell.accessoryView = [self switchWithTag:2 on:st.runAsRoot enabled:YES];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Daemon";
            cell.detailTextLabel.text = _daemonStatus ? _daemonStatus : @"Checking…";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        break;
    case kSecShell:
        if (ip.row == 0) {
            cell.textLabel.text = @"Shell";
            cell.detailTextLabel.text = st.shellPath;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 1) {
            cell.textLabel.text = @"Text Encoding";
            cell.detailTextLabel.text = [TermEncoding current].name;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"New Session";
            cell.textLabel.textAlignment = UITextAlignmentCenter;
            cell.textLabel.textColor = [UIColor colorWithRed:0.75f green:0.1f blue:0.1f alpha:1];
        }
        break;
    case kSecCommands:
        if (ip.row == 0) {
            cell.textLabel.text = @"Saved Commands";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)[st.commands count]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (ip.row == 1) {
            cell.textLabel.text = @"Startup Commands";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)[st.startupCommands count]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"Press Return After Inserting";
            cell.accessoryView = [self switchWithTag:3 on:st.runCommandOnTap enabled:YES];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        break;
    case kSecFont: {
        cell.textLabel.text = [NSString stringWithFormat:@"%d pt", (int)st.fontSize];
        _fontLabel = cell.textLabel;
        UIStepper *stp = [[UIStepper alloc] initWithFrame:CGRectZero];
        stp.minimumValue = 7;
        stp.maximumValue = 28;
        stp.stepValue = 1;
        stp.value = st.fontSize;
        [stp addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stp;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        break;
    }
    case kSecTheme: {
        TermTheme *t = [[TermTheme allThemes] objectAtIndex:ip.row];
        cell.textLabel.text = t.name;
        cell.accessoryType = (ip.row == st.themeIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        break;
    }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == kSecShell && ip.row == 0) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Shell"
                                                    message:@"Path of the shell to start (default /bin/bash)"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Save", nil];
        a.tag = kTagShellAlert;
        a.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *f = [a textFieldAtIndex:0];
        f.text = [Settings shared].shellPath;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        [a show];
    } else if (ip.section == kSecShell && ip.row == 1) {
        [self.navigationController pushViewController:[[EncodingViewController alloc] init] animated:YES];
    } else if (ip.section == kSecShell && ip.row == 2) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"New Session"
                                                    message:@"The running shell and everything in it will be closed."
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"New Session", nil];
        a.tag = kTagNewSessionAlert;
        [a show];
    } else if (ip.section == kSecCommands && ip.row == 0) {
        [self.navigationController pushViewController:[[CommandsViewController alloc] initWithStartup:NO] animated:YES];
    } else if (ip.section == kSecCommands && ip.row == 1) {
        [self.navigationController pushViewController:[[CommandsViewController alloc] initWithStartup:YES] animated:YES];
    } else if (ip.section == kSecTheme) {
        [Settings shared].themeIndex = ip.row;
        [tv reloadSections:[NSIndexSet indexSetWithIndex:kSecTheme] withRowAnimation:UITableViewRowAnimationNone];
    }
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sw
{
    if (sw.tag == 1) {
        [Settings shared].useDaemon = sw.on;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSecPersist] withRowAnimation:UITableViewRowAnimationNone];
    } else if (sw.tag == 3) {
        [Settings shared].runCommandOnTap = sw.on;
    } else {
        [Settings shared].runAsRoot = sw.on;
    }
}

- (void)stepperChanged:(UIStepper *)stp
{
    [Settings shared].fontSize = (CGFloat)stp.value;
    _fontLabel.text = [NSString stringWithFormat:@"%d pt", (int)stp.value];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)idx
{
    if (idx == alert.cancelButtonIndex) return;
    if (alert.tag == kTagShellAlert) {
        NSString *s = [[[alert textFieldAtIndex:0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [Settings shared].shellPath = [s length] ? s : @"/bin/bash";
        [self.tableView reloadData];
    } else if (alert.tag == kTagNewSessionAlert) {
        [_session restart];
        [self finish];
    }
}

@end
