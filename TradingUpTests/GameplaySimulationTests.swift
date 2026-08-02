import XCTest
import SwiftUI
@testable import TradingUp

/// Deterministic RNG (SplitMix64) so gameplay tests are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class GameplaySimulationTests: XCTestCase {
    func testStartsWithStartingCash() {
        XCTAssertEqual(GameCore().cash, Economy.startingCash)
        XCTAssertTrue(GameCore().instances.isEmpty)
    }

    func testBuyingPacksChargesPriceAndYieldsBonuses() {
        var rng = SeededRNG(7)
        var core = GameCore()
        var packs = 0
        while core.cash >= Economy.packPrice(set: 1) && packs < 5 {
            let before = core.cash
            let r = core.buyPack(set: 1, using: &rng)
            XCTAssertNotNil(r, "pack \(packs + 1) should purchase")
            let bonus = r!.bonuses.reduce(0) { $0 + $1.amount }
            XCTAssertEqual(core.cash, before - 10 + bonus, accuracy: 0.001)
            XCTAssertEqual(r!.pulled.count, 6, "pack should yield 6 cards")
            packs += 1
        }
        XCTAssertEqual(core.instances.count, packs * 6, "collection should grow by 6 per pack")
    }

    func testCannotSellLastCopy() {
        var rng = SeededRNG(7)
        var core = GameCore()
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let singleton = core.instances.first(where: { core.count(of: $0.cardId) == 1 }) {
            XCTAssertNil(core.sell(instanceId: singleton.id), "cannot sell the only copy of a card")
        }
    }

    func testSellingADuplicateAddsCash() {
        var rng = SeededRNG(7)
        var core = GameCore()
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let dup = core.sellableInstances.first {
            let before = core.cash
            let v = core.sell(instanceId: dup.id)
            XCTAssertNotNil(v)
            XCTAssertGreaterThan(core.cash, before)
        }
    }

    func testGradingProducesAValidPSAGrade() {
        var rng = SeededRNG(7)
        var core = GameCore()
        core.cash += 50
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let gradeable = core.instances.first(where: { $0.card.rarity.canBeGraded && $0.grade == nil }) {
            let res = core.grade(instanceId: gradeable.id, using: &rng)
            XCTAssertNotNil(res)
            if let res { XCTAssertTrue((1...10).contains(res.grade)) }
        }
    }

    func testGameOverThresholds() {
        var broke = GameCore()
        broke.cash = 0
        broke.instances = [CardInstance(cardId: "S1-001")]
        XCTAssertTrue(broke.isGameOver, "broke with only last-copies should be game over")
        broke.instances.append(CardInstance(cardId: "S1-001"))
        XCTAssertTrue(broke.isGameOver,
                      "a duplicate worth pennies can't buy a pack, so the run is still over")

        // A duplicate only keeps the run alive if it actually bridges the gap.
        var bridged = GameCore()
        bridged.cash = Economy.cheapestPackPrice - 0.10
        bridged.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001")]
        XCTAssertFalse(bridged.isGameOver,
                       "a duplicate that covers the shortfall should keep the run alive")

        // Grading is the other way out: a raw rare sells for $2.21, but a lucky
        // roll on a $2 grade makes it worth far more than the cheapest pack.
        var gradeable = GameCore()
        gradeable.cash = 2
        gradeable.instances = [CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003")]
        XCTAssertLessThan(gradeable.cash + (gradeable.instances[0].sellValue), Economy.cheapestPackPrice,
                          "selling that rare raw shouldn't be enough on its own")
        XCTAssertFalse(gradeable.isGameOver, "a gradeable dupe you can afford to grade is a way out")
        gradeable.cash = Economy.gradeFee(set: 1) - 0.01   // can't even pay the grading fee
        XCTAssertTrue(gradeable.isGameOver, "no way out once the grading fee is out of reach too")

        XCTAssertEqual(Economy.cheapestPackPrice, 10, "cheapest pack price should be $10")
        var edge = GameCore()
        edge.instances = [CardInstance(cardId: "S1-001")]
        edge.cash = Economy.cheapestPackPrice - 0.01
        XCTAssertTrue(edge.isGameOver, "just under cheapest pack price with no sellables = game over")
        edge.cash = Economy.cheapestPackPrice
        XCTAssertFalse(edge.isGameOver, "== cheapest pack price should still be in the game")
    }

    func testMaxRaisableCashCountsEachExtraOnce() {
        var core = GameCore()
        core.cash = 0
        core.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"),
                          CardInstance(cardId: "S1-001")]
        // Three copies means two are actually sellable — the last one can never go.
        XCTAssertEqual(core.sellableExtras.count, 2)
        XCTAssertEqual(core.maxRaisableCash, 2 * core.instances[0].sellValue, accuracy: 0.001)

        // A lone copy is worth nothing to a player trying to raise cash.
        core.instances = [CardInstance(cardId: "S1-001")]
        core.cash = 5
        XCTAssertTrue(core.sellableExtras.isEmpty)
        XCTAssertEqual(core.maxRaisableCash, 5, accuracy: 0.001)
    }

    func testWinConditionAndBonusPayout() {
        var core = GameCore()
        for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
        let events = core.checkBonuses()
        XCTAssertTrue(core.hasWon, "owning all 250 cards should trigger a win")
        XCTAssertEqual(core.claimedSets.count, 5)
        XCTAssertEqual(core.claimedEvoLines.count, 65)
        XCTAssertEqual(events.count, 70, "65 evolution + 5 set bonuses")
        let expected = 34.0 * (10 + 30 + 75 + 160 + 320)
        XCTAssertEqual(core.cash, 100 + expected, accuracy: 0.01)
        XCTAssertTrue(core.checkBonuses().isEmpty, "bonuses should not be paid twice")
    }

    func testSellDuplicatesKeepsOneOfEach() {
        var core = GameCore()
        core.instances = [
            CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"),
            CardInstance(cardId: "S1-002"),
            CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003"),
        ]
        let ids: Set<String> = ["S1-001", "S1-002", "S1-003"]
        let preview = core.duplicateSummary(of: ids)
        XCTAssertEqual(preview.count, 3, "2×S1-001 + 1×S1-003 duplicates expected")

        let startCash = core.cash
        let uniquesBefore = core.uniqueCount
        let sold = core.sellDuplicates(of: ids)
        XCTAssertEqual(sold.count, 3)
        XCTAssertEqual(sold.proceeds, preview.proceeds, accuracy: 0.001)
        XCTAssertEqual(core.cash, startCash + sold.proceeds, accuracy: 0.001)
        XCTAssertEqual(core.count(of: "S1-001"), 1)
        XCTAssertEqual(core.count(of: "S1-002"), 1)
        XCTAssertEqual(core.count(of: "S1-003"), 1)
        XCTAssertEqual(core.uniqueCount, uniquesBefore, "no unique cards should be lost")
        XCTAssertEqual(core.instances.count, 3)
    }

    func testSellDuplicatesKeepsMostValuableCopy() {
        var core = GameCore()
        var foilCopy = CardInstance(cardId: "S1-050"); foilCopy.foil = true
        core.instances = [CardInstance(cardId: "S1-050"), CardInstance(cardId: "S1-050"), foilCopy]
        _ = core.sellDuplicates(of: ["S1-050"])
        XCTAssertEqual(core.count(of: "S1-050"), 1)
        XCTAssertEqual(core.instances(of: "S1-050").first?.foil, true, "the foil copy should be kept")
    }

    func testPreOwnedSnapshotTracksUniquesBeforePack() {
        var rng = SeededRNG(7)
        var core = GameCore()
        core.cash = 100_000
        let r1 = core.buyPack(set: 1, using: &rng)
        XCTAssertEqual(r1?.preOwnedIds.isEmpty, true, "first pack has nothing pre-owned")
        let ownedAfter1 = core.uniqueOwnedIds
        let r2 = core.buyPack(set: 1, using: &rng)
        XCTAssertEqual(r2?.preOwnedIds, ownedAfter1)
        let newInFirst = Set(r1!.pulled.map { $0.cardId }).subtracting(r1!.preOwnedIds)
        XCTAssertFalse(newInFirst.isEmpty, "first pack should yield at least one brand-new card")
        let rb = core.buyBox(set: 1, using: &rng)
        XCTAssertEqual(rb?.preOwnedIds.contains(where: { ownedAfter1.contains($0) }), true)
    }

    func testBoosterBoxYieldsPacksWithGuarantees() {
        var rng = SeededRNG(31)
        var core = GameCore()
        core.cash = 1_000_000
        let ownedBefore = core.instances.count
        guard let results = core.buyBoxPacks(set: 1, using: &rng) else {
            XCTFail("buyBoxPacks should return results for an unlocked, affordable box")
            return
        }
        XCTAssertEqual(results.count, Economy.boxPacks)
        XCTAssertTrue(results.allSatisfy { $0.pulled.count == Economy.packSize })
        XCTAssertTrue(results.allSatisfy { !$0.isBox })

        let totalCards = results.reduce(0) { $0 + $1.pulled.count }
        XCTAssertEqual(core.instances.count, ownedBefore + totalCards, "all box cards ingested up front")

        let ultras = results.flatMap { $0.pulled }.filter { $0.card.rarity == .ultra }.count
        let foils = results.flatMap { $0.pulled }.filter { $0.foil }.count
        XCTAssertGreaterThanOrEqual(ultras, Economy.boxGuaranteeUltras)
        XCTAssertGreaterThanOrEqual(foils, Economy.boxGuaranteeFoils)

        for k in 1..<results.count {
            XCTAssertTrue(results[k].preOwnedIds.isSuperset(of: results[k - 1].preOwnedIds),
                          "preOwnedIds should be monotonic across packs")
            let a = results[k - 1].visibleInstanceIds ?? []
            let b = results[k].visibleInstanceIds ?? []
            XCTAssertTrue(b.isSuperset(of: a) && b.count > a.count,
                          "visibleInstanceIds should strictly grow each pack")
        }
        XCTAssertEqual(results.last?.visibleInstanceIds?.count, core.instances.count,
                       "last pack should see the whole post-box collection")
    }
}

