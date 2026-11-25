#import "CommandPanelView.h"
#import "KeyButton.h"

static const CGFloat kHeaderH   = 46.0f;
static const NSInteger kMaxTabs = 8;

@interface CommandPanelView () {
    UIView *_header;
    CAGradientLayer *_headerGloss;
    UIScrollView *_tabScroll;
    NSMutableArray *_tabButtons;
    KeyButton *_addButton, *_closeButton;
    UITableView *_table;
    UILabel *_empty;
    NSArray *_commands;
    NSInteger _count, _selected;
}
@end

@implementation CommandPanelView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.10f alpha:1];
        self.layer.cornerRadius = 10.0f;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0f;
        self.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.9f].CGColor;

        _header = [[UIView alloc] initWithFrame:CGRectZero];
        _headerGloss = [CAGradientLayer layer];
        KBSetGloss(_headerGloss, KBColor(92, 95, 100), KBColor(58, 60, 65), KBColor(34, 36, 40), KBColor(14, 15, 17));
        [_header.layer addSublayer:_headerGloss];
        [self addSubview:_header];

        _tabScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _tabScroll.showsHorizontalScrollIndicator = NO;
        [_header addSubview:_tabScroll];

        _tabButtons = [NSMutableArray array];

        _addButton = [[KeyButton alloc] initWithFrame:CGRectMake(0, 0, 36, 30)];
        [_addButton setTitle:@"+" forState:UIControlStateNormal];
        _addButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [_addButton addTarget:self action:@selector(addTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabScroll addSubview:_addButton];

        _closeButton = [[KeyButton alloc] initWithFrame:CGRectMake(0, 0, 34, 30)];
        [_closeButton setTitle:@"\u00D7" forState:UIControlStateNormal];
        _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [_closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:_closeButton];

        _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        _table.dataSource = self;
        _table.delegate = self;
        _table.backgroundColor = [UIColor colorWithWhite:0.11f alpha:1];
        _table.separatorColor = [UIColor colorWithWhite:0.26f alpha:1];
        _table.rowHeight = 46;
        [self addSubview:_table];

        _empty = [[UILabel alloc] initWithFrame:CGRectZero];
        _empty.numberOfLines = 0;
        _empty.textAlignment = UITextAlignmentCenter;
        _empty.backgroundColor = [UIColor clearColor];
        _empty.textColor = [UIColor colorWithWhite:0.6f alpha:1];
        _empty.font = [UIFont systemFontOfSize:14];
        _empty.text = @"No saved commands yet.\nAdd some in Settings.";
        [self addSubview:_empty];
    }
    return self;
}

- (void)setSessionCount:(NSInteger)count selected:(NSInteger)selected commands:(NSArray *)commands
{
    _count = count;
    _selected = selected;
    _commands = commands;

    for (UIView *v in _tabButtons) [v removeFromSuperview];
    [_tabButtons removeAllObjects];

    NSInteger i;
    for (i = 0; i < count; i++) {
        KeyButton *b = [[KeyButton alloc] initWithFrame:CGRectMake(0, 0, 36, 30)];
        [b setTitle:[NSString stringWithFormat:@"%d", (int)(i + 1)] forState:UIControlStateNormal];
        b.tag = i;
        b.selected = (i == selected);
        [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_tabScroll addSubview:b];
        [_tabButtons addObject:b];
    }
    _addButton.hidden = (count >= kMaxTabs);
    _closeButton.hidden = (count <= 1);

    [_table reloadData];
    _empty.hidden = ([commands count] > 0);
    _table.hidden = ([commands count] == 0);
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;

    _header.frame = CGRectMake(0, 0, b.size.width, kHeaderH);
    _headerGloss.frame = _header.bounds;

    CGFloat closeW = _closeButton.hidden ? 0 : 42;
    _tabScroll.frame = CGRectMake(0, 0, b.size.width - closeW, kHeaderH);
    _closeButton.frame = CGRectMake(b.size.width - 40, 8, 34, 30);

    CGFloat x = 8;
    for (UIView *t in _tabButtons) {
        t.frame = CGRectMake(x, 8, 36, 30);
        x += 42;
    }
    _addButton.frame = CGRectMake(x, 8, 36, 30);
    if (!_addButton.hidden) x += 42;
    _tabScroll.contentSize = CGSizeMake(x + 4, kHeaderH);

    _table.frame = CGRectMake(0, kHeaderH, b.size.width, b.size.height - kHeaderH);
    _empty.frame = CGRectMake(12, kHeaderH + 20, b.size.width - 24, 60);
}

#pragma mark Actions

- (void)tabTapped:(KeyButton *)b { [self.delegate commandPanel:self didSelectSessionAtIndex:b.tag]; }
- (void)addTapped:(id)sender     { [self.delegate commandPanelDidAddSession:self]; }
- (void)closeTapped:(id)sender   { [self.delegate commandPanelDidCloseSession:self]; }

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return (NSInteger)[_commands count]; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    static NSString *ident = @"cmd";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];
        cell.backgroundColor = [UIColor colorWithWhite:0.16f alpha:1];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62f alpha:1];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
        UIFont *f = [UIFont fontWithName:@"Menlo-Regular" size:11];
        cell.detailTextLabel.font = f ? f : [UIFont systemFontOfSize:11];
        UIView *sel = [[UIView alloc] initWithFrame:CGRectZero];
        sel.backgroundColor = [UIColor colorWithRed:0.20f green:0.42f blue:0.85f alpha:1];
        cell.selectedBackgroundView = sel;
    }
    NSDictionary *c = [_commands objectAtIndex:(NSUInteger)ip.row];
    cell.textLabel.text = [c objectForKey:@"title"];
    cell.detailTextLabel.text = [c objectForKey:@"command"];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    NSString *cmd = [[_commands objectAtIndex:(NSUInteger)ip.row] objectForKey:@"command"];
    [tv deselectRowAtIndexPath:ip animated:NO];
    [self.delegate commandPanel:self didSelectCommand:cmd];
}

@end
