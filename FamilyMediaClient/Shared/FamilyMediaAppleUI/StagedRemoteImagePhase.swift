import FamilyMediaCore
import UIKit

enum StagedRemoteImagePhase {
    case loading
    case preview(UIImage, progress: Double?)
    case full(UIImage)
    case failed(preview: UIImage?)

    var displayedImage: UIImage? {
        switch self {
        case .preview(let image, _), .full(let image):
            return image
        case .failed(let preview):
            return preview
        case .loading:
            return nil
        }
    }

    var progress: Double? {
        guard case .preview(_, let progress) = self else { return nil }
        return progress
    }

    var isLoadingFullImage: Bool {
        if case .preview = self { return true }
        return false
    }

    var didFailFullImage: Bool {
        if case .failed(let preview) = self { return preview != nil }
        return false
    }

    var didFailCompletely: Bool {
        if case .failed(preview: nil) = self { return true }
        return false
    }

    var displaysPreviewQuality: Bool {
        switch self {
        case .preview:
            return true
        case .failed(let preview):
            return preview != nil
        case .loading, .full:
            return false
        }
    }

    var photoLoadState: MediaPhotoLoadState {
        switch self {
        case .loading, .preview:
            return .loading
        case .full:
            return .ready
        case .failed:
            return .failed
        }
    }
}
