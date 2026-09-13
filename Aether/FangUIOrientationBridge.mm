#import "FangUIOrientationBridge.h"
#import <objc/runtime.h>

static id gObserver = nil;
static id gFallbackToken = nil;
static NSInteger gCachedOrientation = 0;
static BOOL gHasCache = NO;

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
                    gCachedOrientation = orientation;
                    gHasCache = YES;
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
    // 块式观察者必须留下 token 才能移除；removeObserver:self 删不掉它。
    gFallbackToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIDeviceOrientationDidChangeNotification
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
        // 兜底路径同样要刷新缓存，否则缓存永远停在第一次的方向。
        gCachedOrientation = (NSInteger)o;
        gHasCache = YES;
        handler((NSInteger)o, 0.25);
    }];
}

+ (void)stopObserving {
    gHasCache = NO;
    gCachedOrientation = 0;
    if (gFallbackToken) {
        [[NSNotificationCenter defaultCenter] removeObserver:gFallbackToken];
        gFallbackToken = nil;
    }
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
}

+ (NSInteger)activeOrientation {
    // 缓存优先：布局每 0.4s 查一次，不能每次都 new 一个 observer。
    if (gHasCache && gCachedOrientation > 0) {
        return gCachedOrientation;
    }

    Class cls = objc_getClass("FBSOrientationObserver");
    if (cls) {
        id obs = [[cls alloc] init];
        SEL sel = NSSelectorFromString(@"activeInterfaceOrientation");
        if ([obs respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            long long v = (long long)[obs performSelector:sel];
#pragma clang diagnostic pop
            if (v > 0) {
                gCachedOrientation = (NSInteger)v;
                gHasCache = YES;
                return gCachedOrientation;
            }
        }
    }

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    NSInteger o = (NSInteger)ws.interfaceOrientation;
                    if (o > 0) {
                        gCachedOrientation = o;
                        gHasCache = YES;
                    }
                    return o;
                }
            }
        }
    }
    return (NSInteger)UIInterfaceOrientationUnknown;
}

@end
