import SwiftUI

struct ContentUnavailableView<Action: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder let action: () -> Action

    init(
        title: String,
        message: String,
        systemImage: String = "rectangle.stack.badge.minus",
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(FamilyMediaTVTheme.accent)
            Text(title)
                .font(.largeTitle.bold())
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }
}
