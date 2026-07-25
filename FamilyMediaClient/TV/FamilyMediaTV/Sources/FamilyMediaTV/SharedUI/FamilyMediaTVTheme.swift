import SwiftUI

enum FamilyMediaTVTheme {
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.96)
    static let purple = Color(red: 0.52, green: 0.42, blue: 0.96)
    static let background = Color(red: 0.025, green: 0.03, blue: 0.055)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.055, green: 0.075, blue: 0.13),
                background,
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
struct TVAppBackground: View {
    var body: some View {
        ZStack {
            FamilyMediaTVTheme.backgroundGradient
            Circle()
                .fill(FamilyMediaTVTheme.purple.opacity(0.17))
                .frame(width: 720, height: 720)
                .blur(radius: 150)
                .offset(x: 620, y: -360)
            Circle()
                .fill(FamilyMediaTVTheme.accent.opacity(0.11))
                .frame(width: 620, height: 620)
                .blur(radius: 150)
                .offset(x: -720, y: 380)
        }
        .ignoresSafeArea()
    }
}
