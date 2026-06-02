import Foundation

enum FocusScriptSource {
    static let runtimeTemplate: String = {
        guard let url = FocusBundle.module.url(forResource: "focus-runtime", withExtension: "js") else {
            assertionFailure("Missing focus-runtime.js resource")
            return "console.warn('Bilibili Focus: missing focus-runtime.js');"
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            assertionFailure("Unable to load focus-runtime.js: \(error)")
            return "console.warn('Bilibili Focus: unable to load focus-runtime.js');"
        }
    }()
}
