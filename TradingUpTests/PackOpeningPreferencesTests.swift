import XCTest
@testable import TradingUp

@MainActor
final class PackOpeningPreferencesTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "TradingUp.PackOpeningTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testBothPreferencesDefaultToOff() throws {
        let defaults = try makeDefaults()
        let preferences = PackOpeningPreferences(defaults: defaults)

        XCTAssertFalse(preferences.tapToOpenPacks)
        XCTAssertFalse(preferences.autoOpenPacks)
        XCTAssertNil(defaults.object(forKey: PackOpeningPreferences.tapToOpenKey))
        XCTAssertNil(defaults.object(forKey: PackOpeningPreferences.autoOpenKey))
    }

    func testExistingFeedbackPreferencesDoNotOptIntoPackOpeningChanges() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "tradingup_sound_enabled")
        defaults.set(true, forKey: "tradingup_music_enabled")
        defaults.set(true, forKey: Haptics.prefKey)

        let preferences = PackOpeningPreferences(defaults: defaults)
        XCTAssertFalse(preferences.tapToOpenPacks)
        XCTAssertFalse(preferences.autoOpenPacks)
    }

    func testEveryCombinationPersistsIndependently() throws {
        for tap in [false, true] {
            for auto in [false, true] {
                let defaults = try makeDefaults()
                let preferences = PackOpeningPreferences(defaults: defaults)
                preferences.tapToOpenPacks = tap
                preferences.autoOpenPacks = auto

                let relaunched = PackOpeningPreferences(defaults: defaults)
                XCTAssertEqual(relaunched.tapToOpenPacks, tap)
                XCTAssertEqual(relaunched.autoOpenPacks, auto)
                XCTAssertEqual(defaults.bool(forKey: PackOpeningPreferences.tapToOpenKey), tap)
                XCTAssertEqual(defaults.bool(forKey: PackOpeningPreferences.autoOpenKey), auto)
            }
        }
    }

    func testTurningEitherPreferenceOffDoesNotResetTheOther() throws {
        let defaults = try makeDefaults()
        let preferences = PackOpeningPreferences(defaults: defaults)
        preferences.tapToOpenPacks = true
        preferences.autoOpenPacks = true

        preferences.tapToOpenPacks = false
        var relaunched = PackOpeningPreferences(defaults: defaults)
        XCTAssertFalse(relaunched.tapToOpenPacks)
        XCTAssertTrue(relaunched.autoOpenPacks)

        preferences.tapToOpenPacks = true
        preferences.autoOpenPacks = false
        relaunched = PackOpeningPreferences(defaults: defaults)
        XCTAssertTrue(relaunched.tapToOpenPacks)
        XCTAssertFalse(relaunched.autoOpenPacks)

        preferences.tapToOpenPacks = false
        relaunched = PackOpeningPreferences(defaults: defaults)
        XCTAssertFalse(relaunched.tapToOpenPacks)
        XCTAssertFalse(relaunched.autoOpenPacks)
    }
}
