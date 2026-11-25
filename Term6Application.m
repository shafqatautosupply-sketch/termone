#import "Term6Application.h"

@interface Term6Application () {
    NSMutableSet *_keyboardTouches;
}
@end

@implementation Term6Application

- (void)sendEvent:(UIEvent *)event
{
    if (event.type == UIEventTypeTouches) {
        UIWindow *main = self.keyWindow;
        if (!_keyboardTouches) _keyboardTouches = [NSMutableSet set];
        for (UITouch *t in [event allTouches]) {
            UIWindow *w = t.window;
            if (!w || w == main) continue;                      /* only touches in other windows = keyboard */
            if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) [_keyboardTouches removeObject:t];
            else [_keyboardTouches addObject:t];
        }
    }
    [super sendEvent:event];
}

- (BOOL)keyboardTouchActive
{
    /* UITouch objects are updated in place, so finished touches can be pruned here as well. */
    NSMutableArray *dead = [NSMutableArray array];
    for (UITouch *t in _keyboardTouches)
        if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) [dead addObject:t];
    for (UITouch *t in dead) [_keyboardTouches removeObject:t];
    return [_keyboardTouches count] > 0;
}

@end
