#import "KeyButton.h"

id KBColor(CGFloat r, CGFloat g, CGFloat b)
{
    return (__bridge id)[UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:1].CGColor;
}

void KBSetGloss(CAGradientLayer *g, id t0, id t1, id b0, id b1)
{
    g.colors = [NSArray arrayWithObjects:t0, t1, b0, b1, nil];
    g.locations = [NSArray arrayWithObjects:
                   [NSNumber numberWithFloat:0.0f], [NSNumber numberWithFloat:0.5f],
                   [NSNumber numberWithFloat:0.5f], [NSNumber numberWithFloat:1.0f], nil];
}

@implementation KeyButton

+ (Class)layerClass { return [CAGradientLayer class]; }

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        CALayer *l = self.layer;
        l.cornerRadius = 4.5f;
        l.borderWidth = 1.0f;
        l.borderColor = [UIColor colorWithWhite:0 alpha:0.9f].CGColor;
        l.shadowColor = [UIColor whiteColor].CGColor;           /* faint lower highlight, as on real bar buttons */
        l.shadowOpacity = 0.22f;
        l.shadowOffset = CGSizeMake(0, 1);
        l.shadowRadius = 0;

        self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.titleLabel.shadowOffset = CGSizeMake(0, -1);
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected | UIControlStateHighlighted];
        [self setTitleColor:[UIColor colorWithWhite:1 alpha:0.35f] forState:UIControlStateDisabled];
        UIColor *sh = [UIColor colorWithWhite:0 alpha:0.75f];
        [self setTitleShadowColor:sh forState:UIControlStateNormal];
        [self setTitleShadowColor:sh forState:UIControlStateHighlighted];
        [self setTitleShadowColor:sh forState:UIControlStateSelected];
        [self setTitleShadowColor:sh forState:UIControlStateSelected | UIControlStateHighlighted];
        [self updateLook];
    }
    return self;
}

- (void)updateLook
{
    CAGradientLayer *g = (CAGradientLayer *)self.layer;
    if (self.selected) {                                         /* lit: blue, like a "Done" button */
        if (self.highlighted) KBSetGloss(g, KBColor(92, 140, 214), KBColor(54, 104, 196), KBColor(28, 80, 176), KBColor(18, 60, 146));
        else                  KBSetGloss(g, KBColor(124, 172, 240), KBColor(76, 130, 222), KBColor(40, 100, 210), KBColor(24, 76, 176));
    } else {
        if (self.highlighted) KBSetGloss(g, KBColor(60, 63, 68), KBColor(40, 42, 46), KBColor(26, 28, 31), KBColor(14, 15, 17));
        else                  KBSetGloss(g, KBColor(108, 112, 118), KBColor(72, 75, 81), KBColor(44, 46, 51), KBColor(30, 32, 36));
    }
}

- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self updateLook]; }
- (void)setSelected:(BOOL)s    { [super setSelected:s];    [self updateLook]; }

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:4.5f].CGPath;
}

@end
