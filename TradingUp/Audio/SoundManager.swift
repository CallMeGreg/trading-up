import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Every sound effect the app can play. The raw value is the bundled WAV's file
/// name (see `tools/generate_sfx.py`, which synthesizes all of them).
enum Sound: String, CaseIterable {
    case purchase
    case foilShimmer   = "foil_shimmer"
    case coin

    /// Convenience mirroring `Haptics.play(_:)` so call sites read the same way.
    @MainActor
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
@Observable
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private static let prefKey = "tradingup_sound_enabled"

    var isEnabled: Bool {
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
    ///
    /// The file reads happen off the main actor; only the resulting pool of
    /// `AVAudioPlayer`s is installed back on the main actor, which is where
    /// `pools` is otherwise read and written from `play(_:volume:)`.
    func preloadAll() {
        #if canImport(AVFoundation)
        Task.detached(priority: .utility) { [weak self] in
            guard self != nil else { return }
            var decoded: [Sound: Data] = [:]
            for sound in Sound.allCases {
                guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
                      let data = try? Data(contentsOf: url) else { continue }
                decoded[sound] = data
            }
            await self?.installPools(from: decoded)
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
        return makePool(from: data, into: sound)
    }

    /// Installs a batch of preloaded pools (called back on the main actor
    /// from `preloadAll()`). Sounds that already have a pool are skipped.
    private func installPools(from decoded: [Sound: Data]) {
        for (sound, data) in decoded where pools[sound] == nil {
            _ = makePool(from: data, into: sound)
        }
    }

    @discardableResult
    private func makePool(from data: Data, into sound: Sound) -> [AVAudioPlayer] {
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
