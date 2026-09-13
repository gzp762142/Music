import SwiftUI

enum AppPhase {
    case loading
    case unlock
    case control
}

final class AppState: ObservableObject {
    @Published var phase: AppPhase = .loading
    @Published var isPoweredOn = true
    @Published var sessionStart: Date?
    @Published var cardMessage: String?

    func completeLoading() {
        withAnimation(.easeInOut(duration: 0.45)) {
            phase = .unlock
        }
    }

    func enterControl() {
        sessionStart = Date()
        isPoweredOn = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            phase = .control
        }
    }

    func setPower(_ on: Bool) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPoweredOn = on
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct RootView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)

            if state.phase == .loading {
                LoadingView {
                    state.completeLoading()
                }
                .transition(.opacity)
            } else if state.phase == .unlock {
                UnlockHostView {
                    state.enterControl()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                ControlView()
                    .environmentObject(state)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .preferredColorScheme(.light)
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(state: AppState())
    }
}
