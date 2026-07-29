import Foundation

// MARK: - On-disk format

/// On-disk save wrapper. The version tag lets a future build detect and migrate
/// an older payload instead of guessing — `GameCore` itself decodes leniently,
/// so additive changes need no migration, but a structural change (e.g. splitting
/// run vs. lifetime stats) can branch on this.
struct SaveFile: Codable {
    /// Bump whenever the payload changes shape in a way `GameCore.init(from:)`
    /// can't absorb on its own.
    ///
    /// v2: split lifetime stats out of the per-run `Stats` (see `LifetimeStats`
    /// on `GameCore`). v1 saves have no `lifetime` key at all; `SaveStore.load()`
    /// branches on `schemaVersion` to migrate them explicitly.
    static let currentVersion = 2

    var schemaVersion: Int
    var core: GameCore

    init(core: GameCore, schemaVersion: Int = SaveFile.currentVersion) {
        self.schemaVersion = schemaVersion
        self.core = core
    }
}

// MARK: - Load outcome

/// Why a save didn't load cleanly, when it didn't.
enum SaveLoadIssue: Equatable {
    /// The file existed but couldn't be decoded. It was moved aside (never
    /// deleted); the payload is the new file name.
    case unreadable(quarantinedAs: String)
    /// The file was written by a newer schema version than this build knows
    /// about. Decoding it leniently would silently drop whatever fields that
    /// future version added — the very next autosave would then permanently
    /// overwrite it with that data gone. So it's quarantined instead, exactly
    /// like an unreadable file: moved aside (never deleted), recoverable by
    /// updating the app.
    case fromNewerVersion(quarantinedAs: String)
    /// The save loaded, but referenced cards no longer in the catalogue.
    case droppedUnknownCards(count: Int)

    var title: String {
        switch self {
        case .unreadable:          return "Couldn't load your save"
        case .fromNewerVersion:    return "Update needed to load your save"
        case .droppedUnknownCards: return "Collection updated"
        }
    }

    var message: String {
        switch self {
        case .unreadable(let name):
            return "Your saved game couldn't be read, so you're starting fresh. The old file wasn't deleted — it's kept as \(name) in the app's Documents folder."
        case .fromNewerVersion(let name):
            return "This save was made by a newer version of Trading Up, so you're starting fresh until you update. Your save wasn't deleted — it's kept as \(name) in the app's Documents folder, and will load once you're back on the version that made it."
        case .droppedUnknownCards(let count):
            let plural = count == 1
            return "\(count) card\(plural ? "" : "s") in your collection \(plural ? "is" : "are") no longer part of this version and \(plural ? "was" : "were") removed. Everything else is intact."
        }
    }
}

// MARK: - Store

/// Reads and writes the game save. Kept separate from `GameState` so the file
/// handling — versioning, legacy formats, corrupt-file quarantine — stays pure,
/// testable, and out of the observable object.
struct SaveStore {
    /// Just enough of the envelope to decide how to decode the rest.
    private struct SchemaProbe: Decodable { let schemaVersion: Int }

    let url: URL

    init(directory: URL? = nil, fileName: String = "tradingup_save.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
    }

    /// Load the save, tolerating the v2 envelope, the v1 envelope, and the
    /// original bare-`GameCore` format. A file that can't be decoded at all,
    /// or was written by a schema version newer than this build knows about,
    /// is *moved aside*, never discarded, so a bug, a bad migration, or an
    /// old build opening a newer save can't silently erase — or silently
    /// truncate — a player's collection.
    func load() -> (core: GameCore?, issue: SaveLoadIssue?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }

        let decoder = JSONDecoder()
        let decoded: GameCore?
        if let probe = try? decoder.decode(SchemaProbe.self, from: data) {
            switch probe.schemaVersion {
            case let v where v > SaveFile.currentVersion:
                // A save from a newer build. Lenient decoding is exactly right
                // for *older* saves (missing keys default sensibly) and
                // exactly wrong for *newer* ones (whatever fields that future
                // version added would just be dropped, invisibly, and the
                // next autosave would make that loss permanent). Refuse to
                // load it at all rather than quietly truncating it.
                return (nil, .fromNewerVersion(quarantinedAs: quarantine()))
            case 1:
                decoded = migrateV1((try? decoder.decode(SaveFile.self, from: data))?.core)
            default:
                // Current version — decode as-is; `GameCore`'s lenient init
                // absorbs any additive fields within this schema version.
                decoded = (try? decoder.decode(SaveFile.self, from: data))?.core
            }
        } else {
            // No `schemaVersion` key at all: a pre-envelope, bare-`GameCore` save.
            decoded = try? decoder.decode(GameCore.self, from: data)
        }

        guard let decoded else { return (nil, .unreadable(quarantinedAs: quarantine())) }

        let (clean, dropped) = decoded.sanitized()
        return (clean, dropped > 0 ? .droppedUnknownCards(count: dropped) : nil)
    }

    /// v1 -> v2: v1 predates lifetime stats entirely, so there's nothing to
    /// carry over beyond what `GameCore`'s lenient decode already defaults
    /// `lifetime` to (all zero). That's correct, not just convenient: the
    /// player's in-progress run gets folded into that zero lifetime at display
    /// time (`GameCore.lifetimeIncludingCurrentRun`), so their all-time totals
    /// read right immediately, with no data loss. Kept as an explicit branch —
    /// rather than only relying on the lenient decode — so the next schema
    /// change has a template to extend instead of inventing this from scratch.
    private func migrateV1(_ core: GameCore?) -> GameCore? { core }

    @discardableResult
    func save(_ core: GameCore) -> Bool {
        guard let data = try? JSONEncoder().encode(SaveFile(core: core)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Move an undecodable (or newer-than-this-build) save out of the way and
    /// return its new file name. The timestamp alone isn't unique enough —
    /// two quarantines in the same wall-clock second (e.g. an unreadable save
    /// followed shortly by a newer-schema one) would otherwise collide and
    /// silently fail to move, via the `try?`. A short random suffix keeps
    /// every quarantined name distinct regardless of timing.
    private func quarantine() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let suffix = String(UUID().uuidString.prefix(6))
        let dest = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp)-\(suffix)")
            .appendingPathExtension("json")
        try? FileManager.default.moveItem(at: url, to: dest)
        return dest.lastPathComponent
    }
}
