import Foundation

// MARK: - Resume snapshot

/// The mid-run phases that can be saved and resumed. Only an *active* run — one
/// still ripping a round or standing in the between-round shop — is resumable; the
/// selection, reward, results and lost phases are pre-run or terminal, so they
/// clear the snapshot instead of writing one.
enum GauntletResumePhase: String, Codable {
    case ripping
    case shop
}

/// Everything needed to drop the player back into an in-progress Gauntlet run
/// exactly where they left it. The pure `GauntletRun` carries the round, cash,
/// Showcase and attuned Catalysts; the rest is the small amount of `GauntletState`
/// orchestration around an unresolved pull.
///
/// Deliberately excludes transient flourish (confetti counters, last-outcome
/// flashes) and the RNG — a resumed run simply continues with fresh randomness,
/// since the current pull's cards are already rolled and stored here.
struct GauntletRunSnapshot: Codable {
    var run: GauntletRun
    var phase: GauntletResumePhase
    var pendingCards: [CardInstance]
    var pendingCatalyst: Catalyst?
    var lastRippedSet: Int
    var revealActive: Bool
    var celebratedRound: Int
}

// MARK: - On-disk format

/// Versioned envelope for a resume snapshot, mirroring `GauntletProgressFile` and
/// `SaveFile`. Bump only when the payload changes shape in a way the loader can't
/// absorb; a resume snapshot is transient run state, so a failed decode just drops
/// the resume (the player starts a fresh run) rather than being a data-loss event.
struct GauntletRunFile: Codable {
    static let currentVersion = 1

    var schemaVersion: Int
    var snapshot: GauntletRunSnapshot

    init(snapshot: GauntletRunSnapshot, schemaVersion: Int = GauntletRunFile.currentVersion) {
        self.schemaVersion = schemaVersion
        self.snapshot = snapshot
    }
}

// MARK: - Store

/// Reads and writes the single in-progress Gauntlet run so leaving the mode and
/// coming back **resumes** it instead of discarding it (req 11). Kept separate
/// from the cross-run `GauntletProgressStore` (unlocks/XP) and the shared
/// `BinderStore`, because unlike those it is deliberately short-lived: it is
/// written while a run is active and cleared the moment the run ends.
///
/// Like the other stores it never clobbers a file written by a *newer* schema
/// than this build understands.
struct GauntletRunStore {
    private struct SchemaProbe: Decodable { let schemaVersion: Int }

    let url: URL

    init(directory: URL? = nil, fileName: String = "tradingup_gauntlet_run.json") {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent(fileName)
    }

    /// The saved in-progress run, or `nil` when there's nothing to resume (no
    /// file, an unreadable one, or one written by a newer schema).
    func load() -> GauntletRunSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        if let probe = try? decoder.decode(SchemaProbe.self, from: data),
           probe.schemaVersion > GauntletRunFile.currentVersion {
            return nil
        }
        return (try? decoder.decode(GauntletRunFile.self, from: data))?.snapshot
    }

    /// Whether it's safe to overwrite the file — never true for a newer-schema file.
    func canSave() -> Bool {
        guard let data = try? Data(contentsOf: url),
              let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data) else {
            return true
        }
        return probe.schemaVersion <= GauntletRunFile.currentVersion
    }

    @discardableResult
    func save(_ snapshot: GauntletRunSnapshot) -> Bool {
        guard canSave(),
              let data = try? JSONEncoder().encode(GauntletRunFile(snapshot: snapshot)) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Drop the saved run. Called whenever a run ends or is reset, so a finished
    /// or abandoned run never resurrects on the next visit. Safe when no file
    /// exists. A newer-schema file is left untouched.
    func clear() {
        guard canSave() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Whether a resumable run is on disk right now (used by Settings to show the
    /// "Reset Gauntlet Run" control only when there's something to reset).
    var hasSavedRun: Bool { load() != nil }
}
