import FamilyMediaCore
import SwiftUI

struct DemoArtworkView: View {
    let item: MediaItem

    private let palettes: [[Color]] = [
        [Color.indigo, Color.purple],
        [Color.blue, Color.cyan],
        [Color.orange, Color.pink],
        [Color.teal, Color.blue],
        [Color.purple, Color.red]
    ]

    private var palette: [Color] {
        let seed = item.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palettes[seed % palettes.count]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 120, height: 120)
                .blur(radius: 2)
                .offset(x: 55, y: -35)
            Image(
                systemName: item.isContainer
                    ? "folder.fill"
                    : (item.kind == .video ? "film.fill" : "photo.fill")
            )
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
