import Foundation

// MARK: - On-disk format (v3, "The Chase")
//
// The Chase persists a whole different shape (MetaState + an optional live
// RunState) from v1/v2's single `GameCore`, so it lives in its own file
// (`tradingup_chase.json`) with its own envelope. `ChaseCore` decodes leniently,
// so additive fields never need a migration; the version tag guards against a
// *newer* build's save, exactly like v2.

struct ChaseSaveFile: Codable {
    /// v3: the roguelite redesign. v1/v2 saves use `SaveFile`/`tradingup_save.json`
    /// and are migrated once on first 2.0 launch (see `ChaseSaveStore.load`).
    static let currentVersion = 3
    /// The current app major. Bumping it lets `MetaState.lastSeenMajorVersion`
    /// drive a one-time "What's New" for a future major.
    static let currentMajorVersion = 2

    var schemaVersion: Int
    var core: ChaseCore

    init(core: ChaseCore, schemaVersion: Int = ChaseSaveFile.currentVersion) {
        self.schemaVersion = schemaVersion
        self.core = core
    }
}

// MARK: - Load outcome

enum ChaseLoadIssue: Equatable {
    /// The chase save existed but couldn't be decoded. Moved aside, never deleted.
    case unreadable(quarantinedAs: String)
    /// The chase save was written by a newer schema version than this build knows.
    /// Quarantined rather than truncated, exactly like v2.
    case fromNewerVersion(quarantinedAs: String)
    /// First launch of 2.0 over a v1/v2 collection: the old save was quarantined
    /// (never deleted) and your collection was imported into the new Binder. The
    /// UI renders this as the full-screen "Welcome to 2.0 — What's New".
    case resetForNewVersion(previousSaveQuarantinedAs: String)

    var heading: String {
        switch self {
        case .unreadable:          return "Couldn't load your progress"
        case .fromNewerVersion:    return "Update needed to load your progress"
        case .resetForNewVersion:  return "Welcome to Trading Up 2.0"
        }
    }

    var body: String {
        switch self {
        case .unreadable(let name):
            return "Your saved progress couldn't be read, so you're starting fresh. The old file wasn't deleted — it's kept as \(name) in the app's Documents folder."
        case .fromNewerVersion(let name):
            return "This save was made by a newer version of Trading Up, so you're starting fresh until you update. Your save wasn't deleted — it's kept as \(name) in the app's Documents folder."
        case .resetForNewVersion(let name):
            return """
            Trading Up is now a grail-hunter. Each run is a Hunt: pick a Grail, chase it across escalating Leads, rip packs with Energy, and trade up through the Bazaar until you can land it. Win or bust, the best copy of every card you hold is kept forever in your Binder, and you earn Renown to unlock Trainers and Guild upgrades.

            Because the game changed shape, your old collection couldn't carry over as a run — so we've started you fresh and imported the best copy of every card you owned straight into your new Binder. Nothing else transfers. Your previous save wasn't deleted; it's kept as \(name) in the app's Documents folder.
            """
        }
    }
}

// MARK: - Store

/// Reads and writes the Chase save, and performs the one-time 2.0 migration from
/// a v1/v2 collection. Kept separate from the observable layer so file handling —
/// versioning, the corrupt/newer-save quarantine, the reset-and-seed — stays pure
/// and testable. The never-delete contract is preserved: nothing is ever removed,
/// only moved aside.
struct ChaseSaveStore {
    private struct SchemaProbe: Decodable { let schemaVersion: Int }

    let url: URL          // tradingup_chase.json
    let legacyURL: URL    // tradingup_save.json (v1/v2)
    private let directory: URL

    init(directory: URL? = nil,
         fileName: String = "tradingup_chase.json",
         legacyFileName: String = "tradingup_save.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = dir
        url = dir.appendingPathComponent(fileName)
        legacyURL = dir.appendingPathComponent(legacyFileName)
    }

    /// Load order:
    /// 1. A v3 Chase save if present (quarantine a newer/unreadable one).
    /// 2. Otherwise, if a v1/v2 collection exists, run the one-time 2.0 reset:
    ///    seed the Binder from it, quarantine it, write a fresh Chase save, and
    ///    report `.resetForNewVersion` so the UI shows What's New.
    /// 3. Otherwise, a brand-new player: fresh game, no issue.
    func load() -> (core: ChaseCore?, issue: ChaseLoadIssue?) {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let probe = try? decoder.decode(SchemaProbe.self, from: data),
               probe.schemaVersion > ChaseSaveFile.currentVersion {
                return (nil, .fromNewerVersion(quarantinedAs: quarantine(url)))
            }
            guard let file = try? decoder.decode(ChaseSaveFile.self, from: data) else {
                return (nil, .unreadable(quarantinedAs: quarantine(url)))
            }
            return (file.core.sanitizedChase(), nil)
        }

        // No Chase save yet. Migrate a legacy collection if one exists.
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            var core = ChaseCore()
            core.meta.lastSeenMajorVersion = ChaseSaveFile.currentMajorVersion
            // Reuse the v1/v2 loader (handles v1/v2/bare + sanitize). It may itself
            // quarantine a corrupt or newer legacy save, which still preserves it.
            let (legacy, _) = SaveStore(directory: directory).load()
            if let legacy { seedBinder(&core, from: legacy) }
            var name = "your previous save"
            if FileManager.default.fileExists(atPath: legacyURL.path) { name = quarantine(legacyURL) }
            _ = save(core)   // write the fresh Chase save so the reset runs exactly once
            return (core, .resetForNewVersion(previousSaveQuarantinedAs: name))
        }

        return (nil, nil)   // brand-new player — normal onboarding, no reset screen
    }

    /// Import the best copy of every card owned in a v1/v2 collection into the new
    /// Binder. This is the *only* carryover — no cash, no run, no Renown — and the
    /// Binder is read-only, so it can't skew the fresh economy.
    private func seedBinder(_ core: inout ChaseCore, from legacy: GameCore) {
        for inst in legacy.instances { core.meta.deposit(inst) }
    }

    @discardableResult
    func save(_ core: ChaseCore) -> Bool {
        var core = core
        core.meta.lastSeenMajorVersion = ChaseSaveFile.currentMajorVersion
        guard let data = try? JSONEncoder().encode(ChaseSaveFile(core: core)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Move a file aside (never delete) and return its new name. Mirrors
    /// `SaveStore.quarantine`, including the random suffix so two quarantines in
    /// the same second can't collide.
    private func quarantine(_ fileURL: URL) -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = String(UUID().uuidString.prefix(6))
        let dest = fileURL.deletingPathExtension()
            .appendingPathExtension("archived-\(stamp)-\(suffix)")
            .appendingPathExtension("json")
        try? FileManager.default.moveItem(at: fileURL, to: dest)
        return dest.lastPathComponent
    }
}

// MARK: - Sanitize (drop cards that left the catalogue)

extension ChaseCore {
    /// Drop Binder slots and in-run stock referencing card ids no longer shipped,
    /// so a catalogue change can never crash on a stale save.
    func sanitizedChase() -> ChaseCore {
        var c = self
        c.meta.binder = c.meta.binder.filter { CardDatabase.exists($0.key) }
        if var r = c.run {
            r.stock.removeAll { !CardDatabase.exists($0.cardId) }
            c.run = r
        }
        return c
    }
}
