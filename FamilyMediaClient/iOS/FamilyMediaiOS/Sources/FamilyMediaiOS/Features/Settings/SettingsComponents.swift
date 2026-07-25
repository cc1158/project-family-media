import FamilyMediaCore
import SwiftUI
import UIKit

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .frame(width: 42, height: 42)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                content()
            }
        }
    }
}
struct SettingsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImage: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        SettingsInputShell(title: title, systemImage: systemImage) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除\(title)")
                }
            }
        }
    }
}
struct SettingsSecureField: View {
    @State private var isRevealed = false
    let title: String
    let placeholder: String
    @Binding var text: String
    let systemImage: String

    var body: some View {
        SettingsInputShell(title: title, systemImage: systemImage) {
            HStack(spacing: 8) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "隐藏密码" : "显示密码")
            }
        }
    }
}

struct SettingsInputShell<Field: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(FamilyMediaTheme.accent)
                    .frame(width: 20)
                field()
                    .font(.subheadline)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.08))
            }
        }
    }
}

struct SettingsActionButton: View {
    let title: String
    let systemImage: String
    let prominent: Bool
    var role: ButtonRole?
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        prominent: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.prominent = prominent
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : (prominent ? Color.black : Color.white))
        .background(buttonBackground, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            if !prominent {
                RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10))
            }
        }
    }

    private var buttonBackground: Color {
        prominent ? FamilyMediaTheme.accent : Color.white.opacity(0.07)
    }
}

struct SettingsStepper: View {
    let title: String
    let valueText: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(valueText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

struct WorkingAndMessage: View {
    let isWorking: Bool
    let message: AppMessage?

    var body: some View {
        if isWorking {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在处理…").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let message {
            StatusLine(
                icon: messageIcon(message),
                text: message.text,
                tint: message.foregroundStyle
            )
        }
    }

    private func messageIcon(_ message: AppMessage) -> String {
        switch message.style {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct StatusLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StatusValueRow: View {
    let row: SettingsStatusRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(row.value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(row.isHealthy ? Color.primary : Color.orange)
                .multilineTextAlignment(.trailing)
        }
    }
}
