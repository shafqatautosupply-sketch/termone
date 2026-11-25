#import "TerminalViewController.h"
#import "TerminalView.h"
#import "KeyBarView.h"
#import "CommandPanelView.h"
#import "SettingsViewController.h"
#import "Settings.h"
#import "TermTheme.h"
#import <QuartzCore/QuartzCore.h>

static const NSInteger kMaxSessions = 8;
static const CGFloat kBarH = 44.0f;
/* Settings slide: plain ease-in-out. (The keyboard's own curve decelerates for a long time at the end,
   which made the slide feel heavy.) */
static const NSTimeInterval kSlideDuration = 0.30;

@interface TerminalViewController () <CommandPanelDelegate> {
    TerminalView *_terminal;
    KeyBarView   *_keyBar;
    NSMutableArray *_sessions;
    NSInteger     _current;
    CGFloat       _kbInset;
    BOOL          _started;

    UINavigationController *_settingsNav;     /* Settings, slid in from the right as a child view */
    BOOL _settingsBusy;                       /* opening or closing: ignore further taps */
    CommandPanelView *_panel;
    UIView       *_shield;
    BOOL          _restoreKeyboard;
}
@end

@implementation TerminalViewController

- (TerminalSession *)session
{
    if (_current < 0 || _current >= (NSInteger)[_sessions count]) return nil;
    return [_sessions objectAtIndex:(NSUInteger)_current];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [[TermTheme current] bgColor];
    self.view.clipsToBounds = YES;
    _sessions = [NSMutableArray array];

    _terminal = [[TerminalView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_terminal];

    _keyBar = [[KeyBarView alloc] initWithFrame:CGRectMake(0, 0, 320, kBarH)];
    _terminal.keyBar = _keyBar;
    [self.view addSubview:_keyBar];                      /* docked above the keyboard (or at the bottom when folded) */

    __weak TerminalViewController *ws = self;
    _terminal.onSettingsTap = ^{ [ws showSettings]; };
    _terminal.onSettingsLongPress = ^{ [ws showCommandPanel]; };
    _terminal.onGridChange = ^(int rows, int cols) {
        TerminalViewController *s = ws;
        if (!s) return;
        for (TerminalSession *t in s->_sessions) [t resizeRows:rows cols:cols];   /* keep background tabs in step */
    };

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged:) name:SettingsDidChangeNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self layoutTerminal];

    if (!_started) {                      /* first layout: now we know the grid size */
        _started = YES;
        [self restoreSessions];
        [_terminal becomeFirstResponder];
    }
}

- (void)layoutTerminal
{
    CGRect b = self.view.bounds;
    CGFloat barY = b.size.height - _kbInset - kBarH;
    _keyBar.frame = CGRectMake(0, barY, b.size.width, kBarH);
    _terminal.frame = CGRectMake(0, 0, b.size.width, barY);
    if (_panel) [self layoutPanel];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    /* Coming back from Settings: start the keyboard now, so it slides up while the flip is still running. */
    if (_started && !_terminal.keyboardHidden) [_terminal becomeFirstResponder];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_terminal.keyboardHidden && ![_terminal isFirstResponder]) [_terminal becomeFirstResponder];
}

#pragma mark - Sessions (tabs)

- (TerminalSession *)newSessionWithDaemonId:(NSUInteger)did
{
    TerminalSession *s = [[TerminalSession alloc] initWithRows:_terminal.visibleRows cols:_terminal.visibleCols];
    s.daemonId = did;
    __weak TerminalViewController *ws = self;
    s.onIdentityChange = ^{ [ws persistSessions]; };
    [_sessions addObject:s];
    [s start];
    return s;
}

- (void)restoreSessions
{
    NSArray *ids = [Settings shared].useDaemon ? [Settings shared].sessionIds : nil;
    if ([ids count] == 0) {
        [self newSessionWithDaemonId:0];
    } else {
        for (NSNumber *n in ids) {
            if ([_sessions count] >= (NSUInteger)kMaxSessions) break;
            [self newSessionWithDaemonId:[n unsignedIntegerValue]];
        }
    }
    [self selectSessionAtIndex:0];
}

- (void)persistSessions
{
    NSMutableArray *ids = [NSMutableArray array];
    for (TerminalSession *s in _sessions)
        if (s.daemonId) [ids addObject:[NSNumber numberWithUnsignedInteger:s.daemonId]];
    [Settings shared].sessionIds = ids;
}

