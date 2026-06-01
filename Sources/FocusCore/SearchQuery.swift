import Foundation

public struct SearchQuery: Equatable, Sendable {
    public let keyword: String

    public init(keyword: String) {
        self.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resultURL: URL {
        var components = URLComponents(string: "https://search.bilibili.com/all")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
        ]
        return components.url!
    }
}
