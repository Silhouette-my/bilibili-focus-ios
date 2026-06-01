import Foundation

public struct FocusPageRule: Codable, Equatable, Sendable {
    public enum RunPhase: String, Codable, Sendable {
        case documentStart
        case documentEnd
    }

    public let id: String
    public let hosts: [String]
    public let pathPrefixes: [String]
    public let runPhase: RunPhase
    public let metaViewport: String?
    public let features: [FocusFeature]

    public init(
        id: String,
        hosts: [String] = [],
        pathPrefixes: [String] = [],
        runPhase: RunPhase,
        metaViewport: String? = nil,
        features: [FocusFeature]
    ) {
        self.id = id
        self.hosts = hosts
        self.pathPrefixes = pathPrefixes
        self.runPhase = runPhase
        self.metaViewport = metaViewport
        self.features = features
    }

    public func match(host: String, path: String) -> Bool {
        let matchesHost = hosts.isEmpty || hosts.contains(host)
        let normalizedPath = path.isEmpty ? "/" : path
        let matchesPath = pathPrefixes.isEmpty || pathPrefixes.contains { normalizedPath.hasPrefix($0) }
        return matchesHost && matchesPath
    }
}
