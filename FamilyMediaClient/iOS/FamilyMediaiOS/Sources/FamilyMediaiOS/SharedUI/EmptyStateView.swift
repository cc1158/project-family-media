import SwiftUI

struct EmptyStateView<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let action: () -> Action

    init(
        title: String,
        message: String,
        systemImage: String = "photo.on.rectangle.angled",
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(FamilyMediaTheme.accent)
                .frame(width: 76, height: 76)
                .background(FamilyMediaTheme.accent.opacity(0.12), in: Circle())
            VStack(spacing: 6) {
                Text(title).font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            action()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
