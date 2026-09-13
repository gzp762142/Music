import UIKit

/// Shows / hides FangUI (UIKit + Metal) over the Music shell.
/// Power ON → overlay appears; Power OFF → auto dismiss.
enum FangUIBridge {
    private static var host: FangUIHost?
    private static var onPowerOff: ((Bool) -> Void)?

    static var isVisible: Bool {
        guard let h = host else { return false }
        return h.view.superview != nil && h.view.alpha > 0.01
    }

    static func setPowerCallback(_ cb: @escaping (Bool) -> Void) {
        onPowerOff = cb
    }

    static func setVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            if visible { show() } else { hide() }
        }
    }

    private static func keyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                if let w = scene.windows.first(where: { $0.isKeyWindow }) { return w }
                if let w = scene.windows.first { return w }
            }
        }
        return UIApplication.shared.windows.first { $0.isKeyWindow }
            ?? UIApplication.shared.windows.first
    }

    private static func show() {
        guard let window = keyWindow() else { return }

        // Existing host but detached (e.g. window recreate) → re-attach.
        if let h = host {
            if h.view.superview !== window {
                window.addSubview(h.view)
            }
            h.view.frame = window.bounds
            window.bringSubviewToFront(h.view)
            UIView.animate(withDuration: 0.15) { h.view.alpha = 1 }
            return
        }

        let h = FangUIHost()
        h.onRequestPowerOff = { onPowerOff?(false) }
        h.view.frame = window.bounds
        h.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(h.view)
        h.view.alpha = 0
        UIView.animate(withDuration: 0.28) { h.view.alpha = 1 }
        host = h
    }

    private static func hide() {
        guard let h = host else { return }
        host = nil
        UIView.animate(withDuration: 0.22, animations: {
            h.view.alpha = 0
        }, completion: { _ in
            h.view.removeFromSuperview()
        })
    }
}

/// Thin container that owns RootViewController and a floating close button.
private final class FangUIHost: UIViewController {
    var onRequestPowerOff: (() -> Void)?
    private let content = RootViewController()
    private let closeBtn = UIButton(type: .system)

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

    @objc private func onClose() {
        onRequestPowerOff?()
    }
}
