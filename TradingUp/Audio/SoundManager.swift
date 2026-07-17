import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
import Combine

/// Every sound effect the app can play. The raw value is the bundled WAV's file
/// name (see `tools/generate_sfx.py`, which synthesizes all of them).
enum Sound: String, CaseIterable {
    case tap
    case purchase
    case packTear      = "pack_tear"
    case cardWhoosh    = "card_whoosh"
    case revealCommon  = "reveal_common"
    case revealUncommon = "reveal_uncommon"
    case revealRare    = "reveal_rare"
    case revealUltra   = "reveal_ultra"
    case foilShimmer   = "foil_shimmer"
    case coin
    case bonus
    case grade
    case win
    case lose

    /// The reveal sting that matches a pulled card's rarity.
    static func reveal(for rarity: Rarity) -> Sound {
        switch rarity {
        case .common:   return .revealCommon
        case .uncommon: return .revealUncommon
        case .rare:     return .revealRare
        case .ultra:    return .revealUltra
        }
    }

    /// Convenience mirroring `Haptics.play(_:)` so call sites read the same way.
    static func play(_ sound: Sound, volume: Float = 1.0) {
        SoundManager.shared.play(sound, volume: volume)
    }
}

/// Plays the app's bundled sound effects with low latency.
///
/// Design notes:
/// - Uses `AVAudioPlayer` pools (a few players per sound) so a sound can retrigger
///   or overlap without cutting itself off.
/// - Runs on the `.ambient` audio session with `.mixWithOthers`, so the game never
///   interrupts the player's own music and honors the physical mute switch.
/// - Mute state is a user preference persisted in `UserDefaults`, independent of
///   the game save, and published so a settings toggle updates live.
final class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private static let prefKey = "tradingup_sound_enabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.prefKey) }
    }

    #if canImport(AVFoundation)
    private var pools: [Sound: [AVAudioPlayer]] = [:]
    private let poolSize = 3
    private var sessionActivated = false
    #endif

    private init() {
        if UserDefaults.standard.object(forKey: Self.prefKey) == nil {
            isEnabled = true   // sound on by default
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.prefKey)
        }
    }

    /// Warm up the audio session and decode every effect ahead of first use so
    /// the initial pack-open doesn't stutter. Safe to call from app launch.
    func preloadAll() {
        #if canImport(AVFoundation)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for sound in Sound.allCases { _ = self.players(for: sound) }
        }
        #endif
    }

    func play(_ sound: Sound, volume: Float = 1.0) {
        guard isEnabled else { return }
        #if canImport(AVFoundation)
        activateSessionIfNeeded()
        guard let player = availablePlayer(for: sound) else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
        #endif
    }

    // MARK: - Player pool

    #if canImport(AVFoundation)
    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        sessionActivated = true
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    /// Returns a player for `sound` that isn't currently playing, creating the
    /// pool on first request. If every player in the pool is busy, reuses the
    /// oldest so rapid taps still make sound.
    private func availablePlayer(for sound: Sound) -> AVAudioPlayer? {
        let pool = players(for: sound)
        guard !pool.isEmpty else { return nil }
        return pool.first(where: { !$0.isPlaying }) ?? pool.first
    }

    private func players(for sound: Sound) -> [AVAudioPlayer] {
        if let existing = pools[sound] { return existing }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
              let data = try? Data(contentsOf: url) else {
            pools[sound] = []
            return []
        }
        var made: [AVAudioPlayer] = []
        for _ in 0..<poolSize {
            if let p = try? AVAudioPlayer(data: data) {
                p.prepareToPlay()
                made.append(p)
            }
        }
        pools[sound] = made
        return made
    }
    #endif
}
