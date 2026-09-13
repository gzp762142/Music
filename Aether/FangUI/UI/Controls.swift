import UIKit

/// 对应原 ToggleSwitch：药丸轨道 + 圆钮 + 缓动
final class ToggleSwitch: UIControl {
    var isOn: Bool {
        didSet { setNeedsLayout(); animateKnob() }
    }
    private let track = UIView()
    private let knob = UIView()
    private var progress: CGFloat

    init(on: Bool) {
        self.isOn = on
        self.progress = on ? 1 : 0
        super.init(frame: CGRect(x: 0, y: 0, width: 46, height: 26))
        setup()
    }

    required init?(coder: NSCoder) {
        self.isOn = false
        self.progress = 0
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        track.layer.cornerRadius = 13
        knob.layer.cornerRadius = 10
        knob.backgroundColor = .white
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOpacity = 0.18
        knob.layer.shadowRadius = 2
        knob.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(track)
        addSubview(knob)
        addTarget(self, action: #selector(tap), for: .touchUpInside)
        apply(progress: progress)
    }

    func apply(palette: Palette, t: CGFloat) {
        track.backgroundColor = lerp(palette.track, palette.accent, t)
        setNeedsLayout()
    }

    private func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }

    @objc private func tap() {
        isOn.toggle()
        sendActions(for: .valueChanged)
    }

    private func animateKnob() {
        progress = isOn ? 1 : 0
        apply(progress: progress)
    }

    private func apply(progress: CGFloat) {
        track.frame = bounds
        let r = bounds.height * 0.5
        let x = r - 3 + (bounds.width - bounds.height) * progress
        knob.frame = CGRect(x: x, y: 3, width: bounds.height - 6, height: bounds.height - 6)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply(progress: progress)
    }

    /// 让 stack 里的行高稳定（无固有尺寸的控件会被压成 0 高）。
    override var intrinsicContentSize: CGSize { CGSize(width: 46, height: 26) }
}

/// 对应 CheckChip：圆角勾选块
final class CheckChip: UIControl {
    var isOn: Bool { didSet { setNeedsDisplay() } }
    private let titleLabel = UILabel()

    init(title: String, on: Bool) {
        self.isOn = on
        super.init(frame: CGRect(x: 0, y: 0, width: 40, height: 26))
        layer.cornerRadius = 9
        addTarget(self, action: #selector(tap), for: .touchUpInside)
        _ = title
    }

    required init?(coder: NSCoder) {
        self.isOn = false
        super.init(coder: coder)
        layer.cornerRadius = 9
    }

    @objc private func tap() {
        isOn.toggle()
        UIView.animate(withDuration: 0.2, animations: {
            self.transform = CGAffineTransform(scaleX: 0.05, y: 1)
        }, completion: { _ in
            self.setNeedsDisplay()
            UIView.animate(withDuration: 0.12) {
                self.transform = .identity
            }
        })
        sendActions(for: .valueChanged)
    }

    func apply(palette: Palette) {
        backgroundColor = isOn ? palette.accent : palette.track
        setNeedsDisplay()
    }

    /// 行内固定尺寸，避免被 stack 压成 0 高。
    override var intrinsicContentSize: CGSize { CGSize(width: 40, height: 26) }

    override func draw(_ rect: CGRect) {
        let c = UIGraphicsGetCurrentContext()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        if isOn {
            UIColor.white.setStroke()
            c?.setLineWidth(2)
            c?.move(to: CGPoint(x: mid.x - 5, y: mid.y + 0.5))
            c?.addLine(to: CGPoint(x: mid.x - 1.5, y: mid.y + 4))
            c?.addLine(to: CGPoint(x: mid.x + 5.5, y: mid.y - 4))
            c?.strokePath()
        } else {
            UIColor.gray.withAlphaComponent(0.7).setStroke()
            c?.setLineWidth(2)
            c?.move(to: CGPoint(x: mid.x - 5, y: mid.y))
            c?.addLine(to: CGPoint(x: mid.x + 5, y: mid.y))
            c?.strokePath()
        }
    }
}

/// 对应 FancySlider：细轨道 + 白钮 + 跟随气泡
final class FancySlider: UIControl {
    var value: Float
    var minValue: Float
    var maxValue: Float
    var format: String
    var dispScale: Float
    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let knob = UIView()
    private let bubble = UILabel()

