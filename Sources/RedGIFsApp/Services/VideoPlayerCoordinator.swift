@preconcurrency import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class VideoPlayerCoordinator {
    var isMuted: Bool {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: Keys.isMuted)
            applyMuteState()
            configureAudioSessionIfNeeded()
        }
    }

    var preferHD: Bool {
        didSet {
            UserDefaults.standard.set(preferHD, forKey: Keys.preferHD)
            reloadActiveVideoQuality()
        }
    }

    var preferAspectFill: Bool {
        didSet {
            UserDefaults.standard.set(preferAspectFill, forKey: Keys.preferAspectFill)
        }
    }

    var autoLoop: Bool {
        didSet {
            UserDefaults.standard.set(autoLoop, forKey: Keys.autoLoop)
        }
    }

    private(set) var activeGifID: String?
    private(set) var isPlaying = false
    private(set) var isPausedByUser = false
    private(set) var isBuffering = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var failedGifIDs: Set<String> = []

    private var players: [String: PlayerEntry] = [:]
    private var activeTimeObserverOwner: AVPlayer?
    private var activeTimeObserverToken: Any?
    private var activeStatusObservation: NSKeyValueObservation?
    private var activeTimeControlObservation: NSKeyValueObservation?

    private let apiClient: RedGifsAPIClient
    private let maxCachedPlayers = 3

    private enum Keys {
        static let isMuted = "pulse.player.isMuted"
        static let preferHD = "pulse.player.preferHD"
        static let preferAspectFill = "pulse.player.preferAspectFill"
        static let autoLoop = "pulse.player.autoLoop"
    }

    private struct PlayerEntry {
        let gif: GifItem
        let player: AVPlayer
        var usingHLSFallback: Bool
        var endObserver: NSObjectProtocol?
        var failureObserver: NSObjectProtocol?
        var statusObserver: NSKeyValueObservation?
    }

    init(apiClient: RedGifsAPIClient = .shared) {
        self.apiClient = apiClient
        let defaults = UserDefaults.standard
        self.isMuted = defaults.object(forKey: Keys.isMuted) as? Bool ?? false
        self.preferHD = defaults.object(forKey: Keys.preferHD) as? Bool ?? true
        self.preferAspectFill = defaults.object(forKey: Keys.preferAspectFill) as? Bool ?? false
        self.autoLoop = defaults.object(forKey: Keys.autoLoop) as? Bool ?? true
        configureAudioSessionIfNeeded()
    }

    var progress: Double {
        guard duration > 0.01 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func player(for gif: GifItem) -> AVPlayer? {
        guard gif.isVideo else { return nil }
        return players[gif.id]?.player
    }

    func activate(gif: GifItem, neighbors: [GifItem]) {
        guard gif.isVideo else {
            pauseAll()
            activeGifID = gif.id
            isPlaying = false
            isBuffering = false
            currentTime = 0
            duration = 0
            return
        }

        if activeGifID != gif.id {
            isPausedByUser = false
            currentTime = 0
            duration = gif.duration ?? 0
        }

        activeGifID = gif.id
        let entry = prepareEntry(for: gif)

        // Pause all non-active cached players so audio/decoders stay quiet.
        for (id, cached) in players where id != gif.id {
            cached.player.pause()
        }

        for neighbor in neighbors where neighbor.isVideo && neighbor.id != gif.id {
            _ = prepareEntry(for: neighbor)
        }

        var keepIDs = Set(neighbors.prefix(2).map(\.id))
        keepIDs.insert(gif.id)
        pruneCache(keeping: keepIDs)

        attachObservers(to: entry.player, gif: gif)
        entry.player.isMuted = isMuted

        if !isPausedByUser {
            entry.player.play()
            isPlaying = true
        }
    }

    func togglePlayPause() {
        guard let activeGifID, let entry = players[activeGifID] else { return }
        if entry.player.timeControlStatus == .playing || isPlaying {
            entry.player.pause()
            isPausedByUser = true
            isPlaying = false
        } else {
            isPausedByUser = false
            entry.player.play()
            isPlaying = true
        }
    }

    func pauseAll() {
        detachActiveObservers()
        for entry in players.values {
            entry.player.pause()
        }
        isPlaying = false
    }

    func resumeActiveIfNeeded() {
        guard let activeGifID,
              let entry = players[activeGifID],
              !isPausedByUser else { return }
        entry.player.isMuted = isMuted
        entry.player.play()
        isPlaying = true
    }

    func seek(to fraction: Double) {
        guard let activeGifID,
              let entry = players[activeGifID],
              let item = entry.player.currentItem else { return }
        let itemDuration = item.duration.seconds
        let effectiveDuration = (itemDuration.isFinite && itemDuration > 0) ? itemDuration : duration
        guard effectiveDuration > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        let targetSeconds = effectiveDuration * clamped
        let cmTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentTime = targetSeconds
        entry.player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func retry(gif: GifItem, neighbors: [GifItem]) {
        failedGifIDs.remove(gif.id)
        evictPlayer(for: gif.id)
        activate(gif: gif, neighbors: neighbors)
    }

    // MARK: - Private Management

    private func prepareEntry(for gif: GifItem) -> PlayerEntry {
        if let existing = players[gif.id] {
            return existing
        }

        let primaryURL = gif.bestVideoURL(preferHD: preferHD)
        let fallbackHLS = gif.hlsURL(preferHD: preferHD)
        let selectedURL = primaryURL ?? fallbackHLS
        let usingHLS = selectedURL != nil && selectedURL == fallbackHLS && primaryURL != fallbackHLS

        let player: AVPlayer
        if let selectedURL {
            let item = makePlayerItem(url: selectedURL)
            player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true
        } else {
            player = AVPlayer()
        }
        player.isMuted = isMuted
        player.actionAtItemEnd = .none

        var entry = PlayerEntry(
            gif: gif,
            player: player,
            usingHLSFallback: usingHLS,
            endObserver: nil,
            failureObserver: nil,
            statusObserver: nil
        )

        if let item = player.currentItem {
            installItemObservers(for: gif, item: item, entry: &entry)
        }

        players[gif.id] = entry
        return entry
    }

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [
                AVURLAssetHTTPUserAgentKey: RedGifsAPIClient.userAgent,
                "AVURLAssetHTTPHeaderFieldsKey": apiClient.mediaHeaders(),
            ]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4.0
        return item
    }

    private func installItemObservers(for gif: GifItem, item: AVPlayerItem, entry: inout PlayerEntry) {
        let gifID = gif.id
        entry.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackDidEnd(for: gifID)
            }
        }

        entry.failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleItemFailure(for: gifID)
            }
        }

        entry.statusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            Task { @MainActor [weak self] in
                if status == .failed {
                    self?.handleItemFailure(for: gifID)
                }
            }
        }
    }

    private func handlePlaybackDidEnd(for gifID: String) {
        guard let entry = players[gifID] else { return }
        if autoLoop {
            entry.player.seek(to: .zero) { [weak self] finished in
                guard finished else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.activeGifID == gifID, !self.isPausedByUser else { return }
                    entry.player.play()
                }
            }
        } else if activeGifID == gifID {
            isPlaying = false
        }
    }

    private func handleItemFailure(for gifID: String) {
        guard var entry = players[gifID] else { return }
        if !entry.usingHLSFallback, let hlsURL = entry.gif.hlsURL(preferHD: preferHD) {
            cleanupItemObservers(for: &entry)
            let fallbackItem = makePlayerItem(url: hlsURL)
            entry.usingHLSFallback = true
            entry.player.replaceCurrentItem(with: fallbackItem)
            installItemObservers(for: entry.gif, item: fallbackItem, entry: &entry)
            players[gifID] = entry
            if activeGifID == gifID && !isPausedByUser {
                attachObservers(to: entry.player, gif: entry.gif)
                entry.player.play()
            }
            return
        }
        failedGifIDs.insert(gifID)
        if activeGifID == gifID {
            isBuffering = false
            isPlaying = false
        }
    }

    private func attachObservers(to player: AVPlayer, gif: GifItem) {
        if activeTimeObserverOwner === player, activeTimeObserverToken != nil {
            return
        }
        detachActiveObservers()

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        activeTimeObserverOwner = player
        activeTimeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.activeTimeObserverOwner === player else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = max(0, seconds)
                }
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                } else if let fallbackDuration = gif.duration, fallbackDuration > 0 {
                    self.duration = fallbackDuration
                }
            }
        }

        activeTimeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak player] observed, _ in
            let controlStatus = observed.timeControlStatus
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.activeTimeObserverOwner === player else { return }
                switch controlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = !self.isPausedByUser
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                @unknown default:
                    break
                }
            }
        }

        if let item = player.currentItem {
            activeStatusObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self, weak player] observedItem, _ in
                let likely = observedItem.isPlaybackLikelyToKeepUp
                Task { @MainActor [weak self, weak player] in
                    guard let self, let player, self.activeTimeObserverOwner === player else { return }
                    if likely {
                        self.isBuffering = false
                    }
                }
            }
        }
    }

    private func detachActiveObservers() {
        if let owner = activeTimeObserverOwner, let token = activeTimeObserverToken {
            owner.removeTimeObserver(token)
        }
        activeTimeObserverOwner = nil
        activeTimeObserverToken = nil
        activeStatusObservation?.invalidate()
        activeStatusObservation = nil
        activeTimeControlObservation?.invalidate()
        activeTimeControlObservation = nil
    }

    private func pruneCache(keeping keepIDs: Set<String>) {
        guard players.count > maxCachedPlayers else { return }
        let removableIDs = players.keys.filter { !keepIDs.contains($0) && $0 != activeGifID }
        for id in removableIDs {
            evictPlayer(for: id)
            if players.count <= maxCachedPlayers {
                break
            }
        }
    }

    private func evictPlayer(for gifID: String) {
        guard var entry = players.removeValue(forKey: gifID) else { return }
        if activeTimeObserverOwner === entry.player {
            detachActiveObservers()
        }
        entry.player.pause()
        cleanupItemObservers(for: &entry)
    }

    private func cleanupItemObservers(for entry: inout PlayerEntry) {
        if let endObserver = entry.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            entry.endObserver = nil
        }
        if let failureObserver = entry.failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            entry.failureObserver = nil
        }
        entry.statusObserver?.invalidate()
        entry.statusObserver = nil
    }

    private func applyMuteState() {
        for entry in players.values {
            entry.player.isMuted = isMuted
        }
    }

    private func reloadActiveVideoQuality() {
        guard let activeGifID, let entry = players[activeGifID] else { return }
        let currentGif = entry.gif
        let neighbors = players.values.map(\.gif).filter { $0.id != activeGifID }
        for id in Array(players.keys) {
            evictPlayer(for: id)
        }
        activate(gif: currentGif, neighbors: neighbors)
    }

    private func configureAudioSessionIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio session configuration can fail on simulator or restricted audio routes; video still renders.
        }
    }
}
