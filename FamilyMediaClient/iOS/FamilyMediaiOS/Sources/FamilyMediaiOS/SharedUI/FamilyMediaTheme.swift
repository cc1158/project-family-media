import SwiftUI

enum FamilyMediaTheme {
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.96)
    static let purple = Color(red: 0.52, green: 0.42, blue: 0.96)
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let surface = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.10)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.075, blue: 0.13),
                background,
                Color(red: 0.025, green: 0.03, blue: 0.055)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            FamilyMediaTheme.backgroundGradient
            Circle()
                .fill(FamilyMediaTheme.purple.opacity(0.16))
                .frame(width: 330, height: 330)
                .blur(radius: 80)
                .offset(x: 170, y: -330)
            Circle()
                .fill(FamilyMediaTheme.accent.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -180, y: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .background(FamilyMediaTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(FamilyMediaTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func familyNavigationStyle() -> some View {
        toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(FamilyMediaTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
