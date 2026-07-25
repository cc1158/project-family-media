import Foundation
import Testing
@testable import FamilyMediaCore

struct PlaybackSettingsTests {
    @Test func normalizesAutoplayLimitToAllowedRange() {
        #expect(PlaybackSettings.normalizedAutoplayLimit(-1) == PlaybackSettings.autoplayLimitRange.lowerBound)
        #expect(PlaybackSettings.normalizedAutoplayLimit(20) == 20)
        #expect(PlaybackSettings.normalizedAutoplayLimit(101) == PlaybackSettings.autoplayLimitRange.upperBound)
    }

    @Test func normalizesPhotoDurationToAllowedRange() {
        #expect(PlaybackSettings.normalizedPhotoDurationSeconds(-1) == PlaybackSettings.photoDurationRange.lowerBound)
        #expect(PlaybackSettings.normalizedPhotoDurationSeconds(5) == 5)
        #expect(PlaybackSettings.normalizedPhotoDurationSeconds(61) == PlaybackSettings.photoDurationRange.upperBound)
    }

    @Test func repairWritesDefaultsWhenPreferencesAreMissing() throws {
        let fixture = try IsolatedDefaults()
        defer { fixture.remove() }
        let defaults = fixture.defaults

        PlaybackSettings.repairPersistedValues(in: defaults)

        #expect(defaults.integer(forKey: PlaybackSettings.autoplayLimitKey) == PlaybackSettings.defaultAutoplayLimit)
        #expect(defaults.integer(forKey: PlaybackSettings.photoDurationKey) == PlaybackSettings.defaultPhotoDurationSeconds)
    }

    @Test func repairClampsValuesFromAnOlderInstallation() throws {
        let fixture = try IsolatedDefaults()
        defer { fixture.remove() }
        let defaults = fixture.defaults
        defaults.set(-50, forKey: PlaybackSettings.autoplayLimitKey)
        defaults.set(500, forKey: PlaybackSettings.photoDurationKey)

        PlaybackSettings.repairPersistedValues(in: defaults)

        #expect(defaults.integer(forKey: PlaybackSettings.autoplayLimitKey) == PlaybackSettings.autoplayLimitRange.lowerBound)
        #expect(defaults.integer(forKey: PlaybackSettings.photoDurationKey) == PlaybackSettings.photoDurationRange.upperBound)
    }

    @Test func repairReplacesUnexpectedStoredTypes() throws {
        let fixture = try IsolatedDefaults()
        defer { fixture.remove() }
        let defaults = fixture.defaults
        defaults.set("100", forKey: PlaybackSettings.autoplayLimitKey)
        defaults.set(true, forKey: PlaybackSettings.photoDurationKey)

        PlaybackSettings.repairPersistedValues(in: defaults)

        #expect(defaults.integer(forKey: PlaybackSettings.autoplayLimitKey) == PlaybackSettings.defaultAutoplayLimit)
        #expect(defaults.integer(forKey: PlaybackSettings.photoDurationKey) == PlaybackSettings.defaultPhotoDurationSeconds)
    }

    @Test func repairPreservesValidPreferences() throws {
        let fixture = try IsolatedDefaults()
        defer { fixture.remove() }
        let defaults = fixture.defaults
        defaults.set(36, forKey: PlaybackSettings.autoplayLimitKey)
        defaults.set(12, forKey: PlaybackSettings.photoDurationKey)

        PlaybackSettings.repairPersistedValues(in: defaults)

        #expect(defaults.integer(forKey: PlaybackSettings.autoplayLimitKey) == 36)
        #expect(defaults.integer(forKey: PlaybackSettings.photoDurationKey) == 12)
    }

    private struct IsolatedDefaults {
        let suiteName: String
        let defaults: UserDefaults

        init() throws {
            suiteName = "PlaybackSettingsTests.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
