import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Music")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(4)
                    .foregroundColor(Color(.tertiaryLabel))

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isPoweredOn ? Color.green : Color(.tertiaryLabel))
                        .frame(width: 6, height: 6)
                    Text(state.isPoweredOn ? "已激活" : "未运行")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(state.isPoweredOn ? Color.green : Color(.secondaryLabel))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(state.isPoweredOn ? Color.green.opacity(0.12) : Color(.secondarySystemFill))
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 28)

            PowerRing(isOn: state.isPoweredOn)
                .frame(width: 176, height: 176)
                .padding(.bottom, 24)

            Text("控制台")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .kerning(-0.5)
                .padding(.bottom, 6)

            Text(state.isPoweredOn ? "服务状态正常" : "服务已关闭")
                .font(.system(size: 14))
                .foregroundColor(Color(.secondaryLabel))
                .padding(.bottom, 28)

            HStack(spacing: 10) {
                PowerButton(title: "开启", style: .on, active: state.isPoweredOn) {
                    state.setPower(true)
                }
                PowerButton(title: "关闭", style: .off, active: !state.isPoweredOn) {
                    state.setPower(false)
                }
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 24)

            HStack(spacing: 8) {
                MetaCell(value: state.isPoweredOn ? "On" : "Off", label: "状态")
                MetaCell(value: "Premium", label: "权限")
                MetaCell(value: elapsedText, label: "本次")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.green.opacity(state.isPoweredOn ? 0.05 : 0),
                    Color(.systemGroupedBackground)
                ]),
                startPoint: .top,
                endPoint: .center
            )
            .edgesIgnoringSafeArea(.all)
        )
    }

    private var elapsedText: String {
        guard let start = state.sessionStart else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }
}

private struct PowerRing: View {
    var isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 6)

            Circle()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(
                    isOn ? Color.green : Color(.tertiaryLabel),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: isOn ? Color.green.opacity(0.35) : .clear, radius: 8)
                .animation(.easeInOut(duration: 0.55), value: isOn)

            VStack(spacing: 4) {
                Text(isOn ? "运行中" : "已停止")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isOn ? Color.primary : Color(.tertiaryLabel))
                Text(isOn ? "On" : "Off")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabel))
            }
            .padding(26)
            .background(
                Circle()
                    .fill(isOn ? Color(.systemBackground) : Color(.secondarySystemBackground))
                    .overlay(
                        Circle()
                            .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(
                        color: Color.black.opacity(isOn ? 0.06 : 0),
                        radius: 16,
                        y: 8
                    )
                    .overlay(
                        Group {
                            if isOn {
                                Circle()
                                    .stroke(Color.green.opacity(0.08), lineWidth: 6)
                            }
                        }
                    )
            )
        }
    }
}

private struct PowerButton: View {
    enum Style { case on, off }
    var title: String
    var style: Style
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(bg)
                .foregroundColor(active ? Color.white : Color(.secondaryLabel))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(active ? Color.clear : Color(.separator), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(
                    color: shadowColor,
                    radius: 12,
                    y: 6
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var bg: Color {
        guard active else { return Color(.systemBackground) }
        return style == .on ? Color.green : Color(.label)
    }

    private var shadowColor: Color {
        guard active else { return .clear }
        return style == .on ? Color.green.opacity(0.3) : Color.black.opacity(0.18)
    }
}

private struct MetaCell: View {
    var value: String
    var label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
                )
        )
    }
}

struct ControlView_Previews: PreviewProvider {
    static var previews: some View {
        ControlView()
            .environmentObject(AppState())
    }
}
