import UIKit

// MARK: - Pass-through overlay window
/// System window (ObjC FangUISystemWindow). Kept PORTRAIT-shaped; orientation is
/// handled by counter-rotating content (TrollEngine SHRootCtrl pattern), because
/// SpringBoard hosts the layer in portrait space and rotates it itself.
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
        startOrientationObserver()

        if let w = window {
            reassert(w)
            registerWithSpringBoard(w)
            startKeepAlive()
            return
        }

        // Portrait-shaped frame: matches SpringBoard's hosting space.
        let w = FangUIOverlayWindow(frame: UIScreen.main.bounds)
        w.windowLevel = levelSystem
        w.backgroundColor = .clear
        w.isOpaque = false
        w.transform = .identity
        let host = FangUIContentHost(onRequestPowerOff: { onPowerOff?(false) })
        w.rootViewController = host

        if #available(iOS 13.0, *) {
            if let scene = preferredWindowScene() {
                w.windowScene = scene
            }
        }
        w.frame = UIScreen.main.bounds
        w.transform = .identity

        w.isHidden = false
        w.alpha = 1
        w.makeKeyAndVisible()

        host.applyOrientation(FangUIBridge.currentOrientation(), animated: false)

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
        w.isHidden = true
        w.rootViewController = nil
        if w.isKeyWindow {
            if let appWin = UIApplication.shared.windows.first(where: { $0 !== w && !$0.isHidden }) {
                appWin.makeKey()
            }
        }
    }

    // MARK: Orientation

    /// UIInterfaceOrientation from SpringBoard if possible, else scene/device.
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
        let device = UIDevice.current.orientation
        switch device {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }

    private static func startOrientationObserver() {
        FangUIOrientationBridge.startObserving { orientationRaw, duration in
            guard let w = window, let host = w.rootViewController as? FangUIContentHost else { return }
            let o = UIInterfaceOrientation(rawValue: orientationRaw) ?? .portrait
            host.applyOrientation(o, animated: true, duration: duration)
            // Re-register so SpringBoard picks up the refreshed context.
            registerWithSpringBoard(w)
        }
    }

    // MARK: SpringBoard registration

    private static func registerWithSpringBoard(_ w: UIWindow) {
        let ok = FangUISBSHosting.shared().register(w, atLevel: Double(w.windowLevel.rawValue))
        if !ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                _ = FangUISBSHosting.shared().register(w, atLevel: Double(w.windowLevel.rawValue))
            }
        }
    }

    private static func reassert(_ w: UIWindow) {
        let bg = UIApplication.shared.applicationState == .background
            || UIApplication.shared.applicationState == .inactive
        // Keep portrait frame; do not fight SpringBoard with geometry changes.
        w.transform = .identity
        if w.frame != UIScreen.main.bounds {
            w.frame = UIScreen.main.bounds
        }
        w.isHidden = false
        w.alpha = 1
        if w.windowLevel.rawValue < UIWindow.Level.statusBar.rawValue + 1000 {
            w.windowLevel = levelSystem
        }
        (w.rootViewController as? FangUIContentHost)?
            .applyOrientation(currentOrientation(), animated: false)

        if bg {
            if w.isKeyWindow { w.resignKey() }
            registerWithSpringBoard(w)
        } else if !w.isKeyWindow {
            w.makeKeyAndVisible()
        }
    }

    // MARK: Keep-alive

    private static func startKeepAlive() {
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let w = window else {
                keepAlive?.invalidate()
                keepAlive = nil
                return
            }
            if w.isHidden || w.windowLevel.rawValue < UIWindow.Level.statusBar.rawValue + 1000 {
                reassert(w)
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

// MARK: - Content host with orientation compensation
private final class FangUIContentHost: UIViewController {
    private let content = RootViewController()
    private let closeBtn = UIButton(type: .system)
    private let onRequestPowerOff: () -> Void
    private var currentOrientation: UIInterfaceOrientation = .portrait

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
        view.clipsToBounds = false

        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = []
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

    // MARK: Orientation (TrollEngine SHRootCtrl pattern)

    private static func rotationTransform(for o: UIInterfaceOrientation) -> CGAffineTransform {
        switch o {
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft:      return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeRight:     return CGAffineTransform(rotationAngle: .pi / 2)
        default:                  return .identity
        }
    }

    func applyOrientation(_ orientation: UIInterfaceOrientation,
                          animated: Bool,
                          duration: TimeInterval = 0.25) {
        let screen = UIScreen.main.bounds.size
        let insets = view.safeAreaInsets
        let safeW = screen.width - insets.left - insets.right
        let safeH = screen.height - insets.top - insets.bottom

        let isLandscape = orientation == .landscapeLeft || orientation == .landscapeRight
        let w = isLandscape ? max(safeW, safeH) : min(safeW, safeH)
        let h = isLandscape ? min(safeW, safeH) : max(safeW, safeH)
        let bounds = CGRect(x: 0, y: 0, width: w, height: h)

        let t = FangUIContentHost.rotationTransform(for: orientation)
        let inv = t.inverted()

        let apply = {
            // Outer: rotate to cancel SpringBoard's own rotation.
            self.view.transform = t
            self.view.bounds = bounds
            // Inner: counter-rotate so the menu reads upright, laid out landscape.
            self.content.view.transform = inv
            self.content.view.bounds = bounds
            self.content.view.center = CGPoint(x: bounds.midX, y: bounds.midY)
            self.layoutCloseButton(in: bounds)
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }

        currentOrientation = orientation

        if animated && duration > 0 {
            UIView.animate(withDuration: duration, animations: apply)
        } else {
            apply()
        }
    }

    private func layoutCloseButton(in bounds: CGRect) {
        closeBtn.sizeToFit()
        closeBtn.frame = CGRect(
            x: bounds.width - closeBtn.bounds.width - 16,
            y: 16,
            width: closeBtn.bounds.width,
            height: max(32, closeBtn.bounds.height)
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCloseButton(in: view.bounds)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    @objc private func onClose() {
        onRequestPowerOff()
    }
}