    init(value: Float, min: Float, max: Float, format: String, scale: Float = 1) {
        self.value = value
        self.minValue = min
        self.maxValue = max
        self.format = format
        self.dispScale = scale
        super.init(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        setup()
    }

    required init?(coder: NSCoder) {
        self.value = 0
        self.minValue = 0
        self.maxValue = 1
        self.format = "%.0f"
        self.dispScale = 1
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = 3
        trackLayer.lineCap = .round
        fillLayer.fillColor = UIColor.clear.cgColor
        fillLayer.lineWidth = 3
        fillLayer.lineCap = .round
        layer.addSublayer(trackLayer)
        layer.addSublayer(fillLayer)

        knob.backgroundColor = .white
        knob.layer.cornerRadius = 9
        knob.layer.borderWidth = 1.5
        addSubview(knob)

        bubble.font = .systemFont(ofSize: 12, weight: .medium)
        bubble.textAlignment = .center
        bubble.layer.cornerRadius = 12
        bubble.clipsToBounds = true
        addSubview(bubble)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        addGestureRecognizer(tap)
    }

    func apply(palette: Palette) {
        trackLayer.strokeColor = palette.track.cgColor
        fillLayer.strokeColor = palette.accent.cgColor
        knob.layer.borderColor = palette.accent.cgColor
        bubble.backgroundColor = palette.accentSoft
        bubble.textColor = palette.accent
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let x = g.location(in: self).x
        update(fromX: x)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        update(fromX: g.location(in: self).x)
    }

    private func update(fromX x: CGFloat) {
        let x0: CGFloat = 10, x1 = bounds.width - 10
        var t = (x - x0) / max(x1 - x0, 1)
        t = min(1, max(0, t))
        value = minValue + Float(t) * (maxValue - minValue)
        setNeedsLayout()
        sendActions(for: .valueChanged)
    }

    /// 滑条需要固定高度：气泡 24 + 间隙 + 轨道。
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 54)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let trackY = bounds.height - 10
        let x0: CGFloat = 10, x1 = bounds.width - 10
        let t = CGFloat((value - minValue) / max(maxValue - minValue, 0.0001))
        let knobX = x0 + t * (x1 - x0)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: x0, y: trackY))
        path.addLine(to: CGPoint(x: x1, y: trackY))
        trackLayer.path = path.cgPath

        let fill = UIBezierPath()
        fill.move(to: CGPoint(x: x0, y: trackY))
        fill.addLine(to: CGPoint(x: knobX, y: trackY))
        fillLayer.path = fill.cgPath

        knob.frame = CGRect(x: knobX - 9, y: trackY - 9, width: 18, height: 18)

        bubble.text = String(format: format, value * dispScale)
        bubble.sizeToFit()
        let bw = bubble.bounds.width + 18, bh: CGFloat = 24
        var bx = knobX - bw * 0.5
        bx = min(max(bx, 0), bounds.width - bw)
        bubble.frame = CGRect(x: bx, y: trackY - 16 - bh, width: bw, height: bh)
        bubble.layer.cornerRadius = bh * 0.5
    }
}

/// 一行：左标签 + 右控件
final class RowView: UIView {
    let label = UILabel()
    let control: UIView

    init(title: String, control: UIView) {
        self.control = control
        super.init(frame: .zero)
        label.text = title
        label.font = .systemFont(ofSize: 15)
        addSubview(label)
        addSubview(control)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(palette: Palette) {
        label.textColor = palette.text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        let h = min(label.bounds.height, bounds.height)
        label.frame = CGRect(x: 0, y: (bounds.height - h) / 2,
                             width: min(label.bounds.width, max(bounds.width - 80, 0)),
                             height: h)

        let intrinsic = control.intrinsicContentSize
        let cw = intrinsic.width != UIView.noIntrinsicMetric
            ? intrinsic.width : max(control.bounds.width, 46)
        let ch = intrinsic.height != UIView.noIntrinsicMetric
            ? intrinsic.height : max(control.bounds.height, 26)
        control.frame = CGRect(x: bounds.width - cw, y: (bounds.height - ch) / 2,
                               width: cw, height: ch)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }
}

/// 段落标题
final class SectionLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 12, weight: .semibold)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
}
