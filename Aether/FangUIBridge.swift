import UIKit

// MARK: - Overlay window
/// System-level window (ObjC FangUISystemWindow: _isSystemWindow / _isSecure).
/// FangUI 自绘不透明面板：窗口自带底色，任何区域都不透出桌面 / 下层 app。
final class FangUIOverlayWindow: FangUISystemWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Bridge
enum FangUIBridge {
    private static var window: FangUIOverlayWindow?
    private static var keepAlive: Timer?
    private static var onPowerOff: ((Bool) -> Void)?
    private static var observers: [NSObjectProtocol] = []

    /// 面板不透明底色，由 RootViewController 随明暗主题回传。
    private static var surface: UIColor = Palette.light.bg
    /// 面板控制器强引用（视图挂在窗口上，控制器不能被释放）。
    private static var panel: RootViewController?

    /// TrollEngine SHMainWnd: UIWindowLevelStatusBar + 2000
    private static let levelSystem = UIWindow.Level(rawValue: UIWindow.Level.statusBar.rawValue + 2000)

    static var isVisible: Bool {
        guard let w = window else { return false }
        return !w.isHidden && w.alpha > 0.01
    }

    static func setPowerCallback(_ cb: @escaping (Bool) -> Void) {
        onPowerOff = cb
    }

    static func setVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible { show() } else { hide() }
        }
    }

    // MARK: Show / hide

    private static func show() {
        installLifecycleObserversIfNeeded()

        if let w = window {
            applySceneGeometry(w)
            reassert(w)
            registerWithSpringBoard(w)
            startKeepAlive()
            return
        }

        let w = FangUIOverlayWindow(frame: .zero)
        w.windowLevel = levelSystem
        // 不透明底：FangUI 面板是唯一可见层，不存在背景图 / 桌面穿透。
        w.backgroundColor = surface
        w.isOpaque = true

        // 宿主 VC 只管窗口状态；面板视图直接挂在窗口上，
        // 绕开 UIKit 对 rootViewController.view 的方向旋转。
        w.rootViewController = FangUIContentHost()

        let content = RootViewController()
        content.onSurfaceColorChange = { color in surface = color }
        content.onRequestClose = { onPowerOff?(false) }
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        w.addSubview(content.view)
        panel = content

        if #available(iOS 13.0, *) {
            if let scene = preferredWindowScene() {
                w.windowScene = scene
            }
        }
        // Portrait bounds + landscape SpringBoard = 90° rotated text. Always
        // rebuild frame from interface orientation, keep transform identity.
        applySceneGeometry(w)

        w.isHidden = false
        w.alpha = 1
        w.makeKeyAndVisible()
        applySceneGeometry(w)

        // Force context into CA so _contextId is non-zero, then register.
        CATransaction.flush()
        DispatchQueue.main.async {
            registerWithSpringBoard(w)
        }

        window = w
        startKeepAlive()
    }

    private static func hide() {
        keepAlive?.invalidate()
        keepAlive = nil
        guard let w = window else { return }
        window = nil
        panel = nil
        w.isHidden = true
        w.rootViewController = nil
        if w.isKeyWindow {
            if let appWin = UIApplication.shared.windows.first(where: { $0 !== w && !$0.isHidden }) {
                appWin.makeKey()
            }
        }
    }

    /// Cross-app key: SBSAccessibilityWindowHostingController
    /// registerWindowWithContextID:atLevel:
    private static func registerWithSpringBoard(_ w: UIWindow) {
        let ok = FangUISBSHosting.shared().register(w, atLevel: Double(w.windowLevel.rawValue))
        if !ok {
            // Retry once after the window is fully in the hierarchy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                _ = FangUISBSHosting.shared().register(w, atLevel: Double(w.windowLevel.rawValue))
            }
        }
    }

    private static func reassert(_ w: UIWindow) {
        let bg = UIApplication.shared.applicationState == .background
            || UIApplication.shared.applicationState == .inactive
        applySceneGeometry(w)
        w.isHidden = false
        w.alpha = 1
        // Keep system level; never drop below statusBar+1000 (SHMainWnd rule).
        if w.windowLevel.rawValue < UIWindow.Level.statusBar.rawValue + 1000 {
            w.windowLevel = levelSystem
        }
        if bg {
            if w.isKeyWindow { w.resignKey() }
            // Re-register at current level so SpringBoard keeps compositing.
            registerWithSpringBoard(w)
        } else if !w.isKeyWindow {
            w.makeKeyAndVisible()
        }
    }

    /// 用窗口所属场景的坐标空间直接得出 window frame。
    /// 旧实现按 interfaceOrientation 手工拼长宽，在 iPad 横屏 SpringBoard 下会
    /// 算出转过 90° 的 bounds —— 那正是面板旋转、错位、露出桌面的根因。
    /// 这里再取「场景坐标空间 / 屏幕」里更大的那一份，保证铺满整屏：某些 iPad
    /// 分屏或横竖屏组合下 coordinateSpace 会给出竖屏尺寸。
    private static func applySceneGeometry(_ w: UIWindow) {
        // 方向纠偏：UIKit 会按 scene 的界面方向旋转内容，
        // 这里每轮布局都把窗口、宿主 VC 视图、面板视图的 transform 归位。
        w.transform = .identity
        w.rootViewController?.view.transform = .identity
        panel?.view.transform = .identity

        let screen = UIScreen.main.bounds
        var size = screen.size
        if #available(iOS 13.0, *) {
            if let scene = w.windowScene ?? preferredWindowScene() {
                let cs = scene.coordinateSpace.bounds
                if cs.width > 1, cs.height > 1 {
                    size = CGSize(width: max(screen.width, cs.width),
                                  height: max(screen.height, cs.height))
                }
            }
        }

        let frame = CGRect(origin: .zero, size: size)
        if w.frame != frame {
            w.frame = frame
            w.setNeedsLayout()
            w.layoutIfNeeded()
        }
        panel?.view.frame = w.bounds
    }

    // MARK: Keep-alive

    private static func startKeepAlive() {
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            guard let w = window else {
                keepAlive?.invalidate()
                keepAlive = nil
                return
            }
            if w.isHidden || w.windowLevel.rawValue < UIWindow.Level.statusBar.rawValue + 1000 {
                reassert(w)
            } else {
                // Orientation can flip while menu is up (iPad rotate).
                applySceneGeometry(w)
            }
        }
        RunLoop.main.add(keepAlive!, forMode: .common)
    }

    private static func installLifecycleObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willEnterForegroundNotification,
            UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                guard let w = window else { return }
                reassert(w)
            })
        }
    }

    private static func preferredWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let fg = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return fg
        }
        return scenes.first
    }
}

// MARK: - Window state host
/// 空宿主：只提供 key window 需要的 rootViewController 与方向掩码。
/// 面板视图由 FangUIBridge 直接挂在窗口上，绕开 UIKit 按界面方向
/// 对 rootViewController.view 施加的旋转（那正是面板横躺 90° 的来源）。
private final class FangUIContentHost: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        view.transform = .identity
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
