import Foundation

/// Observable wrapper around the pure `ChaseCore` (The Chase, v2). Owns
/// randomness and persistence so SwiftUI views stay declarative; every mutation
/// funnels through here and autosaves, exactly like v1's `GameState`.
@Observable
@MainActor
final class ChaseState {
    private(set) var core: ChaseCore

    /// Set when the last load didn't go cleanly — a quarantined save, or the
    /// one-time 2.0 reset — so the UI can explain rather than silently reset.
    private(set) var loadIssue: ChaseLoadIssue?

    /// The recap of the Hunt that just ended (win or bust), held so the UI can
    /// present a summary sheet before returning to the menu. Cleared on dismiss.
    private(set) var lastSummary: HuntSummary?

    /// The three Grails currently offered at the Guild. Generated once when the
    /// player opens New Run so the choice is stable while they deliberate.
    private(set) var pendingGrails: [Grail] = []

    private var rng = AppRNG()
    private let store: ChaseSaveStore

    init(store: ChaseSaveStore = ChaseSaveStore()) {
        self.store = store
        let (loaded, issue) = store.load()
        core = loaded ?? ChaseCore()
        loadIssue = issue
        if issue != nil { store.save(core) }
    }

    #if DEBUG
    /// Test seam: build a state around an explicit core, bypassing disk.
    init(core: ChaseCore, store: ChaseSaveStore) {
        self.store = store
        self.core = core
        self.loadIssue = nil
    }
    #endif

    // MARK: Read-through conveniences

    var meta: MetaState { core.meta }
    var run: RunState? { core.run }
    var hasActiveRun: Bool { core.run != nil }
    var renown: Double { core.meta.renown }
    var binderUnique: Int { core.meta.binderUnique }
    var binderCompletion: Double { core.meta.binderCompletion }
    var totalCards: Int { CardDatabase.all.count }

    // MARK: Guild / New Run

    /// Roll a fresh set of three Grails to choose from (Easy / Medium / Hard).
    func rollGrails() { pendingGrails = core.grailOffers(using: &rng) }

    func canAffordUpgrade(_ u: GuildUpgrade) -> Bool {
        guard let cost = core.meta.upgradeCost(u) else { return false }
        return core.meta.renown >= cost
    }

    @discardableResult
    func purchaseUpgrade(_ u: GuildUpgrade) -> Bool {
        let ok = core.meta.purchase(u)
        if ok { save() }
        return ok
    }

    func startHunt(grail: Grail, trainer: TrainerKind) {
        core.startHunt(grail: grail, trainer: trainer, using: &rng)
        pendingGrails = []
        save()
    }

    // MARK: Working a Lead

    @discardableResult
    func ripPack(set: Int) -> [CardInstance]? {
        let r = core.ripPack(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    @discardableResult
    func sell(_ id: UUID) -> Double? {
        let v = core.sell(instanceId: id)
        if v != nil { save() }
        return v
    }

    @discardableResult
    func sellDuplicates() -> (count: Int, proceeds: Double) {
        let r = core.sellDuplicates()
        if r.count > 0 { save() }
        return r
    }

    @discardableResult
    func grade(_ id: UUID) -> Int? {
        let r = core.grade(instanceId: id, using: &rng)
        if r != nil { save() }
        return r
    }

    @discardableResult
    func useItem(_ kind: ItemKind, target: UUID? = nil) -> Bool {
        let ok = core.useItem(kind, targetInstanceId: target, using: &rng)
        if ok { save() }
        return ok
    }

    // MARK: Phase transitions

    func askSatisfied() -> Bool { core.askSatisfied() }
    func canLandGrail() -> Bool { core.canLandGrail() }
    var hardBust: Bool { core.hardBust }

    @discardableResult
    func runDownLead() -> Bool {
        let ok = core.runDownLead(using: &rng)
        if ok { save() }
        return ok
    }

    @discardableResult
    func pickDraft(_ id: UUID) -> Bool {
        let ok = core.pickDraft(id: id, using: &rng)
        if ok { save() }
        return ok
    }

    func rerollCost() -> Double { core.currentRerollCost() }

    @discardableResult
    func bazaarBuy(_ kind: ItemKind) -> Bool {
        let ok = core.bazaarBuy(kind)
        if ok { save() }
        return ok
    }

    @discardableResult
    func rerollBazaar() -> Bool {
        let ok = core.rerollBazaar(using: &rng)
        if ok { save() }
        return ok
    }

    @discardableResult
    func leaveBazaar() -> Bool {
        let ok = core.leaveBazaar()
        if ok { save() }
        return ok
    }

    @discardableResult
    func chooseRoute(_ id: UUID) -> Bool {
        let ok = core.chooseRoute(optionId: id, using: &rng)
        if ok { save() }
        return ok
    }

    // MARK: Ending

    func landGrail() {
        if let summary = core.landGrail() { lastSummary = summary; save() }
    }

    func giveUp() {
        lastSummary = core.giveUp()
        save()
    }

    func dismissSummary() { lastSummary = nil }
    func dismissLoadIssue() { loadIssue = nil }

    /// Wipe all progress — a fresh career. Used by Settings.
    func resetEverything() {
        core = ChaseCore()
        lastSummary = nil
        save()
    }

    // MARK: Grade / sell previews (for button labels)

    func gradeFee(for inst: CardInstance) -> Double { core.gradeFeeNow(set: inst.card.set) }
    func gradingIsFree() -> Bool { core.gradingIsFree() }
    func sellPreview(_ inst: CardInstance) -> Double { core.sellPreview(inst) }

    private func save() { store.save(core) }
}
