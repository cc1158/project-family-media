import Foundation

public struct MediaViewerSession {
    public private(set) var items: [MediaItem]
    public private(set) var currentIndex: Int
    public private(set) var autoplayedItemCount = 0

    public init(items: [MediaItem], initialItem: MediaItem) {
        self.items = items.isEmpty ? [initialItem] : items
        currentIndex = self.items.firstIndex(where: { $0.id == initialItem.id }) ?? 0
    }

    public var currentItem: MediaItem {
        items[currentIndex]
    }

    public var canGoPrevious: Bool {
        currentIndex > 0
    }

    public var canGoNext: Bool {
        currentIndex < items.count - 1
    }

    public func hasReachedAutoplayLimit(_ limit: Int) -> Bool {
        autoplayedItemCount >= limit
    }

    public mutating func goPreviousManually() {
        guard canGoPrevious else { return }
        resetAutoplayCount()
        currentIndex -= 1
    }

    public mutating func goNextManually() {
        guard canGoNext else { return }
        resetAutoplayCount()
        currentIndex += 1
    }

    public mutating func beginCurrentItemAutoplayIfAllowed(limit: Int) -> Bool {
        guard !hasReachedAutoplayLimit(limit) else {
            return false
        }

        autoplayedItemCount += 1
        return true
    }

    public mutating func advanceAutomaticallyIfPossible() -> Bool {
        guard canGoNext else {
            return false
        }

        currentIndex += 1
        return true
    }

    public mutating func continueAutoplayAfterLimitIfPossible() -> Bool {
        guard canGoNext else {
            return false
        }

        resetAutoplayCount()
        currentIndex += 1
        return true
    }

    private mutating func resetAutoplayCount() {
        autoplayedItemCount = 0
    }
}
