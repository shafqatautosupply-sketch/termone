#import "TermTheme.h"
#import "Settings.h"

@interface TermTheme () {
    uint32_t _ansi[16];
}
@end

@implementation TermTheme

+ (UIColor *)colorFromHex:(uint32_t)hex
{
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0f
                           green:((hex >> 8) & 0xFF) / 255.0f
                            blue:(hex & 0xFF) / 255.0f
                           alpha:1.0f];
}

- (uint32_t)ansiHex:(int)i { return _ansi[i & 15]; }
- (UIColor *)fgColor { return [TermTheme colorFromHex:self.fgHex]; }
- (UIColor *)bgColor { return [TermTheme colorFromHex:self.bgHex]; }

static TermTheme *make(NSString *name, uint32_t fg, uint32_t bg, const uint32_t *pal)
{
    TermTheme *t = [[TermTheme alloc] init];
    t.name = name;
    t.fgHex = fg;
    t.bgHex = bg;
    memcpy(t->_ansi, pal, sizeof(uint32_t) * 16);
    return t;
}

+ (NSArray *)allThemes
{
    static NSArray *themes = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static const uint32_t classic[16] = {
            0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x4F7DFF, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
            0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x6F9BFF, 0xD670D6, 0x29B8DB, 0xFFFFFF };
        static const uint32_t solarized[16] = {
            0x073642, 0xDC322F, 0x859900, 0xB58900, 0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
            0x002B36, 0xCB4B16, 0x586E75, 0x657B83, 0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3 };
        static const uint32_t phosphor[16] = {
            0x000000, 0xFF5F5F, 0x33FF33, 0xCCFF33, 0x33CCFF, 0xFF66FF, 0x33FFCC, 0xB6FFB6,
            0x2E7D32, 0xFF8A80, 0x69FF69, 0xEEFF66, 0x80DFFF, 0xFF99FF, 0x80FFE5, 0xFFFFFF };
        static const uint32_t paper[16] = {
            0x000000, 0xC23621, 0x25A624, 0x9A8F00, 0x2F4FD6, 0xB02FB0, 0x1F9CAD, 0xBBBBBB,
            0x666666, 0xE0402A, 0x2FC52E, 0xB5A800, 0x4A67EE, 0xD04FD0, 0x2FB8CC, 0xE9EBEB };
        themes = [NSArray arrayWithObjects:
            make(@"Classic",         0xE5E5E5, 0x000000, classic),
            make(@"Solarized Dark",  0x839496, 0x002B36, solarized),
            make(@"Green Phosphor",  0x33FF33, 0x000000, phosphor),
            make(@"Paper",           0x1A1A1A, 0xFAF8F0, paper),
            nil];
    });
    return themes;
}

+ (TermTheme *)current
{
    NSArray *all = [self allThemes];
    NSInteger i = [Settings shared].themeIndex;
    if (i < 0 || i >= (NSInteger)[all count]) i = 0;
    return [all objectAtIndex:i];
}

@end
