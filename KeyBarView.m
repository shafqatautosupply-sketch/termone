#import "KeyBarView.h"

/* Standard UIKit: a UIToolbar in the iOS 6 black opaque style holding bordered UIBarButtonItems.
 * Only the gear icon and the swipe-to-move-cursor gesture are ours. */

typedef enum { KeyBarAxisNone = 0, KeyBarAxisHorizontal, KeyBarAxisVertical } KeyBarAxis;

static const CGFloat kGearZone = 56.0f;      /* right-hand strip of the bar that counts as "the gear" for press and hold */

@interface KeyBarView () <UIGestureRecognizerDelegate> {
    UIBarButtonItem *_esc, *_ctrl, *_alt, *_tab, *_gear;
    NSMutableArray *_keyItems;               /* every key with a fixed width ... */
    NSMutableArray *_baseWidths;             /* ... and its width at 320 pt, to scale on wider screens */
    CGFloat _scale;
    BOOL _ctrlOn, _altOn;
    UILongPressGestureRecognizer *_longPress;
    CGFloat _accX, _accY;
    KeyBarAxis _axis;
}
@end

@implementation KeyBarView

/* Own ivar name: UIToolbar may already have a _delegate ivar of its own. */
@synthesize delegate = _keyBarDelegate;

static UIImage *GearIcon(void)
{
    CGSize sz = CGSizeMake(24, 24);
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(c, 12, 12);
    [[UIColor whiteColor] setFill];                              /* toolbar images are used as a mask: only the alpha matters */

    int i;
    for (i = 0; i < 8; i++) {                                    /* teeth */
        CGContextSaveGState(c);
        CGContextRotateCTM(c, i * (float)M_PI / 4.0f);
        CGContextFillRect(c, CGRectMake(-2.3f, -11.0f, 4.6f, 5.5f));
        CGContextRestoreGState(c);
    }
    CGContextAddEllipseInRect(c, CGRectMake(-7.6f, -7.6f, 15.2f, 15.2f));   /* body */
    CGContextAddEllipseInRect(c, CGRectMake(-3.3f, -3.3f, 6.6f, 6.6f));     /* hole */
    CGContextEOFillPath(c);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (UIBarButtonItem *)keyWithTitle:(NSString *)title width:(CGFloat)w action:(SEL)action
{
    UIBarButtonItem *it = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered target:self action:action];
    it.width = w;
    [_keyItems addObject:it];
    [_baseWidths addObject:[NSNumber numberWithFloat:(float)w]];
    return it;
}

- (UIBarButtonItem *)flex
{
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.barStyle = UIBarStyleBlackOpaque;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _keyItems = [NSMutableArray array];
        _baseWidths = [NSMutableArray array];
        _scale = 1.0f;

        _esc  = [self keyWithTitle:@"Esc"  width:40 action:@selector(tapEsc:)];
        _ctrl = [self keyWithTitle:@"Ctrl" width:42 action:@selector(toggleModifier:)];
        _alt  = [self keyWithTitle:@"Alt"  width:36 action:@selector(toggleModifier:)];
        _tab  = [self keyWithTitle:@"Tab"  width:36 action:@selector(tapTab:)];
        UIBarButtonItem *pipe  = [self keyWithTitle:@"|" width:28 action:@selector(tapSymbol:)];
        UIBarButtonItem *slash = [self keyWithTitle:@"/" width:28 action:@selector(tapSymbol:)];
        UIBarButtonItem *dash  = [self keyWithTitle:@"-" width:28 action:@selector(tapSymbol:)];

        _gear = [[UIBarButtonItem alloc] initWithImage:GearIcon() style:UIBarButtonItemStyleBordered
                                                target:self action:@selector(tapSettings:)];
        _gear.width = 36;
        [_keyItems addObject:_gear];
        [_baseWidths addObject:[NSNumber numberWithFloat:36]];

        [self setItems:[NSArray arrayWithObjects:
                        _esc, [self flex], _ctrl, [self flex], _alt, [self flex], _tab, [self flex],
                        pipe, [self flex], slash, [self flex], dash, [self flex], _gear, nil] animated:NO];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        _longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        _longPress.minimumPressDuration = 0.4;
        _longPress.delegate = self;
        [self addGestureRecognizer:_longPress];
    }
    return self;
}

- (BOOL)ctrlActive { return _ctrlOn; }
- (BOOL)altActive  { return _altOn; }

- (void)refreshModifierLook
{
    UIColor *lit = [UIColor colorWithRed:0.20f green:0.45f blue:0.95f alpha:1];   /* lit = tinted blue */
    _ctrl.tintColor = _ctrlOn ? lit : nil;
    _alt.tintColor  = _altOn  ? lit : nil;
}

- (void)clearModifiers
{
    _ctrlOn = NO;
    _altOn = NO;
    [self refreshModifierLook];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat scale = self.bounds.size.width / 320.0f;             /* wider (landscape) = wider keys */
    if (scale < 1.0f) scale = 1.0f;
    if (scale > 1.8f) scale = 1.8f;
    if (fabsf(scale - _scale) < 0.01f) return;
    _scale = scale;
    NSUInteger i;
    for (i = 0; i < [_keyItems count]; i++)
        [[_keyItems objectAtIndex:i] setWidth:floorf([[_baseWidths objectAtIndex:i] floatValue] * scale)];
    [self setItems:[self items] animated:NO];
}

#pragma mark Key actions

- (void)tapEsc:(id)sender      { [self.delegate keyBarDidTapEscape:self]; }
- (void)tapTab:(id)sender      { [self.delegate keyBarDidTapTab:self]; }
- (void)tapSettings:(id)sender { [self.delegate keyBarDidTapSettings:self]; }
- (void)tapSymbol:(UIBarButtonItem *)sender { [self.delegate keyBar:self didTapText:sender.title]; }

- (void)toggleModifier:(UIBarButtonItem *)sender
{
    if (sender == _ctrl) _ctrlOn = !_ctrlOn;
    else                 _altOn  = !_altOn;
    [self refreshModifierLook];
}

#pragma mark Press and hold on the gear

/* The long press only begins over the gear, so holding any other key still taps normally. */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g
{
    if (g == _longPress) return [g locationInView:self].x > self.bounds.size.width - kGearZone;
    return YES;
}

- (void)longPress:(UILongPressGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) [self.delegate keyBarDidLongPressSettings:self];
}

#pragma mark Swipe = move cursor (one axis per gesture)

- (void)handlePan:(UIPanGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) {
        _accX = 0;
        _accY = 0;
        _axis = KeyBarAxisNone;
    }
    if (g.state != UIGestureRecognizerStateBegan && g.state != UIGestureRecognizerStateChanged) return;

    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];

    /* The first movement decides the axis; the other axis is ignored until the finger lifts. */
    if (_axis == KeyBarAxisNone)
        _axis = (fabsf(t.x) >= fabsf(t.y)) ? KeyBarAxisHorizontal : KeyBarAxisVertical;

    NSInteger dx = 0, dy = 0;
    if (_axis == KeyBarAxisHorizontal) {
        CGPoint v = [g velocityInView:self];
        CGFloat stepX = (fabsf(v.x) > 700.0f) ? 6.0f : 11.0f;   /* faster flick = longer jumps */
        _accX += t.x;
        dx = (NSInteger)(_accX / stepX);
        _accX -= dx * stepX;
    } else {
        const CGFloat stepY = 22.0f;
        _accY += t.y;
        dy = (NSInteger)(_accY / stepY);
        _accY -= dy * stepY;
    }
    if (dx != 0 || dy != 0) [self.delegate keyBar:self moveByDX:dx dy:dy];
}

@end
