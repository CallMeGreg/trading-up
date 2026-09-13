import Foundation

@Observable
@MainActor
final class PackOpeningPreferences {
    static let shared = PackOpeningPreferences()
    static let tapToOpenKey = "tradingup_tap_to_open_packs"
    static let autoOpenKey = "tradingup_auto_open_packs"

    @ObservationIgnored private let defaults: UserDefaults

    var tapToOpenPacks: Bool {
        didSet { defaults.set(tapToOpenPacks, forKey: Self.tapToOpenKey) }
    }

    var autoOpenPacks: Bool {
        didSet { defaults.set(autoOpenPacks, forKey: Self.autoOpenKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tapToOpenPacks = defaults.bool(forKey: Self.tapToOpenKey)
        autoOpenPacks = defaults.bool(forKey: Self.autoOpenKey)
    }
}