- (void)selectSessionAtIndex:(NSInteger)i
{
    if (i < 0 || i >= (NSInteger)[_sessions count]) return;
    _current = i;
    _terminal.session = [_sessions objectAtIndex:(NSUInteger)i];
    [self refreshPanel];
}

- (void)addSession
{
    if ([_sessions count] >= (NSUInteger)kMaxSessions) return;
    [self newSessionWithDaemonId:0];
    [self selectSessionAtIndex:(NSInteger)[_sessions count] - 1];
}

- (void)closeCurrentSession
{
    if ([_sessions count] <= 1) return;
    TerminalSession *s = self.session;
    [s closeSession];
    [_sessions removeObject:s];
    if (_current >= (NSInteger)[_sessions count]) _current = (NSInteger)[_sessions count] - 1;
    [self persistSessions];
    [self selectSessionAtIndex:_current];
}

- (void)reconnectAll
{
    for (TerminalSession *s in _sessions) [s reconnectIfNeeded];
}

#pragma mark - Notifications

- (void)keyboardChanged:(NSNotification *)n
{
    if (_settingsNav) return;     /* keyboards of Settings' own text prompts must not resize the terminal behind it */
    NSDictionary *info = [n userInfo];
    CGRect end = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect r = [self.view.window convertRect:end fromWindow:nil];
    r = [self.view convertRect:r fromView:nil];
    CGFloat inset = CGRectGetMaxY(self.view.bounds) - r.origin.y;
    if ([[n name] isEqualToString:UIKeyboardWillHideNotification] || inset < 3.0f) inset = 0;   /* 1pt "no keyboard" view */
    NSTimeInterval dur = [[info objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    int curve = [[info objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    [self applyKeyboardInset:inset duration:dur curve:curve];
}

/* Moves the key bar with the keyboard's own duration and curve; the text area snaps in one step. */
- (void)applyKeyboardInset:(CGFloat)inset duration:(NSTimeInterval)dur curve:(int)curve
{
    if (fabsf(inset - _kbInset) < 0.5f) return;               /* several notifications can describe the same state */
    _kbInset = inset;

    CGRect b = self.view.bounds;
    CGFloat barY = b.size.height - inset - kBarH;

    [UIView animateWithDuration:dur
                          delay:0
                        options:(UIViewAnimationOptionBeginFromCurrentState | (curve << 16))
                     animations:^{ _keyBar.frame = CGRectMake(0, barY, b.size.width, kBarH); }
                     completion:nil];

    /* Animating the text area would stretch the glyphs and reflow the grid on every frame. */
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _terminal.frame = CGRectMake(0, 0, b.size.width, barY);
    [_terminal layoutIfNeeded];
    [CATransaction commit];
    if (_panel) [self layoutPanel];
}

- (void)settingsChanged:(NSNotification *)n
{
    self.view.backgroundColor = [[TermTheme current] bgColor];
    for (TerminalSession *s in _sessions) [s applyTheme];
    [_terminal reloadAppearance];
}

#pragma mark - Settings

/* Opening:  keyboard slides away (native speed)  ->  Settings slides in from the right.
   Closing:  Settings slides back out             ->  keyboard slides up (native speed).     */
- (void)showSettings
{
    if (_settingsNav || _settingsBusy) return;
    _settingsBusy = YES;
    _restoreKeyboard = NO;                                 /* the keyboard comes back by itself once Settings is gone */
    [self dismissCommandPanel];

    SettingsViewController *vc = [[SettingsViewController alloc] initWithSession:self.session];
    __weak TerminalViewController *ws = self;
    vc.onDone = ^{ [ws hideSettings]; };
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.barStyle = UIBarStyleBlackOpaque;

    BOOL keyboardUp = (_kbInset > 0);                      /* the key bar rides with the keyboard through keyboardChanged: */
    __block BOOL slid = NO;
    __block id observer = nil;
    void (^slideIn)(void) = ^{
        if (slid) return;
        slid = YES;
        if (observer) { [[NSNotificationCenter defaultCenter] removeObserver:observer]; observer = nil; }
        [ws slideInSettings:nav];
    };

    [_terminal resignFirstResponder];                      /* keyboard slides away with its own animation */
    if (!keyboardUp) { slideIn(); return; }

    observer = [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardDidHideNotification
                                                                 object:nil
                                                                  queue:[NSOperationQueue mainQueue]
                                                             usingBlock:^(NSNotification *n) { slideIn(); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),    /* safety net if no "did hide" arrives */
                   dispatch_get_main_queue(), slideIn);
}

- (void)slideInSettings:(UINavigationController *)nav
{
    _settingsNav = nav;                                    /* from here on, Settings' own keyboards leave the terminal alone */
    CGRect b = self.view.bounds;
    [self addChildViewController:nav];
    nav.view.frame = CGRectMake(b.size.width, 0, b.size.width, b.size.height);
    nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:nav.view];
    [nav didMoveToParentViewController:self];

    [UIView animateWithDuration:kSlideDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ nav.view.frame = self.view.bounds; }
                     completion:^(BOOL finished) { _settingsBusy = NO; }];
}

- (void)hideSettings
{
    UINavigationController *nav = _settingsNav;
    if (!nav || _settingsBusy) return;
    _settingsBusy = YES;
    [self.view endEditing:YES];

    CGRect b = self.view.bounds;
    [UIView animateWithDuration:kSlideDuration delay:0 options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{ nav.view.frame = CGRectMake(b.size.width, 0, b.size.width, b.size.height); }
                     completion:^(BOOL finished) {
                         [nav willMoveToParentViewController:nil];
                         [nav.view removeFromSuperview];
                         [nav removeFromParentViewController];
                         _settingsNav = nil;
                         _settingsBusy = NO;
                         /* Only now does the keyboard come up, at its normal speed, with the key bar riding along. */
                         if (!_terminal.keyboardHidden) [_terminal becomeFirstResponder];
                     }];
}

#pragma mark - Command / session panel (press and hold the gear key)

- (void)showCommandPanel
{
    if (_panel) { [self dismissCommandPanel]; return; }
    [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    [_terminal clearSelection];

    _restoreKeyboard = !_terminal.keyboardHidden;
    _terminal.keyboardHidden = YES;                       /* make room: the key bar stays, the keyboard folds away */

    _shield = [[UIView alloc] initWithFrame:self.view.bounds];
    _shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissCommandPanel)]];
    [self.view addSubview:_shield];

    _panel = [[CommandPanelView alloc] initWithFrame:CGRectMake(0, 0, 280, 280)];
    _panel.delegate = self;
    [self.view addSubview:_panel];
    [self layoutPanel];
    [self refreshPanel];

    _panel.alpha = 0;
    _panel.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
    [UIView animateWithDuration:0.15 animations:^{
        _panel.alpha = 1;
        _panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismissCommandPanel
{
    if (!_panel) return;
    [_panel removeFromSuperview];
    [_shield removeFromSuperview];
    _panel = nil;
    _shield = nil;
    if (_restoreKeyboard) _terminal.keyboardHidden = NO;
    _restoreKeyboard = NO;
}

- (void)layoutPanel
{
    CGRect b = self.view.bounds;
    CGFloat bottom = b.size.height - kBarH - 6.0f;         /* just above the key bar, where it rests with the keyboard folded */
    CGFloat w = MIN(290.0f, b.size.width - 16.0f);
    CGFloat h = MIN(320.0f, bottom - 8.0f);
    if (h < 110.0f) h = 110.0f;
    _panel.transform = CGAffineTransformIdentity;
    _panel.frame = CGRectMake(b.size.width - w - 8.0f, bottom - h, w, h);   /* right side, above the gear key */
}

- (void)refreshPanel
{
    [_panel setSessionCount:(NSInteger)[_sessions count] selected:_current commands:[Settings shared].commands];
}

- (void)commandPanel:(CommandPanelView *)panel didSelectCommand:(NSString *)command
{
    [self dismissCommandPanel];
    [_terminal typeText:command];
    if ([Settings shared].runCommandOnTap) [_terminal typeText:@"\r"];
}

- (void)commandPanel:(CommandPanelView *)panel didSelectSessionAtIndex:(NSInteger)index
{
    [self selectSessionAtIndex:index];
}

- (void)commandPanelDidAddSession:(CommandPanelView *)panel
{
    [self addSession];
}

- (void)commandPanelDidCloseSession:(CommandPanelView *)panel
{
    [self closeCurrentSession];
}

#pragma mark - Rotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

@end
