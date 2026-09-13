import UIKit

extension UIColor {
    /// Allows `bg: .hex(0xEAE8E1)` in UIColor-typed slots.
    static func hex(_ rgb: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: a
        )
    }
}

/// 明/暗双主题配色，对应原 theme.cpp 的 Palette + Lerp
struct Palette {
    var bg: UIColor
    var card: UIColor
    var cardBorder: UIColor
    var dotGrid: UIColor
    var text: UIColor
    var textDim: UIColor
    var accent: UIColor
    var accentHover: UIColor
    var accentSoft: UIColor
    var track: UIColor
    var danger: UIColor
    var dangerSoft: UIColor
    var success: UIColor
    var navBar: UIColor
    var shadow: UIColor

    static func hex(_ rgb: UInt32, _ a: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: a
        )
    }

    static let light = Palette(
        bg: .hex(0xEAE8E1),
        card: .hex(0xFBFAF7),
        cardBorder: .hex(0x000000, 0x07),
        dotGrid: .hex(0x1A1A2E, 0x16),
        text: .hex(0x1B1B22),
        textDim: .hex(0x1B1B22, 0.5),
        accent: .hex(0x6C63FF),
        accentHover: .hex(0x5850E6),
        accentSoft: .hex(0x6C63FF, 0.13),
        track: .hex(0x6C63FF, 0.2),
        danger: .hex(0xE53E3E),
        dangerSoft: .hex(0xE53E3E, 0.09),
        success: .hex(0x2EBD6B),
        navBar: .hex(0xFFFFFF, 0.62),
        shadow: .hex(0x1A1A2E, 0.13)
    )

    static let dark = Palette(
        bg: .hex(0x0A0A0C),
        card: .hex(0x15151B),
        cardBorder: .hex(0xFFFFFF, 0x08),
        dotGrid: .hex(0xFFFFFF, 0x14),
        text: .hex(0xF4F4F6),
        textDim: .hex(0xF4F4F6, 0.45),
        accent: .hex(0x7C74FF),
        accentHover: .hex(0x8F88FF),
        accentSoft: .hex(0x7C74FF, 0.18),
        track: .hex(0x7C74FF, 0.2),
        danger: .hex(0xFF5A5A),
        dangerSoft: .hex(0xFF5A5A, 0.12),
        success: .hex(0x3AD67E),
        navBar: .hex(0x2A2A38, 0.7),
        shadow: .hex(0x000000, 0.4)
    )

    /// t: 0 浅色 → 1 深色
    static func lerp(_ t: CGFloat) -> Palette {
        let a = light, b = dark
        func mix(_ x: UIColor, _ y: UIColor) -> UIColor {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * t,
                green: g1 + (g2 - g1) * t,
                blue: b1 + (b2 - b1) * t,
                alpha: a1 + (a2 - a1) * t
            )
        }
        return Palette(
            bg: mix(a.bg, b.bg),
            card: mix(a.card, b.card),
            cardBorder: mix(a.cardBorder, b.cardBorder),
            dotGrid: mix(a.dotGrid, b.dotGrid),
            text: mix(a.text, b.text),
            textDim: mix(a.textDim, b.textDim),
            accent: mix(a.accent, b.accent),
            accentHover: mix(a.accentHover, b.accentHover),
            accentSoft: mix(a.accentSoft, b.accentSoft),
            track: mix(a.track, b.track),
            danger: mix(a.danger, b.danger),
            dangerSoft: mix(a.dangerSoft, b.dangerSoft),
            success: mix(a.success, b.success),
            navBar: mix(a.navBar, b.navBar),
            shadow: mix(a.shadow, b.shadow)
        )
    }
}

/// 全局界面状态，对应原 UI::FangUIState
final class FangUIState {
    var dark = false
    var themeT: CGFloat = 0
    var page = 0
    var navIndic: CGFloat = 0
    var navVel: CGFloat = 0
    var titlePage = 0
    var titleFade: CGFloat = 1
    var caesarScramble: CGFloat = 0
    var caesarTimer: CGFloat = 0

    var fpsLimit: Float = 144
    var langIdx = 0
    var toggles = [true, true, true, false, true, false]
    var volume: Float = 0.7
    var quality = 2
    var textBuf = "Caesar UI Kit"
    var rgb: (Float, Float, Float) = (0.42, 0.39, 1.0)
    var radio = 0

    var showBeams = true
    var showDots = true

    static func approach(_ cur: CGFloat, _ target: CGFloat, dt: CGFloat, speed: CGFloat = 10) -> CGFloat {
        let t = 1 - exp(-speed * dt)
        return cur + (target - cur) * t
    }

    static func spring(_ cur: CGFloat, _ target: CGFloat, vel: inout CGFloat, dt: CGFloat,
                       stiff: CGFloat = 220, damp: CGFloat = 22) -> CGFloat {
        let force = (target - cur) * stiff - vel * damp
        vel += force * dt
        return cur + vel * dt
    }
}

enum FangTheme {
    static var current = FangUIState().themeT
    static var state = FangUIState()
    static func palette() -> Palette { .lerp(state.themeT) }
}
