import SwiftUI

enum IPadSidebarMetrics {
    static let minimumWidth: CGFloat = 240
    static let idealWidth: CGFloat = 260
    static let maximumWidth: CGFloat = 300
}

struct IPadRootSplitView<Detail: View>: View {
    @Binding private var selection: RootSidebarDestination?
    @Binding private var detailNavigationPath: NavigationPath
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    private let detail: Detail

    init(
        selection: Binding<RootSidebarDestination?>,
        detailNavigationPath: Binding<NavigationPath>,
        @ViewBuilder detail: () -> Detail
    ) {
        _selection = selection
        _detailNavigationPath = detailNavigationPath
        self.detail = detail()
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("媒体") {
                    sidebarRow(.mediaHome)
                    sidebarRow(.familyMedia)
                    sidebarRow(.jellyfin)
                }

                Section("应用") {
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("家映")
            .navigationSplitViewColumnWidth(
                min: IPadSidebarMetrics.minimumWidth,
                ideal: IPadSidebarMetrics.idealWidth,
                max: IPadSidebarMetrics.maximumWidth
            )
            .scrollContentBackground(.hidden)
            .background(FamilyMediaTheme.backgroundGradient)
            .accessibilityIdentifier("ipad.sidebar")
        } detail: {
            NavigationStack(path: $detailNavigationPath) {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(_ destination: RootSidebarDestination) -> some View {
        HStack(spacing: 12) {
            Image(systemName: destination.systemImage)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)

            Text(destination.title)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .tag(destination)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(destination.title)
        .accessibilityIdentifier("ipad.sidebar.\(destination.accessibilityName)")
    }
}
