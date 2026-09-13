#import "FangUIOrientationBridge.h"
#import <objc/runtime.h>

static id gObserver = nil;

@implementation FangUIOrientationBridge

+ (void)startObserving:(void (^)(NSInteger, double))handler {
    [self stopObserving];

    Class cls = objc_getClass("FBSOrientationObserver");
    if (cls) {
        id obs = [[cls alloc] init];
        gObserver = obs;

        SEL setSel = NSSelectorFromString(@"setHandler:");
        if ([obs respondsToSelector:setSel]) {
            // handler receives FBSOrientationUpdate: orientation / duration
            void (^block)(id) = ^(id update) {
                NSInteger orientation = UIInterfaceOrientationUnknown;
                double duration = 0.25;

                SEL oSel = NSSelectorFromString(@"orientation");
                if ([update respondsToSelector:oSel]) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                                         [update methodSignatureForSelector:oSel]];
                    inv.target = update;
                    inv.selector = oSel;
                    [inv invoke];
                    long long v = 0;
                    [inv getReturnValue:&v];
                    orientation = (NSInteger)v;
                }

                SEL dSel = NSSelectorFromString(@"duration");
                if ([update respondsToSelector:dSel]) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:
                                         [update methodSignatureForSelector:dSel]];
                    inv.target = update;
                    inv.selector = dSel;
                    [inv invoke];
                    double d = 0;
                    [inv getReturnValue:&d];
                    if (d > 0) { duration = d; }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(orientation, duration);
                });
            };

            NSMethodSignature *sig = [obs methodSignatureForSelector:setSel];
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = obs;
            inv.selector = setSel;
            id b = block;
            [inv setArgument:&b atIndex:2];
            [inv invoke];
            return;
        }
    }

    // Fallback: UIDevice orientation notifications
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        UIDeviceOrientation d = [UIDevice currentDevice].orientation;
        UIInterfaceOrientation o = UIInterfaceOrientationPortrait;
        switch (d) {
            case UIDeviceOrientationLandscapeLeft:  o = UIInterfaceOrientationLandscapeRight; break;
            case UIDeviceOrientationLandscapeRight: o = UIInterfaceOrientationLandscapeLeft;  break;
            case UIDeviceOrientationPortraitUpsideDown: o = UIInterfaceOrientationPortraitUpsideDown; break;
            case UIDeviceOrientationPortrait: o = UIInterfaceOrientationPortrait; break;
            default: return;
        }
        handler((NSInteger)o, 0.25);
    }];
}

+ (void)stopObserving {
    if (gObserver) {
        SEL inv = NSSelectorFromString(@"invalidate");
        if ([gObserver respondsToSelector:inv]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [gObserver performSelector:inv];
#pragma clang diagnostic pop
        }
        gObserver = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSInteger)activeOrientation {
    Class cls = objc_getClass("FBSOrientationObserver");
    if (cls) {
        id obs = [[cls alloc] init];
        SEL sel = NSSelectorFromString(@"activeInterfaceOrientation");
        if ([obs respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            long long v = (long long)[obs performSelector:sel];
#pragma clang diagnostic pop
            if (v > 0) { return (NSInteger)v; }
        }
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    return (NSInteger)ws.interfaceOrientation;
                }
            }
        }
    }
    return (NSInteger)UIInterfaceOrientationUnknown;
}

@end