/// Regression coverage for the shop's double-tap bug: `game.buyPack(set:)` and
/// `game.buyBoxPacks(set:)` commit a purchase (charge cash, bump stats, add
/// cards) the instant they're called, so `ShopView` must refuse to start a
/// second purchase while a reveal is still pending/on screen — otherwise a
/// double-tap (or a tap during the cover's slide-in animation) charges the
/// player twice while only ever showing one reveal. The guard itself
/// (`ShopView.attemptPurchase`) is a plain function over `ShopFreeze`/
/// `PendingOpen`, so it's exercised here directly against a real `GameState`
/// without needing a live view.
@MainActor
final class ShopPurchaseGuardTests: XCTestCase {
    var dir: URL!
    var game: GameState!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Fund generously so both a pack and a booster box are affordable
        // (default starting cash is less than one box).
        var core = GameCore()
        core.cash = 10_000
        let store = SaveStore(directory: dir)
        _ = store.save(core)
        game = GameState(store: store)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testSecondPackPurchaseWhileRevealIsPendingIsBlocked() {
        var freeze: ShopFreeze?
        var pending: PendingOpen?
        var buyInvocations = 0

        func attempt() -> Bool {
            ShopView.attemptPurchase(
                freeze: &freeze, pending: &pending,
                freezeSnapshot: ShopFreeze(game),
                buy: { buyInvocations += 1; return game.buyPack(set: 1) },
                makePending: { PendingOpen(content: .pack($0), set: 1) }
            )
        }

        XCTAssertTrue(attempt(), "first purchase should succeed and start a reveal")
        XCTAssertEqual(buyInvocations, 1)
        XCTAssertNotNil(freeze)
        XCTAssertNotNil(pending)
        let cashAfterFirst = game.cash
        let packsAfterFirst = game.stats.packsOpened

        XCTAssertFalse(attempt(), "a purchase while a reveal is pending must be blocked")
        XCTAssertEqual(buyInvocations, 1, "buy() must not be invoked while a reveal is in flight")
        XCTAssertEqual(game.cash, cashAfterFirst, "the player must not be charged twice")
        XCTAssertEqual(game.stats.packsOpened, packsAfterFirst, "packsOpened must not double-increment")

        // Simulate the fullScreenCover finishing its dismissal (both cleared together).
        freeze = nil
        pending = nil
        XCTAssertTrue(attempt(), "a purchase after the reveal is dismissed should succeed normally")
        XCTAssertEqual(buyInvocations, 2)
    }

