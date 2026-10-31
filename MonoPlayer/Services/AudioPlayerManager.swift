import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Воспроизведение, очередь, фоновая аудиосессия, экран блокировки и Dynamic Island.
@MainActor
@Observable
final class AudioPlayerManager {
    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var currentTrack: Track? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var upNext: [Track] {
        guard let currentIndex, currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var notificationTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var seekInFlight = false

    init() {
        configureAudioSession()
        configureRemoteCommands()
        observePlayback()
    }

    // MARK: - Управление

    func play(_ track: Track, in list: [Track]) {
        queue = list.isEmpty ? [track] : list
        currentIndex = queue.firstIndex { $0.id == track.id } ?? 0
        loadCurrent(autoplay: true)
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard currentTrack != nil else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard let currentIndex else { return }
        if currentIndex + 1 < queue.count {
            self.currentIndex = currentIndex + 1
            loadCurrent(autoplay: true)
        } else {
            // Конец очереди: останавливаемся на начале последнего трека
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard let currentIndex else { return }
        if currentTime > 3 || currentIndex == 0 {
            seek(to: 0)
        } else {
            self.currentIndex = currentIndex - 1
            loadCurrent(autoplay: isPlaying)
        }
    }

    func seek(to time: TimeInterval) {
        let target = max(0, min(time, duration > 0 ? duration : time))
        currentTime = target
        seekInFlight = true
        let manager = self
        let completion: @Sendable (Bool) -> Void = { _ in
            Task { @MainActor in manager.finishSeek() }
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)
    }

    private func finishSeek() {
        seekInFlight = false
        updateNowPlayingInfo()
    }

    func playNext(_ track: Track) {
        guard let currentIndex else {
            play(track, in: [track])
            return
        }
        if let existing = queue.firstIndex(where: { $0.id == track.id }) {
            if existing == currentIndex { return }
            queue.remove(at: existing)
            if existing < currentIndex { self.currentIndex = currentIndex - 1 }
        }
        queue.insert(track, at: (self.currentIndex ?? 0) + 1)
    }

    func remove(_ track: Track) {
        guard let index = queue.firstIndex(where: { $0.id == track.id }) else { return }
        let wasCurrent = index == currentIndex
        queue.remove(at: index)

        guard let currentIndex else { return }
        if queue.isEmpty {
            stop()
        } else if wasCurrent {
            self.currentIndex = min(currentIndex, queue.count - 1)
            loadCurrent(autoplay: isPlaying)
        } else if index < currentIndex {
            self.currentIndex = currentIndex - 1
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        currentIndex = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Загрузка

    private func loadCurrent(autoplay: Bool) {
        guard let track = currentTrack else { return }
        let item = AVPlayerItem(url: track.audioURL)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = track.duration
        if autoplay { play() } else { isPlaying = false }
        updateNowPlayingInfo()
    }

    private func handleTick(_ seconds: TimeInterval) {
        guard !seekInFlight else { return }
        if seconds.isFinite { currentTime = seconds }
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        let playing = player.timeControlStatus != .paused
        if playing != isPlaying { isPlaying = playing }
    }

    // MARK: - Системная интеграция

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }

    private func observePlayback() {
        // 0.2 c — достаточно для синхронизации караоке-текста
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.handleTick(seconds) }
        }

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let finished = (note.object as AnyObject?).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem, finished == ObjectIdentifier(item) else { return }
                self.next()
            }
        })

        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            MainActor.assumeIsolated {
                switch type {
                case .began: self?.pause()
                case .ended where options.contains(.shouldResume): self?.play()
                default: break
                }
            }
        })

        // Отключили наушники — пауза, как в системном плеере
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            MainActor.assumeIsolated {
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        // Менеджер живёт всё время работы приложения, поэтому сильный захват безопасен.
        let manager = self
        Self.register(center.playCommand) { _ in
            Task { @MainActor in manager.play() }
            return .success
        }
        Self.register(center.pauseCommand) { _ in
            Task { @MainActor in manager.pause() }
            return .success
        }
        Self.register(center.togglePlayPauseCommand) { _ in
            Task { @MainActor in manager.togglePlayPause() }
            return .success
        }
        Self.register(center.nextTrackCommand) { _ in
            Task { @MainActor in manager.next() }
            return .success
        }
        Self.register(center.previousTrackCommand) { _ in
            Task { @MainActor in manager.previous() }
            return .success
        }
        Self.register(center.changePlaybackPositionCommand) { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in manager.seek(to: position) }
            return .success
        }
    }

    /// Обработчики вызываются системой вне главного актора, поэтому замыкание явно `@Sendable`.
    private nonisolated static func register(
        _ command: MPRemoteCommand,
        handler: @escaping @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        command.addTarget(handler: handler)
    }

    func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let url = track.artworkURL, let image = UIImage(contentsOfFile: url.path()) {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// MPMediaItemArtwork вызывает замыкание на фоновой очереди — создаём его вне главного актора,
    /// иначе Swift 6 упадёт на проверке изоляции.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
