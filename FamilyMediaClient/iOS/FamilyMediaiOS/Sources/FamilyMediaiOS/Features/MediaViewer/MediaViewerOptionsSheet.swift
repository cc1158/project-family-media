import FamilyMediaCore
import SwiftUI

struct MediaViewerOptionsSheet: View {
    let information: MediaInformationPresentation
    let supportsThumbnailRegeneration: Bool
    let isWorking: Bool
    let message: AppMessage?
    let onRegenerateThumbnail: () -> Void

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    MediaInformationDetailView(presentation: information)
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
                        .foregroundStyle(message.foregroundStyle)
                }
            }
            .navigationTitle("媒体选项")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
