import Foundation

public protocol CookieSnapshotProvider: Sendable {
    func loadCookies() async -> [HTTPCookie]
    func attachCookies(to request: URLRequest) -> URLRequest
}

public extension CookieSnapshotProvider {
    func attachCookies(to request: URLRequest) -> URLRequest {
        request
    }
}
