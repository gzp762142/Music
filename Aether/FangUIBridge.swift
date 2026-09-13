import UIKit

/// FangUI as a standalone high-level UIWindow (not a subview of the app window).
/// With Music platform entitlements it can stay visible over other apps
/// (game overlay style). Volume keys / power only toggle this window.
enum FangUIBridge {
    private static var window: UIWindow?
    private static var onPowerOff: ((Bool) -> Void)?

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

    private static func show() {
        if let w = window {
            // Already exists → just unhide / raise.
            w.isHidden = false
            w.alpha = 1
            // Keep it above status bar; raise further if something took the level.
            if w.windowLevel <= .statusBar {
                w.windowLevel = UIWindow.Level.statusBar + 1
            }
            // Do not steal key from the game forever; only become key briefly
            // so the first responder chain works when menu opens.
            w.makeKeyAndVisible()
            return
        }

        let w = UIWindow(frame: UIScreen.main.bounds)
        w.windowLevel = UIWindow.Level.statusBar + 1
        w.backgroundColor = .clear
        w.isOpaque = false
        w.rootViewController = FangUIHost(onRequestPowerOff: { onPowerOff?(false) })
        // No autoresizing on window itself; scene/rotation handled in host.
        if #available(iOS 13.0, *) {
            if let scene = preferredWindowScene() {
                w.windowScene = scene
                w.frame = scene.coordinateSpace.bounds
            }
        }
        w.isHidden = false
        w.alpha = 1
        w.makeKeyAndVisible()
        window = w
    }

    private static func hide() {
        guard let w = window else { return }
        window = nil
        w.isHidden = true
        w.rootViewController = nil
        // Resign key so the game / shell can take it back.
        if w.isKeyWindow {
            // Prefer the app's original window as key again.
            if let appWin = UIApplication.shared.windows.first(where: { $0 !== w && !$0.isHidden }) {
                appWin.makeKey()
            } else {
                w.resignKey()
            }
        }
    }

    private static func preferredWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // Prefer foreground active, else any.
        if let fg = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return fg
        }
        return scenes.first
    }
}

/// Full-screen host: Metal/UIKit menu + floating close.
private final class FangUIHost: UIViewController {
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

        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
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

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    @objc private func onClose() {
        onRequestPowerOff()
    }
}
