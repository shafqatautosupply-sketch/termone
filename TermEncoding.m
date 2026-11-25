#import "TermEncoding.h"
#import "Settings.h"
#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFStringEncodingExt.h>

@implementation TermEncoding

static TermEncoding *make(NSString *name, NSStringEncoding enc, NSString *lang)
{
    TermEncoding *e = [[TermEncoding alloc] init];
    e.name = name;
    e.encoding = enc;
    e.lang = lang;
    return e;
}

static void addCF(NSMutableArray *list, NSString *name, CFStringEncoding cf, NSString *lang)
{
    if (!CFStringIsEncodingAvailable(cf)) return;
    NSStringEncoding ns = CFStringConvertEncodingToNSStringEncoding(cf);
    if (ns == kCFStringEncodingInvalidId) return;
    [list addObject:make(name, ns, lang)];
}

+ (NSArray *)all
{
    static NSArray *list = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        [a addObject:make(@"UTF-8",                      NSUTF8StringEncoding,            @"en_US.UTF-8")];
        [a addObject:make(@"ISO 8859-1 (Latin 1)",       NSISOLatin1StringEncoding,       @"en_US.ISO8859-1")];
        [a addObject:make(@"ISO 8859-2 (Latin 2)",       NSISOLatin2StringEncoding,       @"en_US.ISO8859-2")];
        [a addObject:make(@"Windows-1252",               NSWindowsCP1252StringEncoding,   @"en_US.ISO8859-1")];
        [a addObject:make(@"Windows-1251 (Cyrillic)",    NSWindowsCP1251StringEncoding,   @"ru_RU.CP1251")];
        addCF(a, @"KOI8-R (Cyrillic)",                   kCFStringEncodingKOI8_R,         @"ru_RU.KOI8-R");
        [a addObject:make(@"Mac OS Roman",               NSMacOSRomanStringEncoding,      @"en_US.ISO8859-1")];
        [a addObject:make(@"Shift JIS",                  NSShiftJISStringEncoding,        @"ja_JP.SJIS")];
        [a addObject:make(@"EUC-JP",                     NSJapaneseEUCStringEncoding,     @"ja_JP.eucJP")];
        addCF(a, @"GB 18030 (Chinese)",                  kCFStringEncodingGB_18030_2000,  @"zh_CN.GB18030");
        addCF(a, @"Big5 (Chinese)",                      kCFStringEncodingBig5,           @"zh_TW.Big5");
        addCF(a, @"EUC-KR (Korean)",                     kCFStringEncodingEUC_KR,         @"ko_KR.eucKR");
        [a addObject:make(@"ASCII",                      NSASCIIStringEncoding,           @"C")];
        list = a;
    });
    return list;
}

+ (TermEncoding *)encodingNamed:(NSString *)name
{
    for (TermEncoding *e in [self all])
        if ([e.name isEqualToString:name]) return e;
    return nil;
}

+ (TermEncoding *)current
{
    TermEncoding *e = [self encodingNamed:[Settings shared].encodingName];
    return e ? e : [[self all] objectAtIndex:0];
}

@end
