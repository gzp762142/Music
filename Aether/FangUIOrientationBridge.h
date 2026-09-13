#import <UIKit/UIKit.h>

/// FBSOrientationObserver bridge (private SpringBoard orientation source).
/// Falls back to UIDevice when the class is unavailable.
@interface FangUIOrientationBridge : NSObject

/// orientation: UIInterfaceOrientation raw value. duration in seconds.
+ (void)startObserving:(void (^)(NSInteger orientation, double duration))handler;
+ (void)stopObserving;

/// Current active interface orientation (UIInterfaceOrientation raw value).
+ (NSInteger)activeOrientation;

@end
