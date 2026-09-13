#import "FangUISystemWindow.h"

@implementation FangUISystemWindow

// Mark as system window so SpringBoard / UIKit treat it as hostable overlay.
+ (BOOL)_isSystemWindow { return YES; }

// Opt out of WindowServer-managed hosting (we register via SBS ourselves).
- (BOOL)_isWindowServerHostingManaged { return NO; }

// Interactive menu: do not ignore hit-test.
- (BOOL)_ignoresHitTest { return NO; }

// Secure window + secure context (blocks screenshots of this layer on some OS).
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

@end
