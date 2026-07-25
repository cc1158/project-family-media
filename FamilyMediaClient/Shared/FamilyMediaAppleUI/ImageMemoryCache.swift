import Foundation
import UIKit

final class ImageMemoryCache: @unchecked Sendable {
    private let storage = NSCache<NSString, SendableImage>()
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        storage.name = "Jiaying.MediaImages"
        storage.countLimit = 160
        storage.totalCostLimit = 96 * 1_024 * 1_024
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeAllObjects()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func object(forKey key: NSString) -> SendableImage? {
        storage.object(forKey: key)
    }

    func setObject(_ object: SendableImage, forKey key: NSString, cost: Int) {
        storage.setObject(object, forKey: key, cost: cost)
    }

    func removeAllObjects() {
        storage.removeAllObjects()
    }
}
