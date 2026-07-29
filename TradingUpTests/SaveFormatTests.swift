import XCTest
@testable import TradingUp

/// Save/load hygiene: every schema change must remain additive so old saves
/// never crash on decode, and the sanitizer must strip retired cards safely.
final class SaveFormatTests: XCTestCase {
    func testLegacySaveMissingNewerKeysStillDecodes() {
        let legacy = Data(#"{"cash":42.5,"instances":[],"claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false}"#.utf8)
        let old = try? JSONDecoder().decode(GameCore.self, from: legacy)
        XCTAssertNotNil(old, "a save missing newer keys should still decode")
        XCTAssertEqual(old?.cash, 42.5, "existing values should survive a lenient decode")
        XCTAssertEqual(old?.winAcknowledged, false)
        XCTAssertEqual(old?.welcomeSeen, false)
    }

    func testEmptyPayloadDecodesToDefaults() {
        let empty = try? JSONDecoder().decode(GameCore.self, from: Data("{}".utf8))
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.cash, Economy.startingCash, "an empty payload should decode to a default game")
    }

    func testSaveRecordsSchemaVersionAndRoundTrips() {
        var core = GameCore()
        core.cash = 777
        let encoded = try! JSONEncoder().encode(SaveFile(core: core))
        let round = try? JSONDecoder().decode(SaveFile.self, from: encoded)
        XCTAssertEqual(round?.schemaVersion, SaveFile.currentVersion)
        XCTAssertEqual(round?.core.cash, 777, "save should round-trip the game state")
    }

    func testCardCopyWithOnlyCardIdDecodes() {
        let sparse = Data(#"{"instances":[{"cardId":"S1-001"}]}"#.utf8)
        let sparseCore = try? JSONDecoder().decode(GameCore.self, from: sparse)
        XCTAssertEqual(sparseCore?.instances.count, 1, "a card copy with only a cardId should still decode")
        XCTAssertEqual(sparseCore?.instances.first?.foil, false, "missing per-copy keys fall back to defaults")
        XCTAssertNil(sparseCore?.instances.first?.grade)
        XCTAssertEqual(sparseCore?.instances.first?.cardId, "S1-001", "the required cardId should survive")
    }

    func testUnknownCardIdResolvesToWorthlessPlaceholder() {
        var stale = GameCore()
        stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
        let ghost = stale.instances[1]
        XCTAssertEqual(ghost.card.id, "S9-999")
        XCTAssertEqual(ghost.currentValue, 0, "an unknown card id should resolve to a worthless placeholder, not crash")
    }

    func testSanitizeDropsInstancesWithRetiredCards() {
        var stale = GameCore()
        stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
        let (clean, dropped) = stale.sanitized()
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(clean.instances.count, 1)
        XCTAssertEqual(clean.instances[0].cardId, "S1-001")
    }

    func testSanitizeIsANoOpOnAValidSave() {
        XCTAssertEqual(GameCore().sanitized().droppedInstances, 0)
    }

    func testSanitizeUnclaimsSetsThatAreNoLongerComplete() {
        var claimed = GameCore()
        for c in CardDatabase.cards(inSet: 1) { claimed.instances.append(CardInstance(cardId: c.id)) }
        _ = claimed.checkBonuses()
        XCTAssertTrue(claimed.claimedSets.contains(1), "set 1 should be claimed while complete")
        claimed.instances.append(CardInstance(cardId: "S9-999"))
        claimed.instances.removeAll { $0.cardId == "S1-001" }
        XCTAssertFalse(claimed.sanitized().core.claimedSets.contains(1),
                       "a set that is no longer complete after sanitizing should be un-claimed")
    }
}
