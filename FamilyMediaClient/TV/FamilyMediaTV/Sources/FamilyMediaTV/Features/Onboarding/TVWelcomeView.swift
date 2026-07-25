import SwiftUI

struct TVWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            TVAppBackground()

            VStack(spacing: 42) {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 138, height: 138)
                        .background(
                            LinearGradient(
                                colors: [FamilyMediaTVTheme.accent, FamilyMediaTVTheme.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
                        )

                    Text("欢迎使用家映")
                        .font(.system(size: 58, weight: .bold))
                    Text("连接家庭媒体或 Jellyfin，在电视上一起看照片和视频")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 28) {
                    TVWelcomeFeature(
                        systemImage: "house.fill",
                        title: "家庭媒体",
                        detail: "照片与家庭视频"
                    )
                    TVWelcomeFeature(
                        systemImage: "play.tv.fill",
                        title: "Jellyfin",
                        detail: "电影、剧集与媒体库"
                    )
                    TVWelcomeFeature(
                        systemImage: "gearshape.fill",
                        title: "先到设置",
                        detail: "填写家里 NAS 的地址"
                    )
                }

                Button(action: onContinue) {
                    Label("继续", systemImage: "arrow.right")
                        .frame(minWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .tint(FamilyMediaTVTheme.accent)
            }
            .padding(80)
        }
    }
}

private struct TVWelcomeFeature: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(FamilyMediaTVTheme.accent)
            Text(title)
                .font(.title2.bold())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(width: 350, height: 196)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.10))
        }
        .accessibilityElement(children: .combine)
    }
}
