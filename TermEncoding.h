#import <Foundation/Foundation.h>

/* Text encodings Term6 can use between the screen and the shell. */
@interface TermEncoding : NSObject

@property (nonatomic, copy)   NSString *name;            /* shown in Settings, also what is stored */
@property (nonatomic, assign) NSStringEncoding encoding;
@property (nonatomic, copy)   NSString *lang;            /* LANG / LC_CTYPE given to new shells */

+ (NSArray *)all;
+ (TermEncoding *)current;                               /* from Settings */
+ (TermEncoding *)encodingNamed:(NSString *)name;

@end
