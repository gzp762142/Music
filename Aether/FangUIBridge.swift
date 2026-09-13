import UIKit

// MARK: - Pass-through overlay window
/// System-level window (ObjC FangUISystemWindow: _isSystemWindow / _isSecure).
/// Empty areas pass through to the app/game underneath.
final class FangUIOverlayWindow: FangUISystemWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        if v === self || v === rootViewController?.view {
            return nil
        }
        return v
    }

    override var canBecomeKey: Bool { true }
}

// MARK: - Bridge
enum FangUIBridge {
    private static var window: FangUIOverlayWindow?
    private static var keepAlive: Timer?
    private static var onPowerOff: ((Bool) -> Void)?
    private static var observers: [NSObjectProtocol] = []

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
        w.backgroundColor = .clear
        w.isOpaque = false
        w.rootViewController = FangUIContentHost(onRequestPowerOff: { onPowerOff?(false) })

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

    /// Rebuild window frame so content is upright on iPad (landscape SpringBoard
    /// + portrait UIScreen.main.bounds is what rotated the menu 90°).
    private static func applySceneGeometry(_ w: UIWindow) {
        w.transform = .identity

        var size = UIScreen.main.bounds.size

        if #available(iOS 13.0, *) {
            let scene = w.windowScene ?? preferredWindowScene()
            if let scene = scene {
                let screen = UIScreen.main.bounds.size
                let longSide = max(screen.width, screen.height)
                let shortSide = min(screen.width, screen.height)
                switch scene.interfaceOrientation {
                case .landscapeLeft, .landscapeRight:
                    size = CGSize(width: longSide, height: shortSide)
                case .portrait, .portraitUpsideDown:
                    size = CGSize(width: shortSide, height: longSide)
                default:
                    // Fall back to scene coordinate space
                    let cs = scene.coordinateSpace.bounds.size
                    if cs.width > 0 && cs.height > 0 { size = cs }
                }
            }
        }

        w.bounds = CGRect(origin: .zero, size: size)
        w.center = CGPoint(x: size.width / 2, y: size.height / 2)
        w.setNeedsLayout()
        w.layoutIfNeeded()
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

// MARK: - Full-rect content host (original FangUI card layout)
/// Uses RootViewController as-is: wide rectangular card, bottom nav, Metal FX.
/// Close is a floating chip — does not shrink / rotate the menu.
private final class FangUIContentHost: UIViewController {
    private let content = RootViewController()
    private let closeBtn = UIButton(type: .system)
    private let onRequestPowerOff: () -> Void

    init(onRequestPowerOff: @escaping () -> Void) {
        self.onRequestPowerOff = onRequestPowerOff
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.transform = .identity

        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.view.transform = .identity
        view.addSubview(content.view)
        content.didMove(toParent: self)

        closeBtn.setTitle("关闭", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.layer.cornerRadius = 16
        closeBtn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        closeBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        view.addSubview(closeBtn)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        content.view.frame = view.bounds
        closeBtn.sizeToFit()
        let top = view.safeAreaInsets.top + 8
        closeBtn.frame = CGRect(
            x: view.bounds.width - closeBtn.bounds.width - 16,
            y: top,
            width: closeBtn.bounds.width,
            height: max(32, closeBtn.bounds.height)
        )
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    @objc private func onClose() {
        onRequestPowerOff()
    }
}
