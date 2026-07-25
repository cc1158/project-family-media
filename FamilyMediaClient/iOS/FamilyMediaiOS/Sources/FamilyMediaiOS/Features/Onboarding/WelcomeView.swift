import SwiftUI

struct WelcomeView: View {
    let onConfigure: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 28) {
                    hero

                    VStack(spacing: 12) {
                        WelcomeFeatureRow(
                            systemImage: "house.fill",
                            tint: FamilyMediaTheme.accent,
                            title: "家的照片和视频",
                            detail: "连接自己的家庭媒体服务，按照片或视频浏览。",
                            accessibilityIdentifier: "onboarding.family",
                            action: onConfigure
                        )
                        WelcomeFeatureRow(
                            systemImage: "play.tv.fill",
                            tint: FamilyMediaTheme.purple,
                            title: "也能连接 Jellyfin",
                            detail: "两个来源可以同时使用，切换不会影响登录状态。",
                            accessibilityIdentifier: "onboarding.jellyfin",
                            action: onConfigure
                        )
                        WelcomeFeatureRow(
                            systemImage: "play.circle.fill",
                            tint: .orange,
                            title: "为家里的设备准备",
                            detail: "兼容的视频直接播放，其他格式可由 Jellyfin 转换。",
                            accessibilityIdentifier: "onboarding.playback",
                            action: onConfigure
                        )
                    }

                    VStack(spacing: 12) {
                        Button(action: onConfigure) {
                            Label("开始连接", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                                .foregroundStyle(.black)
                                .background(
                                    FamilyMediaTheme.accent,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("onboarding.configure")

                        Button("先看看首页", action: onBrowse)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("onboarding.browse")
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(
                    LinearGradient(
                        colors: [FamilyMediaTheme.accent, FamilyMediaTheme.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 25, style: .continuous)
                )
                .shadow(color: FamilyMediaTheme.purple.opacity(0.28), radius: 24, y: 12)

            VStack(spacing: 7) {
                Text("欢迎使用家映")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("把家的时光，放在一起看")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WelcomeFeatureRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .frame(minHeight: 44)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开连接设置")
    }
}
