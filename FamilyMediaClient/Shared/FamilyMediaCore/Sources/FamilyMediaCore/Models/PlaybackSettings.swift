import Foundation

public enum PlaybackSettings {
    public static let autoplayLimitKey = "familyMedia.playback.autoplayLimit"
    public static let photoDurationKey = "familyMedia.playback.photoDurationSeconds"

    public static let defaultAutoplayLimit = 20
    public static let defaultPhotoDurationSeconds = 5

    public static let autoplayLimitRange = 1...100
    public static let photoDurationRange = 1...60

    public static func normalizedAutoplayLimit(_ value: Int) -> Int {
        min(max(value, autoplayLimitRange.lowerBound), autoplayLimitRange.upperBound)
    }

    public static func normalizedPhotoDurationSeconds(_ value: Int) -> Int {
        min(max(value, photoDurationRange.lowerBound), photoDurationRange.upperBound)
    }

    /// Rewrites persisted playback preferences into the current supported range.
    ///
    /// This is intentionally safe to call on every launch. It protects upgraded
    /// installations from values written by an older build, and replaces values
    /// with an unexpected storage type instead of allowing them into SwiftUI
    /// controls.
    public static func repairPersistedValues(in defaults: UserDefaults = .standard) {
        let autoplayLimit = persistedInteger(
            forKey: autoplayLimitKey,
            in: defaults,
            fallback: defaultAutoplayLimit,
            normalize: normalizedAutoplayLimit
        )
        let photoDurationSeconds = persistedInteger(
            forKey: photoDurationKey,
            in: defaults,
            fallback: defaultPhotoDurationSeconds,
            normalize: normalizedPhotoDurationSeconds
        )

        defaults.set(autoplayLimit, forKey: autoplayLimitKey)
        defaults.set(photoDurationSeconds, forKey: photoDurationKey)
    }

    private static func persistedInteger(
        forKey key: String,
        in defaults: UserDefaults,
        fallback: Int,
        normalize: (Int) -> Int
    ) -> Int {
        guard let value = defaults.object(forKey: key),
              !(value is Bool),
              let integer = value as? Int else {
            return fallback
        }
        return normalize(integer)
    }
}
