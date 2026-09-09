import Foundation
import AVFoundation

/// Pooled Studio effects and independently mixed, looping mode music.
/// Ambient playback honors the mute switch and never interrupts the player's music.
@Observable
@MainActor
final class SoundManager {
    static let shared = SoundManager()
    let preferences = AudioPreferences.shared
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var effectGeneration = 0

    private final class Voice {
        let player: AVAudioPlayer
        var gain: Float = 1
        var startedAt: TimeInterval = 0
        init(_ player: AVAudioPlayer) { self.player = player }
    }

    @ObservationIgnored private var pools: [Sound: [Voice]] = [:]
    @ObservationIgnored private var cursors: [Sound: Int] = [:]
    @ObservationIgnored private var lastPlayed: [Sound: TimeInterval] = [:]
    @ObservationIgnored private var musicPlayers: [Music: AVAudioPlayer] = [:]
    @ObservationIgnored private var fadeTasks: [Music: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var selectedMusic: Music?
    private var applicationActive = true
    private var interrupted = false
    private var musicMayResume = true
    private var sessionConfigured = false
    private var sessionActivated = false
    private var celebrationUntil: TimeInterval = 0

    private var hardwarePlaybackAllowed: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["TU_AUDIO_DISABLED"] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
        #else
        return true
        #endif
    }

    var isEnabled: Bool {
        get { preferences.sfx.isEnabled }
        set { preferences.sfx.isEnabled = newValue }
    }

    private init() {
        preferences.sfx.onChange = { [weak self] in self?.updateEffectVolumes() }
        preferences.music.onChange = { [weak self] in
            self?.musicMayResume = true
            self?.refreshMusic()
        }
        observeAudioSession()
    }

    func preloadAll() {
        configureSession()
        Task.detached(priority: .utility) { [weak self] in
            var effects: [Sound: [Data]] = [:]
            for sound in Sound.allCases {
                let data = sound.resourceNames.compactMap { Self.readAsset($0, extension: "wav") }
                if data.count == sound.resourceNames.count { effects[sound] = data }
            }
            var tracks: [Music: Data] = [:]
            for music in Music.allCases {
                tracks[music] = Self.readAsset(music.rawValue, extension: "m4a")
            }
            await self?.install(effects: effects, tracks: tracks)
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard volume.isFinite else {
            AudioLog.logger.error("Rejected a non-finite effect gain")
            return
        }
        guard applicationActive, !interrupted, preferences.sfx.volume > 0,
              volume > 0, hardwarePlaybackAllowed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[sound], now - last < 0.035 { return }
        guard activateSession(), let voice = nextVoice(for: sound) else { return }
        lastPlayed[sound] = now
        voice.gain = min(1, volume)
        if now < celebrationUntil, !sound.isCelebration, sound != .foilShimmer {
            voice.gain *= 0.45
        }
        voice.player.volume = voice.gain * Float(preferences.sfx.volume)
        voice.player.currentTime = 0
        voice.startedAt = now
        if voice.player.play() {
            if sound.isCelebration { celebrationUntil = now + voice.player.duration }
        } else {
            report("Could not play sound effect \(sound.rawValue).")
        }
    }

    func playMusic(_ music: Music) {
        selectedMusic = music
        musicMayResume = true
        refreshMusic()
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if !active {
            stopEffects()
            pauseMusic()
            #if os(iOS)
            if sessionActivated {
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    AudioLog.logger.error("Could not deactivate audio: \(error.localizedDescription)")
                }
            }
            #endif
            sessionActivated = false
        } else {
            refreshMusic()
        }
    }

    private func install(effects: [Sound: [Data]], tracks: [Music: Data]) {
        for (sound, data) in effects where pools[sound] == nil {
            pools[sound] = makeVoices(data)
        }
        for (music, data) in tracks where musicPlayers[music] == nil {
            musicPlayers[music] = makeMusicPlayer(data)
        }
        refreshMusic()
    }

