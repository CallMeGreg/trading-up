import Foundation

// MARK: - On-disk format

/// On-disk wrapper for the Binder, versioned exactly like `SaveFile` so a future
/// build can migrate an older payload instead of guessing. `Binder` itself
/// decodes leniently, so additive changes need no migration.
struct BinderFile: Codable {
    /// Bump only when the payload changes shape in a way `Binder.init(from:)`
    /// can't absorb on its own.
    static let currentVersion = 1

    var schemaVersion: Int
    var binder: Binder

    init(binder: Binder, schemaVersion: Int = BinderFile.currentVersion) {
        self.schemaVersion = schemaVersion
        self.binder = binder
    }
}

// MARK: - Store

/// Reads and writes the Binder to its own file, kept separate from the per-run
/// `SaveStore` because the Binder deliberately outlives the run: a `newGame()`
/// wipes the save, but the all-time showcase persists.
///
/// It mirrors `SaveStore`'s shape (a versioned envelope, atomic writes) but stays
/// deliberately simpler about failure: the Binder is a derived-ish trophy record,
/// so an unreadable or newer-schema file just yields an empty binder rather than
/// quarantining. Crucially it does *not* delete anything on a read failure — the
/// old bytes stay on disk untouched until the next successful save — so a
/// transient decode hiccup can't silently erase a player's greatest hits.
struct BinderStore {
    /// Just enough of the envelope to decide how to decode the rest.
    private struct SchemaProbe: Decodable { let schemaVersion: Int }

    let url: URL

    init(directory: URL? = nil, fileName: String = "tradingup_binder.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
    }

    /// Load the binder. A missing file is the normal first-launch case and yields
    /// an empty binder with no error. A file written by a *newer* schema than this
    /// build understands is left on disk and reported empty, so an older build
    /// can't truncate a newer binder by decoding it leniently and saving over it.
    func load() -> Binder {
        guard let data = try? Data(contentsOf: url) else { return Binder() }

        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(SchemaProbe.self, from: data),
           probe.schemaVersion > BinderFile.currentVersion {
            // From a newer build — refuse to load rather than silently drop
            // whatever fields that version added. The bytes stay put.
            return Binder()
        }

        guard var binder = (try? decoder.decode(BinderFile.self, from: data))?.binder else {
            return Binder()
        }
        binder.sanitize()
        return binder
    }

    /// Whether it's safe to overwrite the file on disk. A binder file written by a
    /// newer schema version must never be clobbered by this (older) build, or the
    /// newer fields would be lost for good.
    func canSave() -> Bool {
        guard let data = try? Data(contentsOf: url),
              let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data) else {
            return true   // no file, or a legacy/unreadable one — safe to write
        }
        return probe.schemaVersion <= BinderFile.currentVersion
    }

    @discardableResult
    func save(_ binder: Binder) -> Bool {
        guard canSave(),
              let data = try? JSONEncoder().encode(BinderFile(binder: binder)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
