#import "Settings.h"

NSString *const SettingsDidChangeNotification = @"Term6SettingsDidChange";

static NSString *const kUseDaemon   = @"useDaemon";
static NSString *const kRunAsRoot   = @"runAsRoot";
static NSString *const kShellPath   = @"shellPath";
static NSString *const kFontSize    = @"fontSize";
static NSString *const kTheme       = @"themeIndex";
static NSString *const kEncoding    = @"encodingName";
static NSString *const kCommands    = @"savedCommands";
static NSString *const kRunOnTap    = @"runCommandOnTap";
static NSString *const kStartup     = @"startupCommands";
static NSString *const kSessionIds  = @"sessionIds";

@implementation Settings

+ (Settings *)shared
{
    static Settings *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[Settings alloc] init];
        [[NSUserDefaults standardUserDefaults] registerDefaults:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithBool:YES],  kUseDaemon,
                [NSNumber numberWithBool:NO],   kRunAsRoot,
                @"/bin/bash",                   kShellPath,
                [NSNumber numberWithFloat:13],  kFontSize,
                [NSNumber numberWithInt:0],     kTheme,
                @"UTF-8",                      kEncoding,
                [NSNumber numberWithBool:NO],   kRunOnTap,
                [NSArray arrayWithObjects:
                    [NSDictionary dictionaryWithObjectsAndKeys:@"List files",       @"title", @"ls -la",  @"command", nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:@"Parent folder",    @"title", @"cd ..",   @"command", nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:@"Where am I",       @"title", @"pwd",     @"command", nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:@"Live processes",   @"title", @"top",     @"command", nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:@"Disk space",       @"title", @"df -h",   @"command", nil],
                    [NSDictionary dictionaryWithObjectsAndKeys:@"All processes",    @"title", @"ps aux",  @"command", nil],
                    nil], kCommands,
                nil]];
    });
    return s;
}

- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }

- (void)changed
{
    [[self d] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:SettingsDidChangeNotification object:self];
}

- (BOOL)useDaemon { return [[self d] boolForKey:kUseDaemon]; }
- (void)setUseDaemon:(BOOL)v { [[self d] setBool:v forKey:kUseDaemon]; [self changed]; }

- (BOOL)runAsRoot { return [[self d] boolForKey:kRunAsRoot]; }
- (void)setRunAsRoot:(BOOL)v { [[self d] setBool:v forKey:kRunAsRoot]; [self changed]; }

- (NSString *)shellPath
{
    NSString *s = [[self d] stringForKey:kShellPath];
    return [s length] ? s : @"/bin/bash";
}
- (void)setShellPath:(NSString *)v { [[self d] setObject:v forKey:kShellPath]; [self changed]; }

- (CGFloat)fontSize
{
    CGFloat f = [[self d] floatForKey:kFontSize];
    if (f < 7) f = 7;
    if (f > 28) f = 28;
    return f;
}
- (void)setFontSize:(CGFloat)v { [[self d] setFloat:v forKey:kFontSize]; [self changed]; }

- (NSInteger)themeIndex { return [[self d] integerForKey:kTheme]; }
- (void)setThemeIndex:(NSInteger)v { [[self d] setInteger:v forKey:kTheme]; [self changed]; }

- (NSString *)encodingName
{
    NSString *s = [[self d] stringForKey:kEncoding];
    return [s length] ? s : @"UTF-8";
}
- (void)setEncodingName:(NSString *)v { [[self d] setObject:v forKey:kEncoding]; [self changed]; }

- (NSArray *)commands
{
    NSMutableArray *out = [NSMutableArray array];
    for (id item in [[self d] arrayForKey:kCommands]) {
        NSString *title = nil, *cmd = nil;
        if ([item isKindOfClass:[NSDictionary class]]) {
            title = [item objectForKey:@"title"];
            cmd   = [item objectForKey:@"command"];
        } else if ([item isKindOfClass:[NSString class]]) {      /* saved by an older version */
            cmd = item;
        }
        if ([cmd length] == 0) continue;
        if ([title length] == 0) title = cmd;
        [out addObject:[NSDictionary dictionaryWithObjectsAndKeys:title, @"title", cmd, @"command", nil]];
    }
    return out;
}
- (void)setCommands:(NSArray *)v { [[self d] setObject:(v ? v : [NSArray array]) forKey:kCommands]; [[self d] synchronize]; }

- (NSArray *)startupCommands
{
    NSArray *a = [[self d] arrayForKey:kStartup];
    return a ? a : [NSArray array];
}
- (void)setStartupCommands:(NSArray *)v { [[self d] setObject:(v ? v : [NSArray array]) forKey:kStartup]; [[self d] synchronize]; }

- (BOOL)runCommandOnTap { return [[self d] boolForKey:kRunOnTap]; }
- (void)setRunCommandOnTap:(BOOL)v { [[self d] setBool:v forKey:kRunOnTap]; [[self d] synchronize]; }

- (NSArray *)sessionIds
{
    NSArray *a = [[self d] arrayForKey:kSessionIds];
    return a ? a : [NSArray array];
}
- (void)setSessionIds:(NSArray *)v
{
    [[self d] setObject:(v ? v : [NSArray array]) forKey:kSessionIds];
    [[self d] synchronize];
}

@end
