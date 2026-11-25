#import "CommandEditViewController.h"

@interface CommandEditViewController () {
    UITextField *_titleField, *_commandField;
    BOOL _askTitle;
    void (^_onSave)(NSString *, NSString *);
}
@end

@implementation CommandEditViewController

- (id)initWithTitle:(NSString *)title command:(NSString *)command askTitle:(BOOL)askTitle
             onSave:(void (^)(NSString *, NSString *))onSave
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _askTitle = askTitle;
        _onSave = [onSave copy];

        _titleField = [self fieldWithPlaceholder:@"e.g. List files" text:title mono:NO];
        _titleField.returnKeyType = UIReturnKeyNext;
        _commandField = [self fieldWithPlaceholder:@"e.g. ls -la" text:command mono:YES];
        _commandField.returnKeyType = UIReturnKeyDone;
    }
    return self;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)ph text:(NSString *)text mono:(BOOL)mono
{
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 24)];
    f.placeholder = ph;
    f.text = text;
    f.delegate = self;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIFont *mf = mono ? [UIFont fontWithName:@"Menlo-Regular" size:15] : nil;
    f.font = mf ? mf : [UIFont systemFontOfSize:16];
    f.textColor = [UIColor colorWithRed:0.22f green:0.33f blue:0.53f alpha:1];     /* iOS 6 settings value blue */
    return f;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save:)];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if ([_commandField.text length] == 0 && !_askTitle) [_commandField becomeFirstResponder];
    else if ([_titleField.text length] == 0 && _askTitle) [_titleField becomeFirstResponder];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _askTitle ? 2 : 1; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s
{
    return _askTitle ? @"The title is what you see in the list. The command is what gets typed into the terminal."
                     : @"Typed into every new session as soon as its shell starts.";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL isTitleRow = (_askTitle && ip.row == 0);
    cell.textLabel.text = isTitleRow ? @"Title" : @"Command";
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15];

    UITextField *f = isTitleRow ? _titleField : _commandField;
    f.frame = CGRectMake(100, 11, tv.bounds.size.width - 100 - 40, 24);          /* right of the caption */
    [f removeFromSuperview];
    [cell.contentView addSubview:f];
    return cell;
}

#pragma mark Fields

- (BOOL)textFieldShouldReturn:(UITextField *)tf
{
    if (tf == _titleField) { [_commandField becomeFirstResponder]; return NO; }
    [self save:nil];
    return NO;
}

- (void)save:(id)sender
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    NSString *cmd = [_commandField.text stringByTrimmingCharactersInSet:ws];
    NSString *title = [_titleField.text stringByTrimmingCharactersInSet:ws];
    if ([cmd length] == 0) {
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Enter a command" message:nil delegate:nil
                                          cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [a show];
        return;
    }
    if ([title length] == 0) title = cmd;
    [self.view endEditing:YES];
    if (_onSave) _onSave(title, cmd);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
