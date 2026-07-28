import XCTest
@testable import TradingUp

/// Deterministic checks on the generated card catalogue. These are fast and
/// should catch data-generation regressions immediately; slower Monte Carlo
/// economy checks stay in tools/verify/main.swift.
final class DataIntegrityTests: XCTestCase {
    func testCardCountMatchesGeneratedData() {
        XCTAssertEqual(CardDatabase.all.count, 250, "CardData.swift should match the Card type")
    }

    func testAllNamesUnique() {
        XCTAssertEqual(Set(CardDatabase.all.map { $0.name }).count, 250)
    }

    func testAllIdsUnique() {
        XCTAssertEqual(Set(CardDatabase.all.map { $0.id }).count, 250)
    }

    func testRarityCountsPerSet() {
        for s in 1...5 {
            let sc = CardDatabase.cards(inSet: s)
            let counts = Dictionary(grouping: sc, by: { $0.rarity }).mapValues { $0.count }
            XCTAssertEqual(counts[.common], 25, "set \(s) common count")
            XCTAssertEqual(counts[.uncommon], 15, "set \(s) uncommon count")
            XCTAssertEqual(counts[.rare], 7, "set \(s) rare count")
            XCTAssertEqual(counts[.ultra], 3, "set \(s) ultra count")
        }
    }

    func testValueOrderingAcrossRarities() {
        let order: [Rarity] = [.common, .uncommon, .rare, .ultra]
        for s in 1...5 {
            let sc = CardDatabase.cards(inSet: s)
            for (lo, hi) in zip(order, order.dropFirst()) {
                let maxLo = sc.filter { $0.rarity == lo }.map { $0.baseValue }.max()!
                let minHi = sc.filter { $0.rarity == hi }.map { $0.baseValue }.min()!
                XCTAssertLessThan(maxLo, minHi, "set \(s): best \(lo) should be worth less than worst \(hi)")
            }
        }
    }

    func testEvolutionLinksResolve() {
        var evoBad = 0
        for c in CardDatabase.all {
            if let t = c.evolvesToId, CardDatabase.byId[t] == nil { evoBad += 1 }
            if let f = c.evolvesFromId, CardDatabase.byId[f] == nil { evoBad += 1 }
        }
        XCTAssertEqual(evoBad, 0, "all evolution links should resolve to a real card")
    }

    func testEvolutionLineCount() {
        XCTAssertEqual(CardDatabase.evolutionLines.count, 65, "5 sets × 13 multi-stage evolution lines")
    }
}
