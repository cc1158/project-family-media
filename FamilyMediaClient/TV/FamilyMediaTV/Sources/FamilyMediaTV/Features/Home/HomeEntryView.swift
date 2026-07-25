import FamilyMediaCore
import SwiftUI

struct HomeEntryView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    var availability: MediaSourceAvailability? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: systemImage)
                .font(.system(size: 62, weight: .semibold))
                .frame(width: 104, height: 104)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                if let availability {
                    Label(
                        availability.shortTitle,
                        systemImage: availability.systemImage
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: 320, height: 220, alignment: .leading)
        .padding(30)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.92), accent.opacity(0.45), Color.black.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        guard let availability else { return "\(title)，\(subtitle)" }
        return "\(title)，\(subtitle)，\(availability.shortTitle)"
    }
}
