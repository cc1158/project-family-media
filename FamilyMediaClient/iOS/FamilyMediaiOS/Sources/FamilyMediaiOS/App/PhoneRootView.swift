import SwiftUI

struct PhoneRootView<MediaHome: View, Settings: View>: View {
    @Binding private var selectedTab: RootTab
    @Binding private var mediaNavigationPath: NavigationPath
    private let mediaHome: MediaHome
    private let settings: Settings

    init(
        selectedTab: Binding<RootTab>,
        mediaNavigationPath: Binding<NavigationPath>,
        @ViewBuilder mediaHome: () -> MediaHome,
        @ViewBuilder settings: () -> Settings
    ) {
        _selectedTab = selectedTab
        _mediaNavigationPath = mediaNavigationPath
        self.mediaHome = mediaHome()
        self.settings = settings()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $mediaNavigationPath) {
                mediaHome
            }
            .tabItem {
                Label("媒体", systemImage: "play.rectangle.on.rectangle.fill")
                    .accessibilityIdentifier("tab.media")
            }
            .tag(RootTab.media)

            NavigationStack {
                settings
            }
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
                    .accessibilityIdentifier("tab.settings")
            }
            .tag(RootTab.settings)
        }
        .tint(FamilyMediaTheme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
