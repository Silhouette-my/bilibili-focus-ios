import Foundation

public struct FocusVideoDetail: Sendable, Equatable {
    public struct Playback: Sendable, Equatable {
        public struct StreamResource: Sendable, Equatable {
            public let videoURL: URL?
            public let audioURL: URL?

            public init(videoURL: URL?, audioURL: URL?) {
                self.videoURL = videoURL
                self.audioURL = audioURL
            }
        }

        public struct Subtitle: Sendable, Equatable, Identifiable {
            public let id: String
            public let language: String
            public let title: String
            public let url: URL

            public init(id: String, language: String, title: String, url: URL) {
                self.id = id
                self.language = language
                self.title = title
                self.url = url
            }
        }

        public let streamURL: URL?
        public let streamResource: StreamResource
        public let posterURL: URL?
        public let duration: TimeInterval
        public let subtitles: [Subtitle]

        public init(streamURL: URL?, streamResource: StreamResource, posterURL: URL?, duration: TimeInterval, subtitles: [Subtitle]) {
            self.streamURL = streamURL
            self.streamResource = streamResource
            self.posterURL = posterURL
            self.duration = duration
            self.subtitles = subtitles
        }
    }

    public struct Relation: Sendable, Equatable {
        public let isLiked: Bool
        public let coinCount: Int
        public let isFavorited: Bool

        public init(isLiked: Bool, coinCount: Int, isFavorited: Bool) {
            self.isLiked = isLiked
            self.coinCount = coinCount
            self.isFavorited = isFavorited
        }
    }

    public struct Stat: Sendable, Equatable {
        public let playText: String
        public let danmakuText: String
        public let likeText: String
        public let coinText: String
        public let favoriteText: String
        public let shareText: String

        public init(
            playText: String,
            danmakuText: String,
            likeText: String,
            coinText: String,
            favoriteText: String,
            shareText: String
        ) {
            self.playText = playText
            self.danmakuText = danmakuText
            self.likeText = likeText
            self.coinText = coinText
            self.favoriteText = favoriteText
            self.shareText = shareText
        }
    }

    public struct Author: Sendable, Equatable {
        public let mid: Int64
        public let name: String
        public let avatarURL: URL?
        public let spaceURL: URL?

        public init(mid: Int64, name: String, avatarURL: URL?, spaceURL: URL?) {
            self.mid = mid
            self.name = name
            self.avatarURL = avatarURL
            self.spaceURL = spaceURL
        }
    }

    public struct EpisodeGroup: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let items: [EpisodeItem]

        public init(id: String, title: String, items: [EpisodeItem]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    public struct EpisodeItem: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let badge: String
        public let targetURL: URL
        public let isCurrent: Bool

        public init(id: String, title: String, subtitle: String, badge: String, targetURL: URL, isCurrent: Bool) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.badge = badge
            self.targetURL = targetURL
            self.isCurrent = isCurrent
        }
    }

    public struct Comment: Sendable, Equatable, Identifiable {
        public let id: String
        public let author: String
        public let avatarURL: URL?
        public let content: String
        public let likeText: String
        public let replyText: String
        public let timeText: String

        public init(id: String, author: String, avatarURL: URL?, content: String, likeText: String, replyText: String, timeText: String) {
            self.id = id
            self.author = author
            self.avatarURL = avatarURL
            self.content = content
            self.likeText = likeText
            self.replyText = replyText
            self.timeText = timeText
        }
    }

    public let bvid: String
    public let aid: Int64
    public let cid: Int64?
    public let title: String
    public let author: Author
    public let stat: Stat
    public let playback: Playback
    public let relation: Relation
    public let episodeGroups: [EpisodeGroup]
    public let comments: [Comment]

    public init(
        bvid: String,
        aid: Int64,
        cid: Int64?,
        title: String,
        author: Author,
        stat: Stat,
        playback: Playback,
        relation: Relation,
        episodeGroups: [EpisodeGroup],
        comments: [Comment]
    ) {
        self.bvid = bvid
        self.aid = aid
        self.cid = cid
        self.title = title
        self.author = author
        self.stat = stat
        self.playback = playback
        self.relation = relation
        self.episodeGroups = episodeGroups
        self.comments = comments
    }
}
