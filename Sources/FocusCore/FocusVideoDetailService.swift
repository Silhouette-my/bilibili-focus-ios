import CryptoKit
import Foundation

public final class FocusVideoDetailService: @unchecked Sendable {
    public enum ServiceError: LocalizedError {
        case invalidURL
        case loginRequired
        case notFound
        case requestFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "视频链接无效"
            case .loginRequired:
                return "需要登录后才能加载视频详情"
            case .notFound:
                return "未找到视频详情"
            case let .requestFailed(message):
                return message
            }
        }
    }

    private typealias JSONObject = [String: Any]

    private let cookieProvider: any CookieSnapshotProvider
    private let session: URLSession
    private var cachedWbiKey: String?
    private var cachedWbiExpiration = Date.distantPast

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let wbiMixinTable = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
    ]

    public init(cookieProvider: any CookieSnapshotProvider) {
        self.cookieProvider = cookieProvider
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 16
        configuration.timeoutIntervalForResource = 24
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    public func fetchDetail(for url: URL) async throws -> FocusVideoDetail {
        guard let bvid = Self.extractBvid(from: url) else {
            throw ServiceError.invalidURL
        }

        let referer = "https://www.bilibili.com/video/\(bvid)"
        let viewRoot = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)",
            referer: referer
        )

        if viewRoot.intValue(at: ["code"]) == -101 {
            throw ServiceError.loginRequired
        }

        guard viewRoot.intValue(at: ["code"]) == 0,
              let data = viewRoot.dictionaryValue(at: ["data"])
        else {
            throw ServiceError.requestFailed(viewRoot.stringValue(at: ["message"]) ?? "视频详情加载失败")
        }

        let title = data.stringValue(at: ["title"]) ?? "视频"
        let owner = data.dictionaryValue(at: ["owner"]) ?? [:]
        let statPayload = data.dictionaryValue(at: ["stat"]) ?? [:]
        let aid = Int64(data.intValue(at: ["aid"]) ?? 0)
        let currentPageNumber = Self.extractPageNumber(from: url)
        let cid = Self.resolveCID(from: data, currentPageNumber: currentPageNumber)

        let authorMID = Int64(owner.intValue(at: ["mid"]) ?? 0)
        let avatarURL = Self.normalizedURL(owner.stringValue(at: ["face"]))
        let author = FocusVideoDetail.Author(
            mid: authorMID,
            name: owner.stringValue(at: ["name"]) ?? owner.stringValue(at: ["uname"]) ?? "UP主",
            avatarURL: avatarURL,
            spaceURL: authorMID > 0 ? URL(string: "https://space.bilibili.com/\(authorMID)") : nil
        )

        let stat = FocusVideoDetail.Stat(
            playText: Self.formatCount(Int64(statPayload.intValue(at: ["view"]) ?? 0)),
            danmakuText: Self.formatCount(Int64(statPayload.intValue(at: ["danmaku"]) ?? 0)),
            likeText: Self.formatCount(Int64(statPayload.intValue(at: ["like"]) ?? 0)),
            coinText: Self.formatCount(Int64(statPayload.intValue(at: ["coin"]) ?? 0)),
            favoriteText: Self.formatCount(Int64(statPayload.intValue(at: ["favorite"]) ?? 0)),
            shareText: Self.formatCount(Int64(statPayload.intValue(at: ["share"]) ?? 0))
        )

        var groups: [FocusVideoDetail.EpisodeGroup] = []
        let pages = parseVideoPages(from: data, bvid: bvid, currentPageNumber: currentPageNumber)
        if !pages.isEmpty {
            groups.append(
                .init(
                    id: "pages",
                    title: pages.count > 1 ? "分P · 共 \(pages.count) 条" : "分P",
                    items: pages
                )
            )
        }
        groups.append(contentsOf: parseEpisodeGroups(from: data, currentBvid: bvid))

        let playback = try await fetchPlayback(
            aid: aid,
            bvid: bvid,
            cid: cid,
            referer: referer,
            posterURL: Self.normalizedURL(data.stringValue(at: ["pic"])),
            duration: TimeInterval(data.intValue(at: ["duration"]) ?? 0)
        )

        let relation = try await fetchRelation(aid: aid, bvid: bvid, referer: referer)

        let comments = aid > 0
            ? try await fetchComments(oid: String(aid), type: 1, referer: referer)
            : []

        return FocusVideoDetail(
            bvid: bvid,
            aid: aid,
            cid: cid,
            title: title,
            author: author,
            stat: stat,
            playback: playback,
            relation: relation,
            episodeGroups: groups.filter { !$0.items.isEmpty },
            comments: comments
        )
    }

    private func fetchPlayback(
        aid: Int64,
        bvid: String,
        cid: Int64?,
        referer: String,
        posterURL: URL?,
        duration: TimeInterval
    ) async throws -> FocusVideoDetail.Playback {
        guard aid > 0, let cid else {
            return .init(
                streamURL: nil,
                streamResource: .init(videoURL: nil, audioURL: nil),
                posterURL: posterURL,
                duration: duration,
                subtitles: []
            )
        }

        var params = [
            "qn": "127",
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "avid": String(aid),
            "bvid": bvid,
            "cid": String(cid),
            "from_client": "BROWSER",
            "web_location": "1315873"
        ]
        let playurlQuery = try await signedWbiQuery(parameters: params, referer: referer)
        let playurlRoot = try await requestObject(
            urlString: "https://api.bilibili.com/x/player/wbi/playurl?\(playurlQuery)",
            referer: referer
        )

        let streamResource = Self.extractStreamResource(from: playurlRoot)

        params = [
            "aid": String(aid),
            "cid": String(cid),
            "isGaiaAvoided": "false",
            "web_location": "1315873"
        ]
        let playerInfoRoot = try await requestObject(
            urlString: "https://api.bilibili.com/x/player/v2?aid=\(aid)&cid=\(cid)&web_location=1315873",
            referer: referer
        )
        let subtitles = Self.extractSubtitles(from: playerInfoRoot)

        return .init(
            streamURL: streamResource.videoURL,
            streamResource: streamResource,
            posterURL: posterURL,
            duration: duration,
            subtitles: subtitles
        )
    }

    private func fetchRelation(aid: Int64, bvid: String, referer: String) async throws -> FocusVideoDetail.Relation {
        guard aid > 0 else {
            return .init(isLiked: false, coinCount: 0, isFavorited: false)
        }

        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/web-interface/archive/relation?aid=\(aid)&bvid=\(bvid)",
            referer: referer
        )

        guard root.intValue(at: ["code"]) == 0,
              let data = root.dictionaryValue(at: ["data"])
        else {
            return .init(isLiked: false, coinCount: 0, isFavorited: false)
        }

        return .init(
            isLiked: (data.intValue(at: ["like"]) ?? 0) == 1,
            coinCount: data.intValue(at: ["coin"]) ?? 0,
            isFavorited: (data.intValue(at: ["favorite"]) ?? 0) == 1
        )
    }

    public func toggleLike(aid: Int64, bvid: String, isLiked: Bool) async throws {
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let csrf = await extractCSRF()
        let urlString = "https://api.bilibili.com/x/web-interface/archive/like"

        guard var components = URLComponents(string: urlString) else {
            throw ServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "aid", value: String(aid)),
            URLQueryItem(name: "like", value: isLiked ? "1" : "2"),
            URLQueryItem(name: "csrf", value: csrf)
        ]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        request = cookieProvider.attachCookies(to: request)

        let (data, _) = try await session.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw ServiceError.requestFailed("点赞操作失败")
        }

        if root.intValue(at: ["code"]) != 0 {
            throw ServiceError.requestFailed(root.stringValue(at: ["message"]) ?? "点赞操作失败")
        }
    }

    public func giveCoin(aid: Int64, bvid: String, count: Int = 1) async throws {
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let csrf = await extractCSRF()
        let urlString = "https://api.bilibili.com/x/web-interface/coin/add"

        guard var components = URLComponents(string: urlString) else {
            throw ServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "aid", value: String(aid)),
            URLQueryItem(name: "multiply", value: String(count)),
            URLQueryItem(name: "select_like", value: "0"),
            URLQueryItem(name: "csrf", value: csrf)
        ]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        request = cookieProvider.attachCookies(to: request)

        let (data, _) = try await session.data(for: request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw ServiceError.requestFailed("投币操作失败")
        }

        if root.intValue(at: ["code"]) != 0 {
            throw ServiceError.requestFailed(root.stringValue(at: ["message"]) ?? "投币操作失败")
        }
    }

    public func toggleFavorite(aid: Int64, bvid: String, isFavorited: Bool) async throws {
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let csrf = await extractCSRF()

        if isFavorited {
            let urlString = "https://api.bilibili.com/x/v3/fav/resource/deal"
            guard var components = URLComponents(string: urlString) else {
                throw ServiceError.invalidURL
            }

            components.queryItems = [
                URLQueryItem(name: "rid", value: String(aid)),
                URLQueryItem(name: "type", value: "2"),
                URLQueryItem(name: "add_media_ids", value: ""),
                URLQueryItem(name: "del_media_ids", value: ""),
                URLQueryItem(name: "csrf", value: csrf)
            ]

            guard let url = components.url else {
                throw ServiceError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(referer, forHTTPHeaderField: "Referer")
            request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
            request = cookieProvider.attachCookies(to: request)

            let (data, _) = try await session.data(for: request)
            guard let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject else {
                throw ServiceError.requestFailed("收藏操作失败")
            }

            if root.intValue(at: ["code"]) != 0 {
                throw ServiceError.requestFailed(root.stringValue(at: ["message"]) ?? "收藏操作失败")
            }
        } else {
            throw ServiceError.requestFailed("取消收藏需要指定收藏夹ID")
        }
    }

    private func extractCSRF() async -> String {
        let cookies = await cookieProvider.loadCookies()
        return cookies.first(where: { $0.name == "bili_jct" })?.value ?? ""
    }

    private func parseVideoPages(from data: JSONObject, bvid: String, currentPageNumber: Int?) -> [FocusVideoDetail.EpisodeItem] {
        guard let pages = data.arrayValue(at: ["pages"]) else {
            return []
        }

        return pages.compactMap { page in
            let pageNumber = page.intValue(at: ["page"]) ?? 1
            let title = page.stringValue(at: ["part"])?.nilIfBlank ?? "P\(pageNumber)"
            let duration = Self.formatDuration(Int64(page.intValue(at: ["duration"]) ?? 0))
            guard let targetURL = URL(string: "https://www.bilibili.com/video/\(bvid)?p=\(pageNumber)") else {
                return nil
            }
            return .init(
                id: "page-\(pageNumber)",
                title: title,
                subtitle: "P\(pageNumber)",
                badge: duration,
                targetURL: targetURL,
                isCurrent: currentPageNumber == pageNumber
            )
        }
    }

    private func parseEpisodeGroups(from data: JSONObject, currentBvid: String) -> [FocusVideoDetail.EpisodeGroup] {
        guard let ugcSeason = data.dictionaryValue(at: ["ugc_season"]) else {
            return []
        }

        let seasonTitle = ugcSeason.stringValue(at: ["title"])?.nilIfBlank ?? "选集"
        let sections = ugcSeason.arrayValue(at: ["sections"]) ?? []

        return sections.compactMap { section in
            let groupTitle = section.stringValue(at: ["title"])?.nilIfBlank ?? seasonTitle
            let episodes: [FocusVideoDetail.EpisodeItem] = (section.arrayValue(at: ["episodes"]) ?? []).compactMap { episode in
                guard let bvid = episode.stringValue(at: ["bvid"])?.nilIfBlank,
                      let targetURL = URL(string: "https://www.bilibili.com/video/\(bvid)")
                else {
                    return nil
                }
                let arc = episode.dictionaryValue(at: ["arc"])
                let rawTitle = episode.stringValue(at: ["title"])
                    ?? episode.stringValue(at: ["long_title"])
                    ?? arc?.stringValue(at: ["title"])
                let badge = episode.stringValue(at: ["badge"])
                    ?? episode.dictionaryValue(at: ["badge_info"])?.stringValue(at: ["text"])
                    ?? ""
                return .init(
                    id: bvid,
                    title: rawTitle?.nilIfBlank ?? "视频",
                    subtitle: bvid,
                    badge: badge,
                    targetURL: targetURL,
                    isCurrent: bvid.caseInsensitiveCompare(currentBvid) == .orderedSame
                )
            }

            guard !episodes.isEmpty else {
                return nil
            }

            return .init(id: "ugc-\(groupTitle)", title: groupTitle, items: episodes)
        }
    }

    private func fetchComments(oid: String, type: Int, referer: String) async throws -> [FocusVideoDetail.Comment] {
        let query = try await signedWbiQuery(
            parameters: [
                "type": String(type),
                "oid": oid,
                "pn": "1",
                "ps": "20",
                "sort": "2",
            ],
            referer: referer
        )
        let root = try await requestObject(
            urlString: "https://api.bilibili.com/x/v2/reply/wbi/main?\(query)",
            referer: referer
        )
        guard root.intValue(at: ["code"]) == 0 else {
            return []
        }

        let replies = root.arrayValue(at: ["data", "replies"]) ?? []
        return replies.enumerated().compactMap { index, item in
            parseComment(from: item, fallbackIndex: index)
        }
    }

    private func parseComment(from object: JSONObject, fallbackIndex: Int) -> FocusVideoDetail.Comment? {
        guard let member = object.dictionaryValue(at: ["member"]),
              let content = object.dictionaryValue(at: ["content"]),
              let message = content.stringValue(at: ["message"])?.nilIfBlank
        else {
            return nil
        }

        let likeCount = Int64(object.intValue(at: ["like"]) ?? 0)
        let replyCount = Int64(object.intValue(at: ["rcount"]) ?? 0)
        let publishTime = Int64(object.intValue(at: ["ctime"]) ?? 0)
        let avatarURL = Self.normalizedURL(member.stringValue(at: ["avatar"]))
        let id = object.stringValue(at: ["rpid_str"])
            ?? object.stringValue(at: ["rpid"])
            ?? "comment-\(fallbackIndex)"

        return .init(
            id: id,
            author: member.stringValue(at: ["uname"])?.nilIfBlank ?? "用户",
            avatarURL: avatarURL,
            content: message,
            likeText: likeCount > 0 ? "\(Self.formatCount(likeCount))赞" : "",
            replyText: replyCount > 0 ? "\(Self.formatCount(replyCount))回复" : "",
            timeText: Self.formatCommentTime(publishTime)
        )
    }

    private func requestObject(urlString: String, referer: String?) async throws -> JSONObject {
        guard let url = URL(string: urlString) else {
            throw ServiceError.invalidURL
        }
        let data = try await requestData(url: url, referer: referer)
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw ServiceError.requestFailed("接口返回格式错误")
        }
        return object
    }

    private func requestData(url: URL, referer: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Origin")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request = await cookieProvider.attachCookies(to: request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw ServiceError.requestFailed("网络请求失败")
        }
        return data
    }

    private func signedWbiQuery(parameters: [String: String], referer: String) async throws -> String {
        let mixinKey = try await currentWbiKey(referer: referer)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        var queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(.init(name: "wts", value: timestamp))
        queryItems.sort { $0.name < $1.name }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        let encoded = queryItems.map { item in
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
        let rid = Self.md5Hex(encoded + mixinKey)
        return encoded + "&w_rid=" + rid
    }

    private func currentWbiKey(referer: String) async throws -> String {
        if let cachedWbiKey, cachedWbiExpiration > Date() {
            return cachedWbiKey
        }

        let root = try await requestObject(urlString: "https://api.bilibili.com/x/web-interface/nav", referer: referer)
        guard root.intValue(at: ["code"]) == 0,
              let imgURL = root.stringValue(at: ["data", "wbi_img", "img_url"]),
              let subURL = root.stringValue(at: ["data", "wbi_img", "sub_url"])
        else {
            throw ServiceError.requestFailed("WBI 签名不可用")
        }

        let imgKey = URL(string: imgURL)?.deletingPathExtension().lastPathComponent ?? ""
        let subKey = URL(string: subURL)?.deletingPathExtension().lastPathComponent ?? ""
        let mixinKey = Self.mixinKey(imgKey: imgKey, subKey: subKey)
        cachedWbiKey = mixinKey
        cachedWbiExpiration = Date().addingTimeInterval(30 * 60)
        return mixinKey
    }

    private static func mixinKey(imgKey: String, subKey: String) -> String {
        let source = Array((imgKey + subKey))
        return String(wbiMixinTable.compactMap { index in
            guard index < source.count else { return nil }
            return source[index]
        }.prefix(32))
    }

    private static func md5Hex(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func extractBvid(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if let videoIndex = components.firstIndex(of: "video"), components.indices.contains(videoIndex + 1) {
            let candidate = components[videoIndex + 1]
            if candidate.lowercased().hasPrefix("bv") {
                return candidate
            }
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let bvid = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare("bvid") == .orderedSame })?.value,
           !bvid.isEmpty {
            return bvid
        }
        return nil
    }

    private static func extractPageNumber(from url: URL) -> Int? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "p" })?.value.flatMap(Int.init)
    }

    private static func resolveCID(from data: JSONObject, currentPageNumber: Int?) -> Int64? {
        if let pages = data.arrayValue(at: ["pages"]) {
            if let currentPageNumber,
               let page = pages.first(where: { $0.intValue(at: ["page"]) == currentPageNumber }),
               let cid = page.intValue(at: ["cid"]) {
                return Int64(cid)
            }
            if let page = pages.first,
               let cid = page.intValue(at: ["cid"]) {
                return Int64(cid)
            }
        }
        return nil
    }

    private static func normalizedURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        if raw.lowercased().hasPrefix("http://") {
            return URL(string: "https://" + raw.dropFirst("http://".count))
        }
        return URL(string: raw)
    }

    private static func extractStreamResource(from root: JSONObject) -> FocusVideoDetail.Playback.StreamResource {
        guard root.intValue(at: ["code"]) == 0 else {
            return .init(videoURL: nil, audioURL: nil)
        }

        if let videos = root.value(at: ["data", "dash", "video"]) as? [[String: Any]] {
            let sorted = videos.sorted { left, right in
                let leftID = left.intValue(at: ["id"]) ?? 0
                let rightID = right.intValue(at: ["id"]) ?? 0
                return leftID > rightID
            }
            let bestVideoURL = sorted.first.flatMap { best in
                normalizedURL(best.stringValue(at: ["baseUrl"]) ?? best.stringValue(at: ["base_url"]))
            }
            let audioURL = (root.value(at: ["data", "dash", "audio"]) as? [[String: Any]])?
                .first
                .flatMap { audio in
                    normalizedURL(audio.stringValue(at: ["baseUrl"]) ?? audio.stringValue(at: ["base_url"]))
                }
            return .init(videoURL: bestVideoURL, audioURL: audioURL)
        }

        if let durl = root.arrayValue(at: ["data", "durl"]),
           let first = durl.first,
           let url = normalizedURL(first.stringValue(at: ["url"]))
        {
            return .init(videoURL: url, audioURL: nil)
        }

        return .init(videoURL: nil, audioURL: nil)
    }

    private static func extractSubtitles(from root: JSONObject) -> [FocusVideoDetail.Playback.Subtitle] {
        guard root.intValue(at: ["code"]) == 0,
              let subtitles = root.arrayValue(at: ["data", "subtitle", "subtitles"])
        else {
            return []
        }

        return subtitles.compactMap { item in
            guard let rawURL = item.stringValue(at: ["subtitle_url"]) ?? item.stringValue(at: ["url"]),
                  let url = normalizedURL(rawURL)
            else {
                return nil
            }

            let language = item.stringValue(at: ["lan"])?.nilIfBlank ?? ""
            let title = item.stringValue(at: ["lan_doc"])?.nilIfBlank
                ?? item.stringValue(at: ["subtitle_url"])?.nilIfBlank
                ?? "字幕"

            return .init(
                id: item.stringValue(at: ["id_str"])?.nilIfBlank
                    ?? item.stringValue(at: ["id"])?.nilIfBlank
                    ?? language
                    ?? UUID().uuidString,
                language: language,
                title: title,
                url: url
            )
        }
    }

    private static func formatCount(_ value: Int64) -> String {
        switch value {
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private static func formatDuration(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%lld:%02lld:%02lld", hours, minutes, remainder)
        }
        return String(format: "%lld:%02lld", minutes, remainder)
    }

    private static func formatCommentTime(_ seconds: Int64) -> String {
        guard seconds > 0 else { return "" }
        let now = Int64(Date().timeIntervalSince1970)
        let delta = max(now - seconds, 0)
        switch delta {
        case 0 ..< 60:
            return "刚刚"
        case 60 ..< 3600:
            return "\(max(delta / 60, 1))分钟前"
        case 3600 ..< 86_400:
            return "\(max(delta / 3600, 1))小时前"
        case 86_400 ..< 604_800:
            return "\(max(delta / 86_400, 1))天前"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func dictionaryValue(at path: [String]) -> [String: Any]? {
        value(at: path) as? [String: Any]
    }

    func arrayValue(at path: [String]) -> [[String: Any]]? {
        value(at: path) as? [[String: Any]]
    }

    func stringValue(at path: [String]) -> String? {
        if let string = value(at: path) as? String {
            return string
        }
        if let number = value(at: path) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func intValue(at path: [String]) -> Int? {
        if let int = value(at: path) as? Int {
            return int
        }
        if let number = value(at: path) as? NSNumber {
            return number.intValue
        }
        if let string = value(at: path) as? String {
            return Int(string)
        }
        return nil
    }

    func value(at path: [String]) -> Any? {
        guard let key = path.first else {
            return self
        }
        let next = self[key]
        guard path.count > 1, let dictionary = next as? [String: Any] else {
            return next
        }
        return dictionary.value(at: Array(path.dropFirst()))
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
