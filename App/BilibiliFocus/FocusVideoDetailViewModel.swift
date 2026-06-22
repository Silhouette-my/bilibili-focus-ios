#if canImport(UIKit)
import AVFoundation
import FocusCore
import Foundation
import AVKit

@MainActor
final class FocusVideoDetailViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case failed(String)
        case loaded(FocusVideoDetail)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentURL: URL?
    @Published var isPlaying = false
    @Published var playbackRate: Float = 1.0
    @Published private(set) var isFullscreen = false
    @Published var selectedSubtitleID: String?

    // WebView 播放器控制闭包
    var webPlayerTogglePlayback: (() -> Void)?
    var webPlayerSetPlaybackRate: ((Float) -> Void)?

    let player = AVPlayer()
    var onStreamUnavailable: ((URL) -> Void)?

    private let service: FocusVideoDetailService
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var didRegisterEndNotification = false

    init(service: FocusVideoDetailService) {
        self.service = service
        observePlayer()
    }

    var navigationTitle: String {
        switch state {
        case let .loaded(detail):
            return detail.title
        default:
            return "视频播放"
        }
    }

    func open(_ url: URL) {
        currentURL = url
        Task {
            await load(url)
        }
    }

    func reload() {
        guard let currentURL else {
            return
        }
        Task {
            await load(currentURL)
        }
    }

    func togglePlayback() {
        // 使用 WebView 控制播放
        webPlayerTogglePlayback?()
    }

    func cyclePlaybackRate() {
        let next: Float
        switch playbackRate {
        case ..<1.01:
            next = 1.25
        case ..<1.26:
            next = 1.5
        case ..<1.51:
            next = 2.0
        default:
            next = 1.0
        }

        playbackRate = next
        webPlayerSetPlaybackRate?(next)
    }

    func setFullscreen(_ value: Bool) {
        isFullscreen = value
    }

    func toggleLike() {
        guard case let .loaded(detail) = state else { return }
        Task {
            do {
                let newState = !detail.relation.isLiked
                try await service.toggleLike(aid: detail.aid, bvid: detail.bvid, isLiked: newState)
                // 不重新加载，避免页面刷新
                print("[Focus Native Video UI] toggleLike success: \(newState)")
            } catch {
                print("[Focus Native Video UI] toggleLike error: \(error)")
            }
        }
    }

    func giveCoin() {
        guard case let .loaded(detail) = state else { return }
        Task {
            do {
                try await service.giveCoin(aid: detail.aid, bvid: detail.bvid)
                // 不重新加载，避免页面刷新
                print("[Focus Native Video UI] giveCoin success")
            } catch {
                print("[Focus Native Video UI] giveCoin error: \(error)")
            }
        }
    }

    func toggleFavorite() {
        guard case let .loaded(detail) = state else { return }
        Task {
            do {
                let newState = !detail.relation.isFavorited
                try await service.toggleFavorite(aid: detail.aid, bvid: detail.bvid, isFavorited: newState)
                // 不重新加载，避免页面刷新
                print("[Focus Native Video UI] toggleFavorite success: \(newState)")
            } catch {
                print("[Focus Native Video UI] toggleFavorite error: \(error)")
            }
        }
    }

    private func load(_ url: URL) async {
        state = .loading
        do {
            let detail = try await service.fetchDetail(for: url)
            guard !Task.isCancelled else {
                return
            }
            applyPlayback(detail.playback)
            if selectedSubtitleID == nil {
                selectedSubtitleID = detail.playback.subtitles.first?.id
            }
            state = .loaded(detail)
        } catch let error as FocusVideoDetailService.ServiceError {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func applyPlayback(_ playback: FocusVideoDetail.Playback) {
        guard let streamURL = playback.streamURL else {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            if let currentURL {
                print("[Focus Native Video UI] stream unavailable, triggering fallback to WebView for \(currentURL.absoluteString)")
                onStreamUnavailable?(currentURL)
            }
            return
        }

        let streamResource = playback.streamResource
        Task {
            let item = await buildPlayerItem(for: streamResource, fallbackURL: streamURL)
            guard !Task.isCancelled else {
                return
            }
            player.replaceCurrentItem(with: item)
            player.pause()
            player.rate = 0
            isPlaying = false
            let videoText = streamResource.videoURL?.absoluteString ?? "nil"
            let audioText = streamResource.audioURL?.absoluteString ?? "nil"
            print("[Focus Native Video UI] prepared item video=\(videoText) audio=\(audioText) fallback=\(streamURL.absoluteString)")
        }
    }

    private func buildPlayerItem(for resource: FocusVideoDetail.Playback.StreamResource, fallbackURL: URL) async -> AVPlayerItem {
        guard let videoURL = resource.videoURL else {
            return AVPlayerItem(asset: AVURLAsset(url: fallbackURL))
        }

        guard let audioURL = resource.audioURL else {
            return AVPlayerItem(asset: AVURLAsset(url: videoURL))
        }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()

        do {
            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)

            if let sourceVideoTrack = videoTracks.first,
               let targetVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            {
                let duration = try await videoAsset.load(.duration)
                try targetVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceVideoTrack, at: .zero)
                let transform = try await sourceVideoTrack.load(.preferredTransform)
                targetVideoTrack.preferredTransform = transform
            }

            if let sourceAudioTrack = audioTracks.first,
               let targetAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            {
                let audioDuration = try await audioAsset.load(.duration)
                try targetAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration), of: sourceAudioTrack, at: .zero)
            }

            if composition.tracks.isEmpty {
                return AVPlayerItem(asset: AVURLAsset(url: fallbackURL))
            }
            return AVPlayerItem(asset: composition)
        } catch {
            print("[Focus Native Video UI] composition fallback error=\(error.localizedDescription)")
            return AVPlayerItem(asset: AVURLAsset(url: fallbackURL))
        }
    }

    private func observePlayer() {
        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncPlayerState()
            }
        }

        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, change in
            guard let item = change.newValue as? AVPlayerItem else {
                return
            }
            Task { @MainActor [weak self] in
                self?.registerEndObserver(for: item)
            }
        }
    }

    private func registerEndObserver(for item: AVPlayerItem) {
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        didRegisterEndNotification = true
    }

    @objc private func handlePlaybackEnded() {
        player.seek(to: .zero)
        isPlaying = false
    }

    private func syncPlayerState() {
        isPlaying = player.timeControlStatus == .playing
        if player.rate > 0 {
            playbackRate = player.rate
        }
    }

    deinit {
        timeControlStatusObservation?.invalidate()
        currentItemObservation?.invalidate()
        if didRegisterEndNotification {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
#endif
