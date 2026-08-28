import Foundation

// MARK: - On-disk format

/// On-disk wrapper for `GauntletProgress`, versioned exactly like `SaveFile` and
/// `BinderFile` so a future build can migrate an older payload instead of
/// guessing. `GauntletProgress` itself decodes leniently, so additive changes
/// need no migration.
struct GauntletProgressFile: Codable {
    /// Bump only when the payload changes shape in a way
    /// `GauntletProgress.init(from:)` can't absorb on its own.
    static let currentVersion = 1

    var schemaVersion: Int
    var progress: GauntletProgress

    init(progress: GauntletProgress, schemaVersion: Int = GauntletProgressFile.currentVersion) {
        self.schemaVersion = schemaVersion
        self.progress = progress
    }
}

// MARK: - Store

/// Reads and writes Gauntlet meta progression to its own file, kept separate from
/// the per-run `SaveStore` and the `BinderStore` because it, like the Binder,
/// deliberately outlives any single run.
///
/// It mirrors `BinderStore` exactly, including its most important property: it
/// **never deletes anything on a read failure**. An unreadable or newer-schema
/// file just yields fresh progress (Easy unlocked, every Trainer at level 0)
/// while the old bytes stay on disk untouched until the next successful save — so
/// a transient decode hiccup can't wipe a player's unlocked tiers or Trainer XP.
struct GauntletProgressStore {
    /// Just enough of the envelope to decide how to decode the rest.
    private struct SchemaProbe: Decodable { let schemaVersion: Int }

    let url: URL

    init(directory: URL? = nil, fileName: String = "tradingup_gauntlet.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
    }

    /// Load progress. A missing file is the normal first-launch case and yields
    /// fresh progress with no error. A file written by a *newer* schema than this
    /// build understands is left on disk and reported fresh, so an older build
    /// can't truncate newer progress by decoding it leniently and saving over it.
    func load() -> GauntletProgress {
        guard let data = try? Data(contentsOf: url) else { return GauntletProgress() }

        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(SchemaProbe.self, from: data),
           probe.schemaVersion > GauntletProgressFile.currentVersion {
            return GauntletProgress()
        }

        guard var progress = (try? decoder.decode(GauntletProgressFile.self, from: data))?.progress else {
            return GauntletProgress()
        }
        progress.sanitize()
        return progress
    }

    /// Whether it's safe to overwrite the file. A file written by a newer schema
    /// version must never be clobbered by this (older) build, or the newer fields
    /// would be lost for good.
    func canSave() -> Bool {
        guard let data = try? Data(contentsOf: url),
              let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data) else {
            return true   // no file, or a legacy/unreadable one — safe to write
        }
        return probe.schemaVersion <= GauntletProgressFile.currentVersion
    }

    @discardableResult
    func save(_ progress: GauntletProgress) -> Bool {
        guard canSave(),
              let data = try? JSONEncoder().encode(GauntletProgressFile(progress: progress)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
