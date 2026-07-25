import SwiftUI
import UIKit

@MainActor
final class PlaybackIdleTimerController: ObservableObject {
    private var previousValue: Bool?
    private let readValue: @MainActor () -> Bool
    private let writeValue: @MainActor (Bool) -> Void

    init(
        readValue: @escaping @MainActor () -> Bool = {
            UIApplication.shared.isIdleTimerDisabled
        },
        writeValue: @escaping @MainActor (Bool) -> Void = {
            UIApplication.shared.isIdleTimerDisabled = $0
        }
    ) {
        self.readValue = readValue
        self.writeValue = writeValue
    }

    isolated deinit {
        release()
    }

    func setPlaybackActive(_ isActive: Bool) {
        if isActive {
            guard previousValue == nil else { return }
            previousValue = readValue()
            writeValue(true)
        } else {
            release()
        }
    }

    func release() {
        guard let previousValue else { return }
        writeValue(previousValue)
        self.previousValue = nil
    }
}
