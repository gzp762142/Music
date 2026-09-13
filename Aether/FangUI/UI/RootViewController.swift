import UIKit

/// 根控制器：Metal 特效层 + 卡片 + 标题栏 + 分页内容 + 底部玻璃导航
/// 架构对齐 Music 外挂：UIKit 做菜单，Metal 做背景/特效绘制
final class RootViewController: UIViewController {
    /// 面板底色回传：窗口层跟着换底，保证整块画面不透明。
    var onSurfaceColorChange: ((UIColor) -> Void)?
    /// 关闭（收起面板）回传。
    var onRequestClose: (() -> Void)?

    private let state = FangUIState()
    private var palette = Palette.light
    private var lastSurface: UIColor?

    private let fxView = MetalFXView(frame: .zero, device: MetalContext.shared.device)
    private let cardView = UIView()
    private let closeBtn = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let brandLabel = UILabel()
    private let brandSub = UILabel()
    private let themeSwitch = UISwitch()
    private let badgeLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentContainer = UIView()
    private let navBar = UIView()
    private var navButtons: [UIButton] = []
    private let navIndicator = UIView()
    private var pages: [UIView & PageSizing] = []
    private var displayLink: CADisplayLink?
    private var lastTs: CFTimeInterval = 0

    private let tabTitles = ["Overview", "Controls", "Colors", "Effects"]
    private let tabSubs = [
        "Buttons, sliders & inputs",
        "Toggles, checks & radios",
        "Palette & color controls",
        "Background FX & motion"
    ]
    /// 底栏图标（SF Symbols，iOS 13 起可用）。
    private let navIcons = ["square.grid.2x2", "slider.horizontal.3",
                            "paintpalette.fill", "sparkles"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = palette.bg
        view.isOpaque = true

        // 面板铺满整个窗口且自身不透明：画面上只有 FangUI，没有桌面/背景图。
        cardView.clipsToBounds = true
        cardView.layer.cornerRadius = 0
        view.addSubview(cardView)

        // Metal 点阵 + 光束画在面板内部，作为 FangUI 自己的背景。
        fxView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(fxView)
        NSLayoutConstraint.activate([
            fxView.topAnchor.constraint(equalTo: cardView.topAnchor),
            fxView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            fxView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            fxView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor)
        ])

