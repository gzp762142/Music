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
            reassert(w)
            registerWithSpringBoard(w)
            startKeepAlive()
            return
        }

        let w = FangUIOverlayWindow(frame: UIScreen.main.bounds)
        w.windowLevel = levelSystem
        w.backgroundColor = .clear
        w.isOpaque = false
        w.rootViewController = FangUIPanelHost(onRequestPowerOff: { onPowerOff?(false) })

        if #available(iOS 13.0, *) {
            if let scene = preferredWindowScene() {
                w.windowScene = scene
                w.frame = scene.coordinateSpace.bounds
            }
        }

        w.isHidden = false
        w.alpha = 1
        w.makeKeyAndVisible()

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

// MARK: - Compact draggable panel host
private final class FangUIPanelHost: UIViewController {
    private let content = RootViewController()
    private let panel = UIView()
    private let closeBtn = UIButton(type: .system)
    private let onRequestPowerOff: () -> Void
    private var panelCenter: CGPoint = .zero
    private let panelSize = CGSize(width: 340, height: 520)

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

        panel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        panel.layer.cornerRadius = 20
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        panel.clipsToBounds = true
        view.addSubview(panel)

        addChild(content)
        content.view.frame = CGRect(origin: .zero, size: panelSize)
        panel.addSubview(content.view)
        content.didMove(toParent: self)

        closeBtn.setTitle("关闭", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.layer.cornerRadius = 14
        closeBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        closeBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        panel.addSubview(closeBtn)

        panel.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(onPan(_:))))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if panelCenter == .zero {
            panelCenter = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        }
        layoutPanel()
    }

    private func layoutPanel() {
        panel.bounds = CGRect(origin: .zero, size: panelSize)
        panel.center = panelCenter
        content.view.frame = panel.bounds
        closeBtn.sizeToFit()
        closeBtn.frame = CGRect(
            x: panelSize.width - closeBtn.bounds.width - 10,
            y: 10,
            width: closeBtn.bounds.width,
            height: max(28, closeBtn.bounds.height)
        )
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        panelCenter = CGPoint(x: panelCenter.x + t.x, y: panelCenter.y + t.y)
        g.setTranslation(.zero, in: view)
        let half = CGSize(width: panelSize.width / 2, height: panelSize.height / 2)
        panelCenter.x = min(max(panelCenter.x, half.width), view.bounds.width - half.width)
        panelCenter.y = min(max(panelCenter.y, half.height), view.bounds.height - half.height)
        layoutPanel()
    }

    @objc private func onClose() {
        onRequestPowerOff()
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
