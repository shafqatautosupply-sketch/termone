#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface TermTheme : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) uint32_t fgHex;
@property (nonatomic, assign) uint32_t bgHex;

+ (NSArray *)allThemes;
+ (TermTheme *)current;

- (uint32_t)ansiHex:(int)i;                              /* 0...15 */
- (UIColor *)fgColor;
- (UIColor *)bgColor;
+ (UIColor *)colorFromHex:(uint32_t)hex;

@end
