import FamilyMediaCore
import SwiftUI

struct MediaViewerControlsBar: View {
    let mediaKind: MediaKind
    let photoDateText: String
    let timeline: MediaPlaybackTimeline
    let playbackTitle: String
    let playbackSystemImage: String
    let isMuted: Bool
    let canGoPrevious: Bool
    let canTogglePlayback: Bool
    let canGoNext: Bool
    let isCompactHeight: Bool
    @Binding var scrubberSeconds: Double
    @Binding var isScrubbing: Bool
    let onSeek: (Double) -> Void
    let onToggleMute: () -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: isCompactHeight ? 8 : 14) {
            if mediaKind == .photo {
                Text(photoDateText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(photoDateText)
                    .accessibilityIdentifier("viewer.photo.date")
            } else {
                timelineView
            }

            HStack(spacing: isCompactHeight ? 34 : 46) {
                transportButton(
                    title: "上一个",
                    systemImage: "backward.end.fill",
                    size: isCompactHeight ? 42 : 48,
                    accessibilityIdentifier: "viewer.previous",
                    disabled: !canGoPrevious,
                    action: onPrevious
                )

                transportButton(
                    title: playbackTitle,
                    systemImage: playbackSystemImage,
                    size: isCompactHeight ? 52 : 62,
                    isPrimary: true,
                    accessibilityIdentifier: "viewer.playPause",
                    disabled: !canTogglePlayback,
                    action: onTogglePlayback
                )

                transportButton(
                    title: "下一个",
                    systemImage: "forward.end.fill",
                    size: isCompactHeight ? 42 : 48,
                    accessibilityIdentifier: "viewer.next",
                    disabled: !canGoNext,
                    action: onNext
                )
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 920)
        .padding(.horizontal, isCompactHeight ? 24 : 28)
        .padding(.top, isCompactHeight ? 34 : 58)
        .padding(.bottom, isCompactHeight ? 8 : 22)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.68), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var timelineView: some View {
        let displayTimeline = MediaPlaybackTimeline(
            positionSeconds: isScrubbing ? scrubberSeconds : timeline.positionSeconds,
            durationSeconds: timeline.durationSeconds,
            bufferedSeconds: timeline.bufferedSeconds
        )

        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                ZStack {
                    ProgressView(value: timeline.bufferedProgress)
                        .tint(.white.opacity(0.28))
                    Slider(
                        value: $scrubberSeconds,
                        in: 0...max(1, timeline.durationSeconds),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                onSeek(scrubberSeconds)
                            }
                        }
                    )
                    .tint(FamilyMediaTheme.accent)
                    .disabled(!timeline.canSeek)
                    .accessibilityLabel("播放进度")
                    .accessibilityIdentifier("viewer.timeline.slider")
                }

                HStack {
                    Text(displayTimeline.positionText)
                    Spacer()
                    Text(displayTimeline.durationText)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
            }

            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: isCompactHeight ? 14 : 16, weight: .semibold))
                    .frame(
                        width: isCompactHeight ? 32 : 36,
                        height: isCompactHeight ? 32 : 36
                    )
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? "取消静音" : "静音")
            .accessibilityValue(isMuted ? "已静音" : "有声音")
            .accessibilityIdentifier("viewer.mute")
        }
    }

    private func transportButton(
        title: String,
        systemImage: String,
        size: CGFloat,
        isPrimary: Bool = false,
        accessibilityIdentifier: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(isPrimary ? .title2 : .title3)
                .frame(width: size, height: size)
                .foregroundStyle(isPrimary ? Color.black : Color.white)
                .background(
                    Circle()
                        .fill(isPrimary ? Color.white : Color.white.opacity(0.14))
                )
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.32 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
