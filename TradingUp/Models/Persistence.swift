import Foundation

// MARK: - On-disk format

/// On-disk save wrapper. The version tag lets a future build detect and migrate
/// an older payload instead of guessing — `GameCore` itself decodes leniently,
/// so additive changes need no migration, but a structural change (e.g. splitting
/// run vs. lifetime stats) can branch on this.
struct SaveFile: Codable {
    /// Bump whenever the payload changes shape in a way `GameCore.init(from:)`
    /// can't absorb on its own.
    static let currentVersion = 1

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
    /// The save loaded, but referenced cards no longer in the catalogue.
    case droppedUnknownCards(count: Int)

    var title: String {
        switch self {
        case .unreadable:          return "Couldn't load your save"
        case .droppedUnknownCards: return "Collection updated"
        }
    }

    var message: String {
        switch self {
        case .unreadable(let name):
            return "Your saved game couldn't be read, so you're starting fresh. The old file wasn't deleted — it's kept as \(name) in the app's Documents folder."
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
    let url: URL

    init(directory: URL? = nil, fileName: String = "tradingup_save.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
    }

    /// Load the save, tolerating both the versioned envelope and the original
    /// bare-`GameCore` format. A file that can't be decoded at all is *moved
    /// aside*, never discarded, so a bug or a bad migration can't silently erase
    /// a player's collection.
    func load() -> (core: GameCore?, issue: SaveLoadIssue?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }

        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode(SaveFile.self, from: data))?.core
            ?? (try? decoder.decode(GameCore.self, from: data))   // pre-envelope saves

        guard let decoded else { return (nil, .unreadable(quarantinedAs: quarantine())) }

        let (clean, dropped) = decoded.sanitized()
        return (clean, dropped > 0 ? .droppedUnknownCards(count: dropped) : nil)
    }

    @discardableResult
    func save(_ core: GameCore) -> Bool {
        guard let data = try? JSONEncoder().encode(SaveFile(core: core)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Move an undecodable save out of the way and return its new file name.
    private func quarantine() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp)")
            .appendingPathExtension("json")
        try? FileManager.default.moveItem(at: url, to: dest)
        return dest.lastPathComponent
    }
}
