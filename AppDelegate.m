#import "AppDelegate.h"
#import "TerminalViewController.h"
#import "Settings.h"
#include <signal.h>

@interface AppDelegate () {
    TerminalViewController *_vc;
    UIBackgroundTaskIdentifier _bgTask;
}
@end

@implementation AppDelegate

@synthesize window = _window;

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts
{
    signal(SIGPIPE, SIG_IGN);
    signal(SIGCHLD, SIG_IGN);                 /* local-mode shells get reaped automatically */
    _bgTask = UIBackgroundTaskInvalid;

    [Settings shared];
    app.statusBarStyle = UIStatusBarStyleBlackOpaque;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];
    _vc = [[TerminalViewController alloc] init];
    self.window.rootViewController = _vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)app
{
    /* Local-mode shells get a few extra minutes; daemon-mode shells keep running regardless. */
    if (_bgTask != UIBackgroundTaskInvalid) return;
    _bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
        [app endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)app
{
    if (_bgTask != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }
    [_vc reconnectAll];
}

@end
