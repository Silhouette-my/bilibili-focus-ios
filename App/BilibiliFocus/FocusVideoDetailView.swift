#if canImport(UIKit)
import AVKit
import FocusCore
import SwiftUI
import WebKit

struct FocusVideoDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: FocusVideoDetailViewModel
    @ObservedObject var settingsStore: FocusSettingsStore
    let onOpenVideo: (URL) -> Void
    let onOpenUserSpace: (URL) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        content
            .onAppear {
                // 允许视频页面旋转
                AppDelegate.orientationLock = .allButUpsideDown
                // 监听设备方向变化
                NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak viewModel] _ in
                    guard let viewModel = viewModel else { return }
                    Task { @MainActor in
                        let orientation = UIDevice.current.orientation
                        switch orientation {
                        case .landscapeLeft, .landscapeRight:
                            // 横屏时自动进入全屏
                            if !viewModel.isFullscreen {
                                viewModel.setFullscreen(true)
                            }
                        case .portrait, .portraitUpsideDown:
                            // 竖屏时退出全屏
                            if viewModel.isFullscreen {
                                viewModel.setFullscreen(false)
                            }
                        default:
                            break
                        }
                    }
                }
            }
            .onDisappear {
                // 离开视频页面，锁定竖屏
                AppDelegate.orientationLock = .portrait
                NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
                // 强制回到竖屏
                if #available(iOS 16.0, *) {
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                } else {
                    UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("加载视频详情…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            FocusStateView(
                title: "视频详情加载失败",
                message: message,
                buttonTitle: "重试",
                action: viewModel.reload
            )

        case let .loaded(detail):
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        playerSection(detail)

                        Text(detail.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)

                        metaSummary(detail.stat)
                            .padding(.horizontal, 16)

                        actionBar(detail)
                            .padding(.horizontal, 16)

                        if !detail.episodeGroups.isEmpty {
                            ForEach(detail.episodeGroups) { group in
                                if group.items.count > 1 {
                                    episodeGroup(group)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !detail.comments.isEmpty {
                            commentsSection(detail.comments)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    viewModel.reload()
                }
                .onAppear {
                    print("[Focus Native Video UI] loaded title=\(detail.title) bvid=\(detail.bvid) stream=\(detail.playback.streamURL?.absoluteString ?? "nil") subtitles=\(detail.playback.subtitles.count)")
                    print("[Focus Native Video UI] detail comments=\(detail.comments.count) groups=\(detail.episodeGroups.count) author=\(detail.author.name)")
                }

                videoControls(detail)
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 0)
            }
            .sheet(isPresented: fullscreenBinding) {
                if let currentURL = viewModel.currentURL {
                    FocusWebVideoPlayerFullscreen(url: currentURL, onDismiss: {
                        viewModel.setFullscreen(false)
                    })
                    .ignoresSafeArea()
                }
            }
        }
    }

    private func debugBanner(_ detail: FocusVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NATIVE VIDEO UI ACTIVE")
                .font(.caption.weight(.bold))
            Text("orange background + Native title = current screen is native")
                .font(.caption2)
            Text("bvid: \(detail.bvid)")
                .font(.caption2.monospaced())
            Text("stream: \(detail.playback.streamURL?.lastPathComponent ?? "nil")")
                .font(.caption2.monospaced())
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.88))
        )
    }

    private func playerSection(_ detail: FocusVideoDetail) -> some View {
        Group {
            if let currentURL = viewModel.currentURL {
                FocusWebVideoPlayerContainer(
                    url: currentURL,
                    isPlaying: $viewModel.isPlaying,
                    playbackRate: $viewModel.playbackRate,
                    onCoordinatorReady: { coordinator in
                        viewModel.webPlayerTogglePlayback = { [weak coordinator] in
                            coordinator?.togglePlayback()
                        }
                        viewModel.webPlayerSetPlaybackRate = { [weak coordinator] rate in
                            coordinator?.setPlaybackRate(rate)
                        }
                    }
                )
            } else {
                Color.black
                    .overlay {
                        ProgressView("加载播放器...")
                            .foregroundStyle(.white)
                    }
            }
        }
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .background(Color.black)
    }

    private func videoControls(_ detail: FocusVideoDetail) -> some View {
        HStack(spacing: 0) {
            FocusVideoControlButton(
                systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill",
                accessibilityLabel: "播放或暂停"
            ) {
                viewModel.togglePlayback()
            }
            .frame(maxWidth: .infinity)

            Divider()
                .background(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.2))

            FocusVideoControlButton(
                systemImage: "speedometer",
                title: playbackRateLabel,
                accessibilityLabel: "切换倍速"
            ) {
                viewModel.cyclePlaybackRate()
            }
            .frame(maxWidth: .infinity)

            Divider()
                .background(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.2))

            FocusVideoControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "切换全屏"
            ) {
                viewModel.setFullscreen(true)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
        .background(Color(uiColor: colorScheme == .dark ? .systemGray6 : .systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.15)),
            alignment: .top
        )
    }

    private var fullscreenBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isFullscreen },
            set: { viewModel.setFullscreen($0) }
        )
    }

    private var playbackRateLabel: String {
        let rate = Double(viewModel.playbackRate)
        switch rate {
        case 1:
            return "1x"
        case 1.25:
            return "1.25x"
        case 1.5:
            return "1.5x"
        case 2:
            return "2x"
        default:
            return String(format: "%.2gx", rate)
        }
    }

    @ViewBuilder
    private func metaSummary(_ stat: FocusVideoDetail.Stat) -> some View {
        let rows = [
            ("play.rectangle", stat.playText.isEmpty ? "--" : stat.playText, "播放"),
            ("text.bubble", stat.danmakuText.isEmpty ? "--" : stat.danmakuText, "弹幕")
        ]

        HStack(spacing: 14) {
            ForEach(rows, id: \.1) { row in
                Label {
                    Text("\(row.1) \(row.2)")
                } icon: {
                    Image(systemName: row.0)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func actionBar(_ detail: FocusVideoDetail) -> some View {
        HStack(spacing: 10) {
            videoAuthorCard(detail.author)

            HStack(spacing: 0) {
                Button {
                    viewModel.toggleLike()
                } label: {
                    actionItem(symbol: detail.relation.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup", title: detail.stat.likeText)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    viewModel.giveCoin()
                } label: {
                    actionItem(symbol: detail.relation.coinCount > 0 ? "bitcoinsign.circle.fill" : "bitcoinsign.circle", title: detail.stat.coinText)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    viewModel.toggleFavorite()
                } label: {
                    actionItem(symbol: detail.relation.isFavorited ? "star.fill" : "star", title: detail.stat.favoriteText)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button {
                    // TODO: Share action
                } label: {
                    actionItem(symbol: "square.and.arrow.up", title: "分享")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
    }

    private func actionItem(symbol: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
            Text(title.isEmpty ? "--" : title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.primary)
        .frame(height: 58)
    }

    @ViewBuilder
    private func videoAuthorCard(_ author: FocusVideoDetail.Author) -> some View {
        Button {
            guard let url = author.spaceURL else {
                return
            }
            onOpenUserSpace(url)
        } label: {
            HStack(spacing: 10) {
                FocusRemoteImage(url: author.avatarURL, referer: author.spaceURL?.absoluteString ?? "https://space.bilibili.com/") { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                    case .empty:
                        Circle()
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .overlay(ProgressView())
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(author.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("进入 UP 主页")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func subtitleSection(_ detail: FocusVideoDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("字幕")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(detail.playback.subtitles) { subtitle in
                        Button {
                            viewModel.selectedSubtitleID = subtitle.id
                        } label: {
                            Text(subtitle.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(viewModel.selectedSubtitleID == subtitle.id ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(viewModel.selectedSubtitleID == subtitle.id ? FocusSharedDesign.primary : Color(uiColor: .tertiarySystemGroupedBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func episodeGroup(_ group: FocusVideoDetail.EpisodeGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(group.items) { item in
                            Button {
                                onOpenVideo(item.targetURL)
                            } label: {
                                FocusVideoEpisodeCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
                .onAppear {
                    if let currentItem = group.items.first(where: { $0.isCurrent }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentItem.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func commentsSection(_ comments: [FocusVideoDetail.Comment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            ForEach(comments) { comment in
                FocusVideoCommentCard(comment: comment)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct FocusNativeVideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

private struct FocusNativeFullscreenPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func playerViewControllerWillEndFullScreenPresentation(_ playerViewController: AVPlayerViewController) {
            onDismiss()
        }
    }
}

private struct FocusVideoEpisodeCard: View {
    let item: FocusVideoDetail.EpisodeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !item.badge.isEmpty {
                Text(item.badge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 160, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(item.isCurrent ? FocusSharedDesign.primary.opacity(0.14) : Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.isCurrent ? FocusSharedDesign.primary.opacity(0.42) : Color.white.opacity(0), lineWidth: 1.5)
        )
    }
}

private struct FocusVideoCommentCard: View {
    let comment: FocusVideoDetail.Comment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FocusRemoteImage(url: comment.avatarURL, referer: "https://www.bilibili.com/") { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                case .empty:
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .overlay(ProgressView())
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(comment.author)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FocusSharedDesign.primary)

                Text(comment.content)
                    .font(.body)
                    .foregroundStyle(.primary)

                let meta = [comment.timeText, comment.likeText, comment.replyText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }
}

// MARK: - WebView Video Player

private struct FocusWebVideoPlayerContainer: UIViewRepresentable {
    let url: URL
    @Binding var isPlaying: Bool
    @Binding var playbackRate: Float
    let onCoordinatorReady: ((Coordinator) -> Void)?

    init(url: URL, isPlaying: Binding<Bool>, playbackRate: Binding<Float>, onCoordinatorReady: ((Coordinator) -> Void)? = nil) {
        self.url = url
        _isPlaying = isPlaying
        _playbackRate = playbackRate
        self.onCoordinatorReady = onCoordinatorReady
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(isPlaying: $isPlaying, playbackRate: $playbackRate)
        onCoordinatorReady?(coordinator)
        return coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator

        // 设置桌面 User-Agent
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15"

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        context.coordinator.webView = webView

        // 加载完整的 bilibili 网页
        let request = URLRequest(url: url)
        webView.load(request)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 不自动重新加载，避免刷新问题
        // URL 的变化由用户操作（点击新视频）触发
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isPlaying: Bool
        @Binding var playbackRate: Float
        weak var webView: WKWebView?

        init(isPlaying: Binding<Bool>, playbackRate: Binding<Float>) {
            _isPlaying = isPlaying
            _playbackRate = playbackRate
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 页面加载完成，注入 CSS 隐藏不需要的元素（参考 FocusRuleCatalog video-prune 和 video-repair）
            print("[WebVideoPlayer] Page loaded, injecting CSS")

            let css = """
            /* 隐藏所有非播放器元素 */
            .m-video-related,
            .m-video2-recom,
            .m-video-related-wrap,
            .recom-wrapper,
            .recom-list,
            .card-box,
            .launch-app-btn,
            .open-app-btn,
            .openapp-btn,
            .download-btn,
            .download-layer,
            .m-video-open-app,
            .video-open-app,
            .video-guide-open-app,
            .m-video-float-openapp,
            .m-bottom-app-download,
            .m-video-up-app,
            .m-nav-bottom,
            .v-card-module,
            .download-entry,
            .download-client-trigger,
            #commentapp,
            [class*="openapp"],
            [id*="openapp"],
            #biliMainHeader,
            #bili-header-container,
            .bili-header,
            .international-header,
            .fixed-header,
            #viewbox_report,
            .video-info-container,
            #v_desc,
            .video-desc-container,
            .video-tag-container,
            .left-banner,
            .rec-list,
            .related-list,
            .video-sections,
            .up-panel-container,
            .up-info-container,
            .video-top-container,
            .note-card,
            .bpx-player-sending-area,
            .bilibili-player-video-inputbar,
            .bilibili-player-danmaku-input,
            .bilibili-player-danmaku-send,
            .right-container,
            .right-container-inner,
            aside {
              display: none !important;
            }

            /* 页面布局 */
            html,
            body {
              width: 100% !important;
              height: 100% !important;
              margin: 0 !important;
              padding: 0 !important;
              overflow: hidden !important;
              background: #000000 !important;
            }

            #app,
            main,
            #mirror-vdcon,
            .video-container,
            .video-container-v1 {
              width: 100% !important;
              height: 100% !important;
              min-width: 0 !important;
              max-width: 100% !important;
              margin: 0 !important;
              padding: 0 !important;
              box-sizing: border-box !important;
              overflow: hidden !important;
            }

            .left-container,
            .left-container.scroll-sticky {
              width: 100% !important;
              height: 100% !important;
              min-width: 0 !important;
              max-width: 100% !important;
              margin: 0 !important;
              padding: 0 !important;
              box-sizing: border-box !important;
              position: static !important;
              inset: auto !important;
              overflow: hidden !important;
            }

            /* 隐藏左侧容器中除了播放器外的所有内容 */
            .left-container > *:not(#playerWrap):not(.player-wrap),
            .left-container.scroll-sticky > *:not(#playerWrap):not(.player-wrap) {
              display: none !important;
            }

            /* 播放器容器占满整个屏幕 */
            #playerWrap,
            .player-wrap,
            .player-container,
            #bilibili-player,
            .bpx-player-container {
              width: 100% !important;
              height: 100% !important;
              min-width: 0 !important;
              max-width: 100% !important;
              margin: 0 !important;
              padding: 0 !important;
              position: static !important;
              inset: auto !important;
            }
            """

            let script = """
            (function() {
                var style = document.createElement('style');
                style.textContent = `\(css)`;
                document.head.appendChild(style);
            })();
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("[WebVideoPlayer] CSS injection error: \(error)")
                } else {
                    print("[WebVideoPlayer] CSS injected successfully")
                }
            }
        }

        func togglePlayback() {
            guard let webView else { return }

            let script = """
            (function() {
              var video = document.querySelector('video');
              if (video) {
                if (video.paused) {
                  video.play();
                } else {
                  video.pause();
                }
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    print("[WebVideoPlayer] togglePlayback error: \(error)")
                } else {
                    self?.isPlaying.toggle()
                }
            }
        }

        func setPlaybackRate(_ rate: Float) {
            guard let webView else { return }

            let script = """
            (function() {
              var video = document.querySelector('video');
              if (video) {
                video.playbackRate = \(rate);
              }
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    print("[WebVideoPlayer] setPlaybackRate error: \(error)")
                } else {
                    self?.playbackRate = rate
                }
            }
        }
    }
}

private struct FocusWebVideoPlayerFullscreen: View {
    let url: URL
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            FocusWebVideoPlayerContainer(
                url: url,
                isPlaying: .constant(true),
                playbackRate: .constant(1.0)
            )
            .ignoresSafeArea()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(16)
        }
    }
}
#endif

