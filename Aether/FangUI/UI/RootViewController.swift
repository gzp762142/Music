import UIKit

/// 鏍规帶鍒跺櫒锛歁etal 鐗规晥灞?+ 鍗＄墖 + 鏍囬鏍?+ 鍒嗛〉鍐呭 + 搴曢儴鐜荤拑瀵艰埅
/// 鏋舵瀯瀵归綈 Music 澶栨寕锛歎IKit 鍋氳彍鍗曪紝Metal 鍋氳儗鏅?鐗规晥缁樺埗
final class RootViewController: UIViewController {
    private let state = FangUIState()
    private var palette = Palette.light

    private let fxView = MetalFXView(frame: .zero, device: MetalContext.shared.device)
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let brandLabel = UILabel()
    private let brandSub = UILabel()
    private let themeSwitch = UISwitch()
    private let badgeLabel = UILabel()
    private let contentContainer = UIView()
    private let navBar = UIView()
    private var navButtons: [UIButton] = []
    private let navIndicator = UIView()
    private var pages: [UIView & PageBuildable] = []
    private var displayLink: CADisplayLink?
    private var lastTs: CFTimeInterval = 0

    private let tabTitles = ["Overview", "Controls", "Colors", "Effects"]
    private let tabSubs = [
        "Buttons, sliders & inputs",
        "Toggles, checks & radios",
        "Palette & color controls",
        "Background FX & motion"
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.bg

        fxView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fxView)
        NSLayoutConstraint.activate([
            fxView.topAnchor.constraint(equalTo: view.topAnchor),
            fxView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fxView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fxView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        cardView.layer.cornerRadius = 22
        cardView.layer.borderWidth = 1
        cardView.clipsToBounds = true
        view.addSubview(cardView)

        brandLabel.font = .systemFont(ofSize: 20, weight: .bold)
        brandLabel.text = "DsTool"
        brandSub.font = .systemFont(ofSize: 11, weight: .medium)
        brandSub.text = "UI THEME KIT"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.text = tabTitles[0]
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.text = tabSubs[0]
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.text = "  鈼?Ready  "
        badgeLabel.layer.cornerRadius = 15
        badgeLabel.clipsToBounds = true

        themeSwitch.addTarget(self, action: #selector(onTheme), for: .valueChanged)

        [brandLabel, brandSub, titleLabel, subtitleLabel, themeSwitch, badgeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(contentContainer)

        pages = [
            OverviewPage(state: state),
            ControlsPage(state: state),
            ColorsPage(state: state),
            EffectsPage(state: state)
        ]
        (pages[3] as? EffectsPage)?.onBurst = { [weak self] p in
            self?.fxView.emitBurst(at: p, count: 60)
        }
        pages.forEach { p in
            p.translatesAutoresizingMaskIntoConstraints = false
            p.isHidden = true
            contentContainer.addSubview(p)
        }
        pages[0].isHidden = false

        navBar.translatesAutoresizingMaskIntoConstraints = false
        navBar.layer.cornerRadius = 29
        navBar.clipsToBounds = false
        cardView.addSubview(navBar)

        navIndicator.backgroundColor = palette.accent
        navIndicator.layer.cornerRadius = 2.5
        navBar.addSubview(navIndicator)

        for (i, title) in tabTitles.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.tag = i
            b.addTarget(self, action: #selector(onTab(_:)), for: .touchUpInside)
            b.translatesAutoresizingMaskIntoConstraints = false
            navBar.addSubview(b)
            navButtons.append(b)
        }

        applyPalette(animated: false)
        startDisplayLink()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let inset: CGFloat = 24
        let cardW = min(view.bounds.width - 48, 900)
        let cardH = min(view.bounds.height - 48, 720)
        cardView.frame = CGRect(
            x: (view.bounds.width - cardW) / 2,
            y: (view.bounds.height - cardH) / 2,
            width: cardW, height: cardH
        )

        let pad: CGFloat = 20
        brandLabel.frame = CGRect(x: pad + 8, y: 18, width: 120, height: 24)
        brandSub.frame = CGRect(x: pad + 8, y: 42, width: 120, height: 14)
        titleLabel.sizeToFit()
        titleLabel.frame = CGRect(x: 160, y: 22, width: titleLabel.bounds.width, height: 28)
        subtitleLabel.frame = CGRect(x: titleLabel.frame.maxX + 12, y: 28,
                                     width: 220, height: 18)
        themeSwitch.frame = CGRect(x: cardView.bounds.width - 70, y: 22, width: 51, height: 31)
        badgeLabel.sizeToFit()
        badgeLabel.frame = CGRect(
            x: cardView.bounds.width - badgeLabel.bounds.width - 16,
            y: 20, width: badgeLabel.bounds.width, height: 30
        )
        badgeLabel.layer.cornerRadius = 15

        let navH: CGFloat = 58
        let navW = min(cardView.bounds.width - 40, 560)
        navBar.frame = CGRect(
            x: (cardView.bounds.width - navW) / 2,
            y: cardView.bounds.height - navH - 16,
            width: navW, height: navH
        )
        layoutNav()

        contentContainer.frame = CGRect(
            x: inset, y: 72,
            width: cardView.bounds.width - inset * 2,
            height: navBar.frame.minY - 72 - 12
        )
        pages.forEach { $0.frame = contentContainer.bounds }
        _ = inset
    }

    private func layoutNav() {
        let n = CGFloat(navButtons.count)
        let cellW = navBar.bounds.width / n
        for (i, b) in navButtons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * cellW, y: 0, width: cellW, height: navBar.bounds.height)
            b.setTitleColor(i == state.page ? palette.accent : palette.textDim, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: i == state.page ? .semibold : .regular)
        }
        updateIndicator(animated: false)
    }

    private func updateIndicator(animated: Bool) {
        let n = CGFloat(navButtons.count)
        let cellW = navBar.bounds.width / n
        let target = cellW * (state.navIndic + 0.5)
        let updates = {
            self.navIndicator.frame = CGRect(x: target - 12, y: 0, width: 24, height: 5)
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0,
                           usingSpringWithDamping: 0.85, initialSpringVelocity: 0.6,
                           options: [], animations: updates)
        } else {
            updates()
        }
    }

