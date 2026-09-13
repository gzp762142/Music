import SwiftUI
import UIKit

/// Card-key validation stub. iOS 13+.
enum CardKeyService {
    static let demoKey = "AETHER-2026"

    struct Result {
        let ok: Bool
        let message: String?
    }

    static func validate(_ key: String, completion: @escaping (Result) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            let v = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if v == demoKey || v.count >= 8 {
                completion(Result(ok: true, message: nil))
            } else {
                completion(Result(ok: false, message: "卡密无效"))
            }
        }
    }
}

private struct CardKeyTextField: UIViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void
    var onCommit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.borderStyle = .none
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.keyboardType = .asciiCapable
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: CardKeyTextField

        init(_ parent: CardKeyTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            parent.text = value
            parent.onTextChange(value)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit()
            return true
        }
    }
}

private struct ActivityIndicatorView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.color = .white
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {}
}

struct UnlockHostView: View {
    var onUnlocked: () -> Void

    @State private var showSheet = false
    @State private var key = ""
    @State private var hint = "输入卡密后继续"
    @State private var hintColor: Color = Color(.tertiaryLabel)
    @State private var shake = false
    @State private var success = false
    @State private var busy = false

    var body: some View {
        ZStack {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(Color(.tertiaryLabel))
                    )

                Text("需要验证")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(.secondaryLabel))
            }

            Color.black.opacity(showSheet ? 0.32 : 0)
                .edgesIgnoringSafeArea(.all)
                .animation(.easeInOut(duration: 0.35))
        }
        .sheet(isPresented: $showSheet) {
            self.keySheet
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showSheet = true
            }
        }
    }

    private var keySheet: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            CardKeyTextField(
                text: $key,
                onTextChange: { _ in
                    hint = "输入卡密后继续"
                    hintColor = Color(.tertiaryLabel)
                    success = false
                },
                onCommit: submit
            )
            .frame(height: 48)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .offset(x: shake ? -6 : 0)

            Button(action: submit) {
                ZStack {
                    if busy {
                        ActivityIndicatorView()
                    } else {
                        Text("继续")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(busy ? Color.green : Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            .opacity(key.trimmingCharacters(in: .whitespaces).isEmpty || busy ? 0.3 : 1)

            Text(hint)
                .font(.system(size: 12))
                .foregroundColor(hintColor)
                .frame(height: 16)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(minHeight: 280)
        .background(Color(.systemBackground))
    }

    private var borderColor: Color {
        if success { return .green }
        if shake { return .red }
        return Color(.separator)
    }

    private func submit() {
        let v = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !busy else { return }
        busy = true
        hint = "请稍候"
        hintColor = Color(.tertiaryLabel)

        CardKeyService.validate(v) { result in
            busy = false
            if result.ok {
                success = true
                hint = "验证成功"
                hintColor = .green
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onUnlocked()
                    }
                }
            } else {
                withAnimation(.default) {
                    shake = true
                }
                hint = result.message ?? "卡密无效"
                hintColor = .red
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.default) {
                        shake = false
                    }
                }
            }
        }
    }
}

struct UnlockHostView_Previews: PreviewProvider {
    static var previews: some View {
        UnlockHostView {}
    }
}
