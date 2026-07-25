import FamilyMediaCore
import SwiftUI

struct MediaViewerOptionsPanel: View {
    let supportsThumbnailRegeneration: Bool
    let isWorking: Bool
    let message: AppMessage?
    let onShowInformation: () -> Void
    let onRegenerateThumbnail: () -> Void

    var body: some View {
        HStack {
            Spacer()

            VStack(alignment: .leading, spacing: 28) {
                Text("媒体选项")
                    .font(.title2.bold())

                Button {
                    onShowInformation()
                } label: {
                    Label("媒体信息", systemImage: "info.circle")
                }
                .accessibilityIdentifier("viewer.information.open")

                if supportsThumbnailRegeneration {
                    Button {
                        onRegenerateThumbnail()
                    } label: {
                        Label("重新生成封面", systemImage: "arrow.triangle.2.circlepath.camera")
                    }
                    .disabled(isWorking)
                }

                if let message {
                    Text(message.text)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(message.tvForegroundStyle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focusSection()
            .frame(width: 420, alignment: .leading)
            .padding(40)
            .background(.black.opacity(0.84))
            .padding(.trailing, 64)
        }
        .ignoresSafeArea()
    }
}

struct MediaInformationPanel: View {
    let presentation: MediaInformationPresentation
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                Text("媒体信息")
                    .font(.title.bold())

                ForEach(presentation.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 28) {
                        Label(row.title, systemImage: row.id.systemImage)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 28)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("viewer.information.\(row.id.rawValue)")
                }

                Button("返回选项", action: onBack)
                    .accessibilityIdentifier("viewer.information.back")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(width: 720)
            .padding(48)
            .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
        }
    }
}
