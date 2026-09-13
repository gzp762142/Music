#import "FangUISBSHosting.h"
#import <objc/runtime.h>

// UIWindow private SPI — context id used by SpringBoard hosting.
@interface UIWindow (FangUIPrivate)
- (unsigned int)_contextId;
@end

@implementation FangUISBSHosting {
    id _hostingController; // SBSAccessibilityWindowHostingController
}

+ (instancetype)shared {
    static FangUISBSHosting *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FangUISBSHosting new]; });
    return s;
}

- (BOOL)registerWindow:(UIWindow *)window {
    if (!window) { return NO; }
    return [self registerWindow:window atLevel:(double)window.windowLevel];
}

- (BOOL)registerWindow:(UIWindow *)window atLevel:(double)level {
    if (!window) { return NO; }

    Class cls = objc_getClass("SBSAccessibilityWindowHostingController");
    if (!cls) {
        NSLog(@"[FangUISBSHosting] SBSAccessibilityWindowHostingController missing");
        return NO;
    }

    if (!_hostingController) {
        _hostingController = [[cls alloc] init];
    }

    // _contextId is SPI; respondsToSelector guard.
    if (![window respondsToSelector:@selector(_contextId)]) {
        NSLog(@"[FangUISBSHosting] UIWindow has no _contextId");
        return NO;
    }

    unsigned int ctxId = [window _contextId];
    if (ctxId == 0) {
        NSLog(@"[FangUISBSHosting] contextId is 0 (window not yet in CA?)");
        return NO;
    }

    // registerWindowWithContextID:atLevel:  →  v@:Id
    SEL sel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![_hostingController respondsToSelector:sel]) {
        NSLog(@"[FangUISBSHosting] hosting controller missing selector");
        return NO;
    }

    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = _hostingController;
    inv.selector = sel;
    [inv setArgument:&ctxId atIndex:2];
    [inv setArgument:&level atIndex:3];
    [inv invoke];

    NSLog(@"[FangUISBSHosting] registered ctx=%u level=%.1f", ctxId, level);
    return YES;
}

@end