    private nonisolated static func readAsset(_ name: String, extension ext: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            AudioLog.logger.error("Missing bundled audio: \(name).\(ext)")
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            AudioLog.logger.error("Could not read \(name).\(ext): \(error.localizedDescription)")
            return nil
        }
    }

    private func makeVoices(_ data: [Data]) -> [Voice] {
        guard !data.isEmpty else {
            report("A sound effect has no audio data.")
            return []
        }
        var voices: [Voice] = []
        for index in 0..<3 {
            do {
                let player = try AVAudioPlayer(data: data[index % data.count])
                player.prepareToPlay()
                voices.append(Voice(player))
            } catch {
                report("Could not decode a sound effect: \(error.localizedDescription)")
            }
        }
        return voices
    }

    private func nextVoice(for sound: Sound) -> Voice? {
        if pools[sound] == nil {
            let data = sound.resourceNames.compactMap { Self.readAsset($0, extension: "wav") }
            guard data.count == sound.resourceNames.count else {
                report("The \(sound.rawValue) sound files could not be loaded.")
                return nil
            }
            pools[sound] = makeVoices(data)
        }
        guard let pool = pools[sound], !pool.isEmpty else { return nil }
        let cursor = cursors[sound, default: 0] % pool.count
        let order = (0..<pool.count).map { (cursor + $0) % pool.count }
        let index = order.first(where: { !pool[$0].player.isPlaying })
            ?? pool.indices.min(by: { pool[$0].startedAt < pool[$1].startedAt })!
        cursors[sound] = (index + 1) % pool.count
        return pool[index]
    }

    private func updateEffectVolumes() {
        for voice in pools.values.flatMap({ $0 }) {
            voice.player.volume = voice.gain * Float(preferences.sfx.volume)
        }
        if preferences.sfx.volume == 0 { stopEffects() }
    }

    private func stopEffects() {
        effectGeneration &+= 1
        for voice in pools.values.flatMap({ $0 }) { voice.player.stop() }
        celebrationUntil = 0
        lastPlayed.removeAll()
    }

    private func makeMusicPlayer(_ data: Data) -> AVAudioPlayer? {
        do {
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            return player
        } catch {
            report("Could not decode background music: \(error.localizedDescription)")
            return nil
        }
    }

    private func refreshMusic() {
        guard applicationActive, !interrupted, musicMayResume,
              preferences.music.volume > 0, hardwarePlaybackAllowed,
              let selectedMusic else {
            pauseMusic()
            return
        }
        guard activateSession() else { return }
        #if os(iOS)
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else {
            pauseMusic()
            return
        }
        #endif
        if musicPlayers[selectedMusic] == nil,
           let data = Self.readAsset(selectedMusic.rawValue, extension: "m4a") {
            musicPlayers[selectedMusic] = makeMusicPlayer(data)
        }
        guard let selected = musicPlayers[selectedMusic] else {
            report("The \(selectedMusic.rawValue) background music could not be loaded.")
            return
        }
        fadeTasks[selectedMusic]?.cancel()
        fadeTasks[selectedMusic] = nil
        if !selected.isPlaying {
            selected.volume = 0
            guard selected.play() else {
                report("Could not start background music.")
                return
            }
        }
        selected.setVolume(Float(preferences.music.volume), fadeDuration: 0.35)
        for (track, player) in musicPlayers where track != selectedMusic && player.isPlaying {
            fadeTasks[track]?.cancel()
            player.setVolume(0, fadeDuration: 0.35)
            fadeTasks[track] = Task { [weak player] in
                do {
                    try await Task.sleep(for: .milliseconds(380))
                } catch is CancellationError {
                    return
                } catch {
                    AudioLog.logger.error("Music fade timing failed: \(error.localizedDescription)")
                    return
                }
                guard !Task.isCancelled else { return }
                player?.pause()
            }
        }
    }

    private func pauseMusic() {
        for task in fadeTasks.values { task.cancel() }
        fadeTasks.removeAll()
        for player in musicPlayers.values {
            player.volume = 0
            player.pause()
        }
    }

    private func configureSession() {
        guard !sessionConfigured else { return }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: .mixWithOthers)
            sessionConfigured = true
        } catch {
            report("Could not configure audio: \(error.localizedDescription)")
        }
        #else
        sessionConfigured = true
        #endif
    }

    private func activateSession() -> Bool {
        configureSession()
        guard sessionConfigured else { return false }
        guard !sessionActivated else { return true }
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            report("Could not activate audio: \(error.localizedDescription)")
            return false
        }
        #endif
        sessionActivated = true
        return true
    }

    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self, let type, let interruption = AVAudioSession.InterruptionType(rawValue: type) else { return }
                if interruption == .began {
                    self.interrupted = true
                    self.sessionActivated = false
                    self.stopEffects()
                    self.pauseMusic()
                } else {
                    self.interrupted = false
                    self.musicMayResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
                    self.refreshMusic()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                             object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.musicMayResume = false
                self?.pauseMusic()
                self?.stopEffects()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.stopEffects()
                self.pauseMusic()
                self.pools.removeAll()
                self.musicPlayers.removeAll()
                self.sessionConfigured = false
                self.sessionActivated = false
                self.preloadAll()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshMusic() }
        })
        #endif
    }

    private func report(_ message: String) {
        errorMessage = message
        AudioLog.logger.error("\(message, privacy: .public)")
    }
}
