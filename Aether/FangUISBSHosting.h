#import <UIKit/UIKit.h>

/// Registers a UIWindow with SpringBoard via
/// SBSAccessibilityWindowHostingController registerWindowWithContextID:atLevel:
@interface FangUISBSHosting : NSObject

+ (instancetype)shared;

/// Returns YES if registration was invoked (class present + contextId obtained).
- (BOOL)registerWindow:(UIWindow *)window;

/// Re-register at a new level (e.g. after raising windowLevel in background).
- (BOOL)registerWindow:(UIWindow *)window atLevel:(double)level;

@end
