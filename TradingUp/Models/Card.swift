import Foundation

// MARK: - Rarity

enum Rarity: String, Codable, CaseIterable, Hashable {
    case common, uncommon, rare, ultra

    var display: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .ultra: return "Ultra Rare"
        }
    }

    /// Sort order low → high.
    var order: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .ultra: return 3
        }
    }

    /// Any card can be graded, regardless of rarity.
    var canBeGraded: Bool { true }
}

// MARK: - Element

enum Element: String, Codable, CaseIterable, Hashable {
    case fire, rock, water, grass, electric, shadow

    var display: String { rawValue.capitalized }

    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .rock: return "🪨"
        case .water: return "💧"
        case .grass: return "🌿"
        case .electric: return "⚡"
        case .shadow: return "🌑"
        }
    }
}

// MARK: - Card (static catalogue entry)

struct Card: Identifiable, Codable, Hashable {
    let id: String
    let set: Int
    let number: Int
    let name: String
    let element: Element
    let rarity: Rarity
    let lineId: String
    let stage: Int
    let stageCount: Int
    let evolvesFromId: String?
    let evolvesToId: String?
    let baseValue: Double
    let flavor: String

    /// Stand-in for a card id that is no longer in the catalogue — e.g. a save
    /// written before a card was renamed, renumbered, or retired. Saves are
    /// sanitized on load (`GameCore.sanitized()`), so this should be unreachable
    /// in practice; it exists so a stale id degrades to a worthless placeholder
    /// instead of crashing the app on launch.
    static func unknown(id: String) -> Card {
        Card(id: id, set: 0, number: 0, name: "Unknown Card", element: .shadow,
             rarity: .common, lineId: "unknown", stage: 1, stageCount: 1,
             evolvesFromId: nil, evolvesToId: nil, baseValue: 0, flavor: "")
    }
}

// MARK: - Card database

/// `all` is provided by the auto-generated `Generated/CardData.swift`.
enum CardDatabase {
    static let setCount = 5
    static let setNames = ["Emberfall", "Tidecaller", "Verdspire", "Voltcrest", "Umbral Reach"]
    static func setName(_ set: Int) -> String {
        (set >= 1 && set <= setNames.count) ? setNames[set - 1] : "Set \(set)"
    }

    static let byId: [String: Card] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Whether `id` still exists in the shipped catalogue. Used to sanitize saves
    /// written against an older card list.
    static func exists(_ id: String) -> Bool { byId[id] != nil }

    private static let bySet: [Int: [Card]] =
        Dictionary(grouping: all, by: { $0.set }).mapValues { $0.sorted { $0.number < $1.number } }

    static func cards(inSet set: Int) -> [Card] { bySet[set] ?? [] }

    static func card(_ id: String) -> Card? { byId[id] }

    /// All multi-stage evolution lines, keyed by lineId, each sorted by stage.
    static let evolutionLines: [String: [Card]] = {
        Dictionary(grouping: all.filter { $0.stageCount > 1 }, by: { $0.lineId })
            .mapValues { $0.sorted { $0.stage < $1.stage } }
    }()

    /// How many multi-stage evolution lines exist in the shipped catalogue.
    static var evolutionLineCount: Int { evolutionLines.count }

    /// The full chain a card belongs to (length 1 for singles), sorted by stage.
    static func line(_ lineId: String) -> [Card] {
        (Dictionary(grouping: all, by: { $0.lineId })[lineId] ?? []).sorted { $0.stage < $1.stage }
    }
}
