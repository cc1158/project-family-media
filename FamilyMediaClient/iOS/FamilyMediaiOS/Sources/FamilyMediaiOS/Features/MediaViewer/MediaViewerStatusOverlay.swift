import FamilyMediaCore
import SwiftUI

struct MediaViewerStatusOverlay: View {
    let playbackState: MediaPlaybackState
    let playbackPositionSeconds: Double
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch playbackState {
        case .preparing:
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(playbackPositionSeconds > 0 ? "正在恢复播放…" : "正在准备播放…")
            }
            .foregroundStyle(.white)
        case .buffering(.transcode):
            Text("Jellyfin 正在转码")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.65))
                .clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 72)
        case .failed(let failure):
            failureView(failure)
        case .buffering:
            VStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("正在缓冲…").font(.caption)
            }
            .foregroundStyle(.white)
        case .idle, .playing, .paused:
            EmptyView()
        }
    }

    private func failureView(_ failure: MediaPlaybackFailure) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
            Text(failure.message)
                .multilineTextAlignment(.center)
            if failure.recovery == .signIn {
                Text("请退出播放器，然后到设置中重新登录 Jellyfin。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            HStack(spacing: 12) {
                if failure.recovery == .retry {
                    Button("重新尝试", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(FamilyMediaTheme.accent)
                }
                Button(
                    failure.recovery == .signIn ? "退出播放器" : "返回媒体库",
                    action: onDismiss
                )
                .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.orange)
        .padding(24)
        .background(.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: 560)
        .padding(24)
    }
}
