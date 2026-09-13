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
    /// 用户拖动后的窗口位置：心跳重设几何时沿用它，不再回到默认位。
    private static var customFrame: CGRect?

    /// 拖动把手回调：把窗口搬到新位置并记住。
    static func setPanelFrame(_ frame: CGRect) {
        customFrame = frame
        guard let w = window else { return }
        applySceneGeometry(w)
    }

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
        startOrientationObserver()

        if let w = window {
            applySceneGeometry(w)
            reassert(w)
            registerWithSpringBoard(w)
            startKeepAlive()
            return
        }

        let w = FangUIOverlayWindow(frame: .zero)
        w.windowLevel = levelSystem
        // 窗口只覆盖卡片本身（含阴影边距）：卡片不透明，
        // 卡片之外透出桌面或下层 app —— 这才是外挂悬浮菜单的形态。
        w.backgroundColor = .clear
        w.isOpaque = false

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
        FangUIOrientationBridge.stopObserving()
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

    /// 面板 ＝ 一块悬浮卡片：窗口只覆盖卡片（加上阴影边距）。
    /// 关键：窗口交给 SpringBoard 托管后，系统会按当前界面方向再转一次，
    /// 所以这里不是「强制归零」，而是给窗口施加**反向**变换把它抵消掉。
    private static func applySceneGeometry(_ w: UIWindow) {
        let screen = UIScreen.main.bounds
        let inset = RootViewController.shadowInset
        let panelW = min(max(screen.width * 0.42, 360), 560)
        let panelH = min(max(screen.height * 0.62, 320), 470)
        let winW = panelW + inset * 2
        let winH = panelH + inset * 2

        var frame = customFrame ?? CGRect(
            x: (screen.width - winW) / 2,
            y: max(screen.height * 0.10, (screen.height - winH) / 2 - 40),
            width: winW, height: winH
        )
        frame.size = CGSize(width: winW, height: winH)
        frame.origin.x = min(max(frame.origin.x, 0), max(0, screen.width - winW))
        frame.origin.y = min(max(frame.origin.y, 0), max(0, screen.height - winH))

        // Rotate about the panel centre so counter-rotation keeps it in place.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let comp = compensationTransform()

        let changed = w.bounds.size != CGSize(width: winW, height: winH)
            || w.center != center
            || w.transform != comp

        if changed {
            w.transform = .identity
            w.bounds = CGRect(x: 0, y: 0, width: winW, height: winH)
            w.center = center
            w.transform = comp
            w.rootViewController?.view.transform = .identity
            panel?.view.transform = .identity
            w.setNeedsLayout()
            w.layoutIfNeeded()
        }
        panel?.view.frame = w.bounds
    }

    /// 抵消 SpringBoard 对托管窗口施加的方向旋转。
    private static func compensationTransform() -> CGAffineTransform {
        switch currentOrientation() {
        case .landscapeLeft:       return CGAffineTransform(rotationAngle: .pi / 2)
        case .landscapeRight:      return CGAffineTransform(rotationAngle: -.pi / 2)
        case .portraitUpsideDown:  return CGAffineTransform(rotationAngle: .pi)
        default:                   return .identity
        }
    }

    /// UIInterfaceOrientation from SpringBoard (FBSOrientationObserver) or fallback.
    static func currentOrientation() -> UIInterfaceOrientation {
        let raw = FangUIOrientationBridge.activeOrientation()
        if let o = UIInterfaceOrientation(rawValue: raw), o != .unknown {
            return o
        }
        if #available(iOS 13.0, *) {
            if let scene = preferredWindowScene() {
                let o = scene.interfaceOrientation
                if o != .unknown { return o }
            }
        }
        switch UIDevice.current.orientation {
        case .landscapeLeft:       return .landscapeRight
        case .landscapeRight:      return .landscapeLeft
        case .portraitUpsideDown:  return .portraitUpsideDown
        default:                   return .portrait
        }
    }

    private static func startOrientationObserver() {
        FangUIOrientationBridge.startObserving { _, _ in
            guard let w = window else { return }
            applySceneGeometry(w)
            registerWithSpringBoard(w)
        }
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
