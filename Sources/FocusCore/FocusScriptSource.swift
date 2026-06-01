import Foundation

enum FocusScriptSource {
    static let runtimeTemplate: String = {
        guard let url = FocusBundle.module.url(forResource: "focus-runtime", withExtension: "js") else {
            fatalError("Missing focus-runtime.js resource")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            fatalError("Unable to load focus-runtime.js: \(error)")
        }
    }()
}