        closeBtn.setTitle("✕", for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeBtn.addTarget(self, action: #selector(onCloseTap), for: .touchUpInside)
        cardView.addSubview(closeBtn)

        brandLabel.font = .systemFont(ofSize: 20, weight: .bold)
        brandLabel.text = "DsTool"
        brandSub.font = .systemFont(ofSize: 11, weight: .medium)
        brandSub.text = "UI THEME KIT"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.text = tabTitles[0]
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.text = tabSubs[0]
        // 顶栏文本一律单行：宽度异常时截断，不要逐字竖排
        [brandLabel, brandSub, titleLabel, subtitleLabel, badgeLabel].forEach {
            $0.numberOfLines = 1
            $0.lineBreakMode = .byTruncatingTail
        }
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.text = "  ● Ready  "
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 15
        badgeLabel.clipsToBounds = true

        themeSwitch.addTarget(self, action: #selector(onTheme), for: .valueChanged)

        [brandLabel, brandSub, titleLabel, subtitleLabel, themeSwitch, badgeLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }

        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.clipsToBounds = true
        cardView.addSubview(scrollView)

        // 内容容器：宽度锁在滚动视口上，高度由最"高"的页面内容决定。
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

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
            p.installContentStackConstraints()
            NSLayoutConstraint.activate([
                p.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                p.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                p.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                p.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
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
            b.titleLabel?.font = .systemFont(ofSize: 11, weight: .regular)
            b.titleEdgeInsets = UIEdgeInsets(top: 26, left: 0, bottom: 0, right: 0)
            b.tag = i
            b.addTarget(self, action: #selector(onTab(_:)), for: .touchUpInside)
            b.translatesAutoresizingMaskIntoConstraints = false

            let icon = UIImageView(image: UIImage(systemName: navIcons[i]))
            icon.contentMode = .scaleAspectFit
            icon.isUserInteractionEnabled = false
            icon.tag = 900 + i
            b.addSubview(icon)

            navBar.addSubview(b)
            navButtons.append(b)
        }

        applyPalette(animated: false)
        startDisplayLink()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // 面板 ＝ 整个窗口。
        cardView.frame = view.bounds

        let W = cardView.bounds.width
        let H = cardView.bounds.height
        let top = view.safeAreaInsets.top
        let bottom = view.safeAreaInsets.bottom
        let pad: CGFloat = 20
        let wide = W >= 620
        let headerH: CGFloat = wide ? 72 : 104

        // 右上角自右向左：关闭 → Ready 徽章 → 主题开关
        let closeSide: CGFloat = 30
        closeBtn.frame = CGRect(x: W - pad - closeSide,
                                y: top + (wide ? 18 : 14),
                                width: closeSide, height: closeSide)
        closeBtn.layer.cornerRadius = closeSide / 2
        themeSwitch.frame = CGRect(x: closeBtn.frame.minX - 12 - 51,
                                   y: closeBtn.frame.midY - 15.5,
                                   width: 51, height: 31)

        badgeLabel.text = (badgeLabel.text ?? "").trimmingCharacters(in: .whitespaces)
        badgeLabel.sizeToFit()
        let badgeW = min(max(badgeLabel.bounds.width + 22, 86), W * 0.45)
        let badgeH: CGFloat = 28
        badgeLabel.layer.cornerRadius = badgeH / 2

        titleLabel.sizeToFit()

        if wide {
            // 单行 header：品牌 | 标题 + 副标题 … 开关 · 徽章 · 关闭
            brandLabel.frame = CGRect(x: pad + 8, y: top + 18, width: 160, height: 24)
            brandSub.frame = CGRect(x: pad + 8, y: top + 42, width: 160, height: 14)
            brandSub.isHidden = false
            subtitleLabel.isHidden = false

            titleLabel.frame = CGRect(x: 176, y: top + 20,
                                      width: titleLabel.bounds.width, height: 30)
            let subX = titleLabel.frame.maxX + 12
            subtitleLabel.frame = CGRect(
                x: subX, y: top + 27,
                width: max(0, themeSwitch.frame.minX - 16 - subX), height: 18
            )
            badgeLabel.frame = CGRect(x: themeSwitch.frame.minX - 12 - badgeW,
                                      y: top + 21, width: badgeW, height: badgeH)
        } else {
            // 窄屏两行 header：上行品牌 + 开关/关闭，下行标题 + 徽章
            brandLabel.frame = CGRect(x: pad + 8, y: top + 14, width: 160, height: 26)
            brandSub.isHidden = true
            subtitleLabel.isHidden = true

            titleLabel.frame = CGRect(x: pad + 8, y: top + 48,
                                      width: min(titleLabel.bounds.width,
                                                 W - pad * 2 - badgeW - 12),
                                      height: 30)
            badgeLabel.frame = CGRect(x: W - pad - badgeW, y: top + 50,
                                      width: badgeW, height: badgeH)
        }

        // 底部玻璃导航
        let navH: CGFloat = 58
        let navW = min(W - 40, 560)
        navBar.frame = CGRect(x: (W - navW) / 2,
                              y: H - navH - 16 - bottom,
                              width: navW, height: navH)
        layoutNav()

        // 内容区：宽度由约束链锁定，高度由页面内容撑开，滚动交给 UIScrollView。
        let contentTop = top + headerH
        let contentBottom = navBar.frame.minY - 12
        scrollView.frame = CGRect(x: pad, y: contentTop,
                                  width: W - pad * 2,
                                  height: max(40, contentBottom - contentTop))
    }

    private func layoutNav() {
        let n = CGFloat(navButtons.count)
        let cellW = navBar.bounds.width / n
        for (i, b) in navButtons.enumerated() {
            b.frame = CGRect(x: CGFloat(i) * cellW, y: 0, width: cellW, height: navBar.bounds.height)
            b.setTitleColor(i == state.page ? palette.accent : palette.textDim, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 11, weight: i == state.page ? .semibold : .regular)
            b.titleEdgeInsets = UIEdgeInsets(top: 26, left: 0, bottom: 0, right: 0)
            if let icon = b.viewWithTag(900 + i) {
                let side: CGFloat = 20
                icon.frame = CGRect(x: (b.bounds.width - side) / 2, y: 8,
                                    width: side, height: side)
                (icon as? UIImageView)?.tintColor =
                    i == state.page ? palette.accent : palette.textDim
            }
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

        // 主题过渡（对应 Approach）
        let target: CGFloat = state.dark ? 1 : 0
        state.themeT = FangUIState.approach(state.themeT, target, dt: dt, speed: 8)

        // 导航弹簧（对应 Spring）
        var vel = state.navVel
        state.navIndic = FangUIState.spring(state.navIndic, CGFloat(state.page), vel: &vel, dt: dt)
        state.navVel = vel
        updateIndicator(animated: false)

        // 标题淡入淡出
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

        // 主题色连续刷
        let p = Palette.lerp(state.themeT)
        palette = p
        view.backgroundColor = p.bg
        cardView.backgroundColor = p.bg
        navBar.backgroundColor = p.navBar
        navIndicator.backgroundColor = p.accent
        closeBtn.backgroundColor = p.accentSoft
        closeBtn.setTitleColor(p.text, for: .normal)
        if lastSurface?.isEqual(p.bg) != true {
            lastSurface = p.bg
            onSurfaceColorChange?(p.bg)
        }
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
            (b.viewWithTag(900 + i) as? UIImageView)?.tintColor =
                i == state.page ? p.accent : p.textDim
        }
        (pages[state.page] as? PageBuildable)?.rebuild(palette: p)
    }

    private func applyPalette(animated: Bool) {
        let p = Palette.lerp(state.themeT)
        palette = p
        view.backgroundColor = p.bg
        cardView.backgroundColor = p.bg
        navBar.backgroundColor = p.navBar
        closeBtn.backgroundColor = p.accentSoft
        closeBtn.setTitleColor(p.text, for: .normal)
        if lastSurface?.isEqual(p.bg) != true {
            lastSurface = p.bg
            onSurfaceColorChange?(p.bg)
        }
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
        scrollView.setContentOffset(.zero, animated: false)
        view.setNeedsLayout()
        UIView.transition(with: contentContainer, duration: 0.2,
                          options: .transitionCrossDissolve, animations: nil)
    }

    @objc private func onCloseTap() {
        onRequestClose?()
    }

    deinit {
        displayLink?.invalidate()
    }
}
