import FamilyMediaCore
import SwiftUI

enum PhotoViewerControl: Hashable {
    case previous
    case next
    case options
}

struct PhotoViewerControlsOverlay: View {
    let item: MediaItem
    let photoDateText: String
    let canGoPrevious: Bool
    let canGoNext: Bool
    let focusedControl: FocusState<PhotoViewerControl?>.Binding
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onOptions: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 22) {
                HStack(spacing: 24) {
                    Text(item.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("viewer.title")

                    Spacer()

                    controlButton(
                        title: "媒体选项",
                        systemImage: "ellipsis",
                        control: .options,
                        size: 46,
                        disabled: false,
                        action: onOptions
                    )
                }

                Text(photoDateText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
                    .accessibilityLabel(photoDateText)
                    .accessibilityIdentifier("viewer.photo.date")

                HStack(spacing: 46) {
                    controlButton(
                        title: "上一个",
                        systemImage: "backward.end.fill",
                        control: .previous,
                        size: 52,
                        disabled: !canGoPrevious,
                        action: onPrevious
                    )

                    controlButton(
                        title: "下一个",
                        systemImage: "forward.end.fill",
                        control: .next,
                        size: 52,
                        disabled: !canGoNext,
                        action: onNext
                    )
                }
                .focusSection()
            }
            .frame(maxWidth: 1_120)
            .padding(.horizontal, 80)
            .padding(.top, 100)
            .padding(.bottom, 46)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("viewer.controls")
    }

    private func controlButton(
        title: String,
        systemImage: String,
        control: PhotoViewerControl,
        size: CGFloat,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedControl.wrappedValue == control

        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: size, height: size)
                .foregroundStyle(Color.white)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isFocused ? 0.2 : 0.1))
                )
                .overlay {
                    Circle()
                        .stroke(
                            isFocused ? FamilyMediaTVTheme.accent : .white.opacity(0.14),
                            lineWidth: isFocused ? 3 : 1
                        )
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(disabled)
        .focused(focusedControl, equals: control)
        .scaleEffect(isFocused ? 1.08 : 1)
        .shadow(
            color: isFocused ? FamilyMediaTVTheme.accent.opacity(0.28) : .clear,
            radius: isFocused ? 14 : 0
        )
        .animation(.easeOut(duration: 0.16), value: isFocused)
        .opacity(disabled ? 0.32 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier(control.accessibilityIdentifier)
    }
}

private extension PhotoViewerControl {
    var accessibilityIdentifier: String {
        switch self {
        case .previous: "viewer.control.previous"
        case .next: "viewer.control.next"
        case .options: "viewer.control.options"
        }
    }
}
