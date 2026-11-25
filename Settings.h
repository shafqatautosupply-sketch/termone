#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const SettingsDidChangeNotification;

@interface Settings : NSObject

+ (Settings *)shared;

/* Keep shells in the root daemon (term6d) so they survive the app being suspended/killed. */
@property (nonatomic, assign) BOOL useDaemon;
/* Only honoured in daemon mode: start the shell as root instead of "mobile". */
@property (nonatomic, assign) BOOL runAsRoot;
@property (nonatomic, copy)   NSString *shellPath;
@property (nonatomic, assign) CGFloat fontSize;
@property (nonatomic, assign) NSInteger themeIndex;
/* Name of a TermEncoding ("UTF-8" by default). */
@property (nonatomic, copy)   NSString *encodingName;

/* Saved commands shown in the long-press panel: array of NSDictionary with @"title" and @"command".
   Plain strings saved by older versions are upgraded on read (title = the command). */
@property (nonatomic, copy) NSArray *commands;
/* Commands typed automatically into every NEW session (array of NSString). */
@property (nonatomic, copy) NSArray *startupCommands;
/* Press Return right after inserting a saved command. */
@property (nonatomic, assign) BOOL runCommandOnTap;
/* Daemon session ids of the open tabs, in order (array of NSNumber). Not a user-visible setting. */
@property (nonatomic, copy) NSArray *sessionIds;

@end
