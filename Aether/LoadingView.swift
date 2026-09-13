import SwiftUI

/// Thinking Nine rose-curve loading, 0 → 100%. iOS 13+.
struct LoadingView: View {
    var onFinished: () -> Void

    @State private var progress: Double = 0
    @State private var detailScale: Double = 0.6
    @State private var rotation: Angle = .zero
    @State private var finished = false

    private let loadDuration: Double = 2.8
    private let rotationDuration: Double = 28
    private let pulseDuration: Double = 3.8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Title pinned to top, centered horizontally
                VStack {
                    Text("Music")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(6)
                        .foregroundColor(Color(.tertiaryLabel))
                        .padding(.top, max(24, geo.safeAreaInsets.top + 12))
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width)

                // Rose curve true center (iPhone + iPad)
                roseDial
                    .frame(width: roseSize(for: geo.size), height: roseSize(for: geo.size))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear(perform: start)
    }

    private func roseSize(for size: CGSize) -> CGFloat {
        let side = min(size.width, size.height)
        // 260pt on phone-sized; scale down slightly on narrow/short layouts
        return min(260, side * 0.58)
    }

    private var roseDial: some View {
        ZStack {
            RoseCurveTrack()
                .stroke(
                    Color.primary.opacity(0.06),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )

            RoseCurve(progress: progress, detailScale: detailScale)
                .stroke(
                    finished ? Color.green : Color.primary,
                    style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                )
                .opacity(0.08 + progress * 0.1)
                .rotationEffect(rotation)
                .shadow(
                    color: finished ? Color.green.opacity(0.35) : .clear,
                    radius: 12
                )

            VStack(spacing: 6) {
                Text("\(Int((progress * 100).rounded()))")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundColor(finished ? Color.green : Color.primary)
                    .scaleEffect(finished ? 1.06 : 1)

                Text("Loading")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2)
                    .foregroundColor(Color(.tertiaryLabel))
                    .opacity(finished ? 0 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func start() {
        let start = Date()

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            let t = Date().timeIntervalSince(start)
            let p = min(t / loadDuration, 1)
            let eased = 1 - pow(1 - p, 2.4)

            DispatchQueue.main.async {
                progress = eased
                detailScale = 0.52 + ((sin(t / pulseDuration * .pi * 2 + 0.55) + 1) / 2) * 0.48
                rotation = .degrees(-(t.truncatingRemainder(dividingBy: rotationDuration) / rotationDuration) * 360)
            }

            if p >= 1 {
                timer.invalidate()
                DispatchQueue.main.async {
                    finished = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                        onFinished()
                    }
                }
            }
        }
    }
}

private func rosePoint(t: Double, detailScale: Double) -> CGPoint {
    let petals = 9.0
    let x = 7 * cos(t) - 3 * detailScale * cos(petals * t)
    let y = 7 * sin(t) - 3 * detailScale * sin(petals * t)
    return CGPoint(x: 50 + x * 3.9, y: 50 + y * 3.9)
}

struct RoseCurve: Shape {
    var progress: Double
    var detailScale: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, detailScale) }
        set {
            progress = newValue.first
            detailScale = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { p in
            let steps = 480
            for i in 0...steps {
                let t = Double(i) / Double(steps) * .pi * 2
                let pt = rosePoint(t: t, detailScale: detailScale)
                let x = rect.minX + pt.x / 100 * rect.width
                let y = rect.minY + pt.y / 100 * rect.height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

struct RoseCurveTrack: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let steps = 480
            let s = 0.78
            for i in 0...steps {
                let t = Double(i) / Double(steps) * .pi * 2
                let pt = rosePoint(t: t, detailScale: s)
                let x = rect.minX + pt.x / 100 * rect.width
                let y = rect.minY + pt.y / 100 * rect.height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView {}
    }
}