    private func startDisplayLink() {
        lastTs = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        var dt = CGFloat(now - lastTs)
        lastTs = now
        if dt > 0.1 { dt = 0.1 }

        // 涓婚杩囨浮锛堝搴?Approach锛?        let target: CGFloat = state.dark ? 1 : 0
        state.themeT = FangUIState.approach(state.themeT, target, dt: dt, speed: 8)

        // 瀵艰埅寮圭哀锛堝搴?Spring锛?        var vel = state.navVel
        state.navIndic = FangUIState.spring(state.navIndic, CGFloat(state.page), vel: &vel, dt: dt)
        state.navVel = vel
        updateIndicator(animated: false)

        // 鏍囬娣″叆娣″嚭
        if state.titlePage != state.page {
            state.titleFade -= dt / 0.12
            if state.titleFade <= 0 {
                state.titleFade = 0
                state.titlePage = state.page
                titleLabel.text = tabTitles[state.titlePage]
                subtitleLabel.text = tabSubs[state.titlePage]
            }
        } else if state.titleFade < 1 {
            state.titleFade = min(1, state.titleFade + dt / 0.16)
        }
        titleLabel.alpha = state.titleFade
        subtitleLabel.alpha = state.titleFade

        // 涓婚鑹茶繛缁埛
        let p = Palette.lerp(state.themeT)
        palette = p
        view.backgroundColor = p.bg
        cardView.backgroundColor = p.card
        cardView.layer.borderColor = p.cardBorder.cgColor
        navBar.backgroundColor = p.navBar
        navIndicator.backgroundColor = p.accent
        fxView.accent = p.accent
        fxView.dotColor = p.dotGrid
        fxView.showBeams = state.showBeams
        fxView.showDots = state.showDots
        brandLabel.textColor = p.text
        brandSub.textColor = p.textDim
        titleLabel.textColor = p.text
        subtitleLabel.textColor = p.textDim
        badgeLabel.backgroundColor = p.accentSoft
        badgeLabel.textColor = p.text
        navButtons.enumerated().forEach { i, b in
            b.setTitleColor(i == state.page ? p.accent : p.textDim, for: .normal)
        }
        (pages[state.page] as? PageBuildable)?.rebuild(palette: p)
    }

    private func applyPalette(animated: Bool) {
        let p = Palette.lerp(state.themeT)
        palette = p
        view.backgroundColor = p.bg
        cardView.backgroundColor = p.card
        cardView.layer.borderColor = p.cardBorder.cgColor
        navBar.backgroundColor = p.navBar.withAlphaComponent(0.7)
        navBar.layer.shadowColor = UIColor.black.cgColor
        navBar.layer.shadowOpacity = 0.12
        navBar.layer.shadowRadius = 12
        navBar.layer.shadowOffset = CGSize(width: 0, height: 4)
        brandLabel.textColor = p.text
        brandSub.textColor = p.textDim
        titleLabel.textColor = p.text
        subtitleLabel.textColor = p.textDim
        badgeLabel.backgroundColor = p.accentSoft
        badgeLabel.textColor = p.text
        pages.forEach { $0.rebuild(palette: p) }
        _ = animated
    }

    @objc private func onTheme() {
        state.dark.toggle()
    }

    @objc private func onTab(_ sender: UIButton) {
        guard sender.tag != state.page else { return }
        state.page = sender.tag
        pages.forEach { $0.isHidden = ($0 !== pages[sender.tag]) }
        pages[sender.tag].rebuild(palette: palette)
        UIView.transition(with: contentContainer, duration: 0.2,
                          options: .transitionCrossDissolve, animations: nil)
    }

    deinit {
        displayLink?.invalidate()
    }
}

