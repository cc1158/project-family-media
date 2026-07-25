import AVKit
import FamilyMediaCore
import SwiftUI
import UIKit

struct TVSystemVideoPlayer: UIViewControllerRepresentable {
    let snapshot: MediaPlaybackSnapshot
    let item: MediaItem
    let information: MediaInformationPresentation
    let canGoPrevious: Bool
    let canGoNext: Bool
    let supportsThumbnailRegeneration: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onRegenerateThumbnail: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = true
        controller.playbackControlsIncludeTransportBar = true
        controller.playbackControlsIncludeInfoViews = true
        controller.transportBarIncludesTitleView = true
        controller.view.accessibilityIdentifier = "viewer.systemVideoPlayer"
        context.coordinator.update(
            controller: controller,
            configuration: configuration
        )
        return controller
    }

    func updateUIViewController(
        _ controller: AVPlayerViewController,
        context: Context
    ) {
        context.coordinator.update(
            controller: controller,
            configuration: configuration
        )
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        controller.delegate = nil
        controller.player = nil
        controller.customInfoViewControllers = []
        controller.transportBarCustomMenuItems = []
    }

    private var configuration: Configuration {
        Configuration(
            snapshot: snapshot,
            item: item,
            information: information,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext,
            supportsThumbnailRegeneration: supportsThumbnailRegeneration,
            onPrevious: onPrevious,
            onNext: onNext,
            onRegenerateThumbnail: onRegenerateThumbnail,
            onDismiss: onDismiss
        )
    }
}

extension TVSystemVideoPlayer {
    struct Configuration {
        let snapshot: MediaPlaybackSnapshot
        let item: MediaItem
        let information: MediaInformationPresentation
        let canGoPrevious: Bool
        let canGoNext: Bool
        let supportsThumbnailRegeneration: Bool
        let onPrevious: () -> Void
        let onNext: () -> Void
        let onRegenerateThumbnail: () -> Void
        let onDismiss: () -> Void
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        private var configuration: Configuration?
        private weak var player: AVPlayer?
        private var representedItemID: String?
        private var menuSignature: MenuSignature?
        private var didRequestDismiss = false

        func update(
            controller: AVPlayerViewController,
            configuration: Configuration
        ) {
            self.configuration = configuration

            if player !== configuration.snapshot.player {
                player = configuration.snapshot.player
                controller.player = configuration.snapshot.player
                representedItemID = nil
            }

            if representedItemID != configuration.item.id {
                representedItemID = configuration.item.id
                applyTitleMetadata(
                    title: configuration.item.displayTitle,
                    to: configuration.snapshot.player?.currentItem
                )
                controller.customInfoViewControllers = [
                    makeInformationController(configuration.information)
                ]
            }

            let nextMenuSignature = MenuSignature(
                canGoPrevious: configuration.canGoPrevious,
                canGoNext: configuration.canGoNext,
                supportsThumbnailRegeneration: configuration.supportsThumbnailRegeneration
            )
            if menuSignature != nextMenuSignature {
                menuSignature = nextMenuSignature
                controller.transportBarCustomMenuItems = makeTransportItems(
                    signature: nextMenuSignature
                )
            }
        }

        func playerViewControllerShouldDismiss(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            guard !didRequestDismiss else { return false }
            didRequestDismiss = true
            configuration?.onDismiss()
            // This controller is embedded by UIViewControllerRepresentable,
            // so the surrounding SwiftUI full-screen cover owns dismissal.
            return false
        }

        private func makeTransportItems(signature: MenuSignature) -> [UIMenuElement] {
            let previous = UIAction(
                title: "上一个",
                image: UIImage(systemName: "backward.end.fill")
            ) { [weak self] _ in
                self?.configuration?.onPrevious()
            }
            if !signature.canGoPrevious {
                previous.attributes.insert(.disabled)
            }

            let next = UIAction(
                title: "下一个",
                image: UIImage(systemName: "forward.end.fill")
            ) { [weak self] _ in
                self?.configuration?.onNext()
            }
            if !signature.canGoNext {
                next.attributes.insert(.disabled)
            }

            var items: [UIMenuElement] = [previous, next]
            if signature.supportsThumbnailRegeneration {
                let regenerate = UIAction(
                    title: "重新生成封面",
                    image: UIImage(systemName: "arrow.triangle.2.circlepath.camera")
                ) { [weak self] _ in
                    self?.configuration?.onRegenerateThumbnail()
                }
                items.append(
                    UIMenu(
                        title: "媒体选项",
                        image: UIImage(systemName: "ellipsis.circle"),
                        children: [regenerate]
                    )
                )
            }
            return items
        }

        private func makeInformationController(
            _ information: MediaInformationPresentation
        ) -> UIViewController {
            let controller = UIHostingController(
                rootView: TVSystemMediaInformationView(presentation: information)
            )
            controller.title = "媒体信息"
            controller.preferredContentSize = CGSize(width: 1_000, height: 520)
            return controller
        }

        private func applyTitleMetadata(title: String, to item: AVPlayerItem?) {
            guard let item else { return }
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierTitle
            metadata.value = title as NSString
            metadata.extendedLanguageTag = "zh-Hans"
            item.externalMetadata = [metadata]
        }
    }
}

private struct MenuSignature: Equatable {
    let canGoPrevious: Bool
    let canGoNext: Bool
    let supportsThumbnailRegeneration: Bool
}

private struct TVSystemMediaInformationView: View {
    let presentation: MediaInformationPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(presentation.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 32) {
                    Label(row.title, systemImage: row.id.systemImage)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 32)
                    Text(row.value)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("viewer.information.\(row.id.rawValue)")
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .background(Color.black)
    }
}
