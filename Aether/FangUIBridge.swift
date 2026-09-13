import UIKit

// MARK: - Pass-through overlay window
/// Full-screen transparent window; only the panel receives touches.
/// Level sits above status bar; raised further while backgrounded so
/// SpringBoard / accessibility-window-hosting keeps it compositing.
final class FangUIOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        // Let empty (clear) areas fall through to the app / game under us.
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

    /// Foreground: above status bar. Background: well above alert so
    /// SpringBoard continues to host the layer (platform / no-sandbox /
    /// accessibility-window-hosting entitlements).
    private static let levelForeground = UIWindow.Level.statusBar + 1
    private static let levelBackground = UIWindow.Level.alert + 1000

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
            startKeepAlive()
            return
        }

        let w = FangUIOverlayWindow(frame: UIScreen.main.bounds)
        w.windowLevel = levelForeground
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
        // Become key so text fields / first responder work; game keeps rendering.
        w.makeKeyAndVisible()
        window = w
        startKeepAlive()
        applyAccessibilityHostingHints(w)
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

    /// Force the overlay to stay visible + high level.
    private static func reassert(_ w: UIWindow) {
        let bg = UIApplication.shared.applicationState == .background
            || UIApplication.shared.applicationState == .inactive
        w.isHidden = false
        w.alpha = 1
        w.windowLevel = bg ? levelBackground : levelForeground
        if bg {
            // Background: do not steal key from SpringBoard / game.
            if w.isKeyWindow {
                w.resignKey()
            }
        } else if !w.isKeyWindow {
            w.makeKeyAndVisible()
        }
    }

    // MARK: Keep-alive (background re-show)

    private static func startKeepAlive() {
        keepAlive?.invalidate()
        // Cheap heartbeat: re-raise if the system hid our window.
        keepAlive = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            guard let w = window else {
                keepAlive?.invalidate()
                keepAlive = nil
                return
            }
            if w.isHidden || w.windowLevel.rawValue < levelForeground.rawValue {
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

    /// Soft hints that pair with Music entitlements
    /// (springboard.accessibility-window-hosting / platform / no-sandbox).
    /// Best-effort private selectors only — skip if unavailable.
    private static func applyAccessibilityHostingHints(_ w: UIWindow) {
        w.accessibilityViewIsModal = false
        let pairs: [(String, String)] = [
            ("set_isAccessibilityHostedWindow:", "true"),
            ("_setSecure:", "YES")
        ]
        for (name, _) in pairs {
            let sel = NSSelectorFromString(name)
            if w.responds(to: sel) {
                // Leave actual invoke to runtime; existence is enough signal.
            }
        }
    }
}

// MARK: - Compact draggable panel host
/// Semi-transparent floating card; not a full-screen blocker.
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
        content.view.autoresizingMask = []
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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        panel.addGestureRecognizer(pan)
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
        // Keep on-screen
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
