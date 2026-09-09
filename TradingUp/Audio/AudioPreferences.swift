import Foundation
import OSLog

enum AudioLog {
    static let logger = Logger(subsystem: "com.callmegreg.tradingup", category: "Audio")
}

/// Muting remembers the last audible level; moving the slider unmutes it.
@Observable
@MainActor
final class AudioChannelSettings {
    private(set) var rememberedVolume: Double
    private(set) var isMuted: Bool
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var adjustmentStartVolume: Double?
    @ObservationIgnored private let defaults: UserDefaults
    private let volumeKey: String
    private let enabledKey: String

    init(defaults: UserDefaults, volumeKey: String, enabledKey: String,
         defaultVolume: Double, defaultEnabled: Bool) {
        self.defaults = defaults
        self.volumeKey = volumeKey
        self.enabledKey = enabledKey
        let saved = (defaults.object(forKey: volumeKey) as? NSNumber)?.doubleValue
        if let saved, saved.isFinite, saved > 0 {
            rememberedVolume = min(1, saved)
        } else {
            rememberedVolume = defaultVolume
        }
        let enabled = defaults.object(forKey: enabledKey) == nil
            ? defaultEnabled : defaults.bool(forKey: enabledKey)
        isMuted = !enabled || saved == 0
    }

    var volume: Double {
        get { isMuted ? 0 : rememberedVolume }
        set {
            guard newValue.isFinite else {
                AudioLog.logger.error("Rejected a non-finite audio volume")
                return
            }
            let level = min(1, max(0, newValue))
            if level > 0 { rememberedVolume = level }
            isMuted = level == 0
            persist()
        }
    }

    var isEnabled: Bool {
        get { !isMuted }
        set {
            endVolumeAdjustment()
            isMuted = !newValue
            persist()
        }
    }

    func toggleMute() {
        endVolumeAdjustment()
        isMuted.toggle()
        persist()
    }

    func beginVolumeAdjustment() {
        adjustmentStartVolume = adjustmentStartVolume ?? rememberedVolume
    }

    func endVolumeAdjustment() {
        guard let startingVolume = adjustmentStartVolume else { return }
        adjustmentStartVolume = nil
        if isMuted {
            // A drag to zero must not remember the tiny intermediate levels.
            rememberedVolume = startingVolume
            persist()
        }
    }

    private func persist() {
        defaults.set(rememberedVolume, forKey: volumeKey)
        defaults.set(!isMuted, forKey: enabledKey)
        onChange?()
    }
}

@MainActor
final class AudioPreferences {
    static let shared = AudioPreferences()
    let sfx: AudioChannelSettings
    let music: AudioChannelSettings

    init(defaults: UserDefaults = .standard) {
        let legacyEnabled = defaults.object(forKey: "tradingup_sound_enabled") == nil
            || defaults.bool(forKey: "tradingup_sound_enabled")
        if defaults.object(forKey: "tradingup_music_enabled") == nil {
            defaults.set(legacyEnabled, forKey: "tradingup_music_enabled")
        }
        sfx = AudioChannelSettings(defaults: defaults, volumeKey: "tradingup_sfx_volume",
                                   enabledKey: "tradingup_sound_enabled",
                                   defaultVolume: 1, defaultEnabled: true)
        // An existing silent-game preference must not unexpectedly start a new score.
        music = AudioChannelSettings(defaults: defaults, volumeKey: "tradingup_music_volume",
                                     enabledKey: "tradingup_music_enabled",
                                     defaultVolume: 0.28, defaultEnabled: legacyEnabled)
    }
}
