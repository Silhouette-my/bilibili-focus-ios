import Foundation

public enum FocusEntry: String, Codable, CaseIterable, Sendable {
    case dynamic
    case search

    public var title: String {
        switch self {
        case .dynamic:
            return "动态"
        case .search:
            return "搜索"
        }
    }
}