    func testSecondBoxPurchaseWhileRevealIsPendingIsBlocked() {
        var freeze: ShopFreeze?
        var pending: PendingOpen?
        var buyInvocations = 0

        func attempt() -> Bool {
            ShopView.attemptPurchase(
                freeze: &freeze, pending: &pending,
                freezeSnapshot: ShopFreeze(game),
                buy: { buyInvocations += 1; return game.buyBoxPacks(set: 1) },
                makePending: { PendingOpen(content: .box(results: $0), set: 1) }
            )
        }

        XCTAssertTrue(attempt(), "first box purchase should succeed and start a reveal")
        XCTAssertEqual(buyInvocations, 1)
        let cashAfterFirst = game.cash
        let boxesAfterFirst = game.stats.boxesOpened

        XCTAssertFalse(attempt(), "a box purchase while a reveal is pending must be blocked")
        XCTAssertEqual(buyInvocations, 1, "buy() must not be invoked while a reveal is in flight")
        XCTAssertEqual(game.cash, cashAfterFirst, "the player must not be charged twice for a box")
        XCTAssertEqual(game.stats.boxesOpened, boxesAfterFirst, "boxesOpened must not double-increment")
    }
}

/// Deterministic evidence that the iPad/landscape layout pass doesn't overflow
/// or fail to lay out at the two shapes that matter most: a wide iPad frame
/// (1024×1366pt, portrait iPad Pro 11") and a very short landscape-phone frame
/// (874×402pt, iPhone landscape). `ImageRenderer` only produces an image when
/// SwiftUI successfully lays the view out at the requested size, so a non-nil,
/// correctly-sized result is proof the screen renders (rather than clipping,
/// crashing, or silently producing a zero-size snapshot) at that shape.
@MainActor
final class WideAndShortLayoutRenderTests: XCTestCase {
    var dir: URL!
    var game: GameState!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        game = GameState(store: SaveStore(directory: dir))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func rendersWithoutFailure<V: View>(_ view: V, size: CGSize) -> CGSize? {
        let sized = view.environment(game).frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: sized)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        return renderer.uiImage?.size
    }

    private let ipadSize = CGSize(width: 1024, height: 1366)
    private let landscapePhoneSize = CGSize(width: 874, height: 402)

    func testShopViewRendersAtIPadWidth() {
        XCTAssertEqual(rendersWithoutFailure(ShopView(), size: ipadSize), ipadSize)
    }

    func testCollectionViewRendersAtIPadWidth() {
        XCTAssertEqual(rendersWithoutFailure(CollectionView(), size: ipadSize), ipadSize)
    }

    func testStatsViewRendersAtIPadWidth() {
        XCTAssertEqual(rendersWithoutFailure(StatsView(), size: ipadSize), ipadSize)
    }

    func testCollectionViewRendersAtLandscapePhoneSize() {
        XCTAssertEqual(rendersWithoutFailure(CollectionView(), size: landscapePhoneSize), landscapePhoneSize)
    }

    func testSealedPackViewRendersAtLandscapePhoneSizeWithoutClipping() {
        let view = SealedPackView(set: 1, isBox: true, onOpen: {})
        XCTAssertEqual(rendersWithoutFailure(view, size: landscapePhoneSize), landscapePhoneSize)
    }

    func testRevealingCardViewScalesDownAtLandscapePhoneSize() {
        var rng = SeededRNG(3)
        var core = GameCore()
        guard let result = core.buyPack(set: 1, using: &rng) else {
            XCTFail("expected a pack purchase to succeed")
            return
        }
        let view = RevealingCardView(inst: result.pulled[0], isNew: true, width: 280)
        XCTAssertEqual(rendersWithoutFailure(view, size: landscapePhoneSize), landscapePhoneSize)
    }

    func testWinViewRendersAtIPadWidth() {
        XCTAssertEqual(rendersWithoutFailure(WinView(), size: ipadSize), ipadSize)
    }

    func testLoseViewRendersAtIPadWidth() {
        XCTAssertEqual(rendersWithoutFailure(LoseView(), size: ipadSize), ipadSize)
    }

    func testWelcomeViewRendersAtLandscapePhoneSize() {
        XCTAssertEqual(rendersWithoutFailure(WelcomeView(), size: landscapePhoneSize), landscapePhoneSize)
    }

    /// The reveal used to hang its glow (440pt) and particle field (460pt) off the
    /// same ZStack as the card, in absolute points. On anything narrower than
    /// those the stack overflowed and the hero card landed ~35pt right of centre.
    /// They're a background/overlay now, so the view measures exactly one card.
    func testRevealingCardViewIsExactlyCardSized() {
        var rng = SeededRNG(3)
        var core = GameCore()
        guard let result = core.buyPack(set: 1, using: &rng) else {
            XCTFail("expected a pack purchase to succeed")
            return
        }
        // Slot 6 is always the rare/ultra hit — the pull that carries the effects.
        guard let hit = result.pulled.last else { return XCTFail("empty pack") }
        XCTAssertTrue(hit.card.rarity == .rare || hit.card.rarity == .ultra)

        let width: CGFloat = 280
        let renderer = ImageRenderer(content: RevealingCardView(inst: hit, isNew: true, width: width))
        renderer.proposedSize = ProposedViewSize(width: 390, height: 700)   // iPhone 14
        renderer.scale = 1
        XCTAssertEqual(renderer.uiImage?.size, CGSize(width: width, height: width * 1.4))
    }

    /// There's little enough on the intro that nobody should have to scroll to
    /// find the button that starts the game, so check the green CTA actually
    /// lands on screen across the phone sizes people are playing on.
    func testWelcomeViewShowsStartButtonWithoutScrolling() {
        let devices: [(String, CGSize)] = [
            ("iPhone 14", CGSize(width: 390, height: 763)),
            ("iPhone 16/17", CGSize(width: 393, height: 759)),
            ("iPhone 17 Pro", CGSize(width: 402, height: 795)),
            ("iPhone 17 Pro Max", CGSize(width: 440, height: 874)),
            ("iPad 11-inch", CGSize(width: 834, height: 1150)),
        ]
        for (name, size) in devices {
            let renderer = ImageRenderer(content: WelcomeView().environment(game))
            renderer.proposedSize = ProposedViewSize(size)
            renderer.scale = 1
            guard let image = renderer.uiImage else {
                XCTFail("\(name): welcome screen failed to render")
                continue
            }
            XCTAssertTrue(containsActionGreen(image, bottomFraction: 0.22),
                          "\(name): 'Start Collecting' should be visible without scrolling")
        }
    }

    /// Looks for the money-green of the primary button in the bottom slice of a
    /// rendered screen.
    private func containsActionGreen(_ image: UIImage, bottomFraction: CGFloat) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for y in Int(CGFloat(h) * (1 - bottomFraction))..<h {
            for x in stride(from: 0, to: w, by: 4) {
                let i = (y * w + x) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                if g > 150, g > r + 45, g > b + 35 { return true }
            }
        }
        return false
    }

    /// The evolution line on a card's detail sheet draws each stage's shipped
    /// illustration, so every card needs one in the asset catalogue.
    func testEveryCardHasShippedArt() {
        let missing = CardDatabase.all.filter { UIImage(named: $0.id) == nil }
        XCTAssertTrue(missing.isEmpty, "cards without art: \(missing.prefix(5).map(\.id))")
    }
}
