import FocusCore
import Foundation

private enum FocusUserscriptBuilderError: Error, CustomStringConvertible {
    case missingOutputPath
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingOutputPath:
            return "Missing value for --output"
        case let .unknownArgument(argument):
            return "Unknown argument: \(argument)"
        }
    }
}

private struct FocusUserscriptBuildConfiguration {
    let outputFile: URL
    let legacyOutputFile: URL

    init(arguments: [String], workingDirectory: URL) throws {
        var outputPath = "Userscript/bilibili-focus.user.js"
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw FocusUserscriptBuilderError.missingOutputPath
                }
                outputPath = arguments[index]
            default:
                throw FocusUserscriptBuilderError.unknownArgument(argument)
            }
            index += 1
        }

        if outputPath.hasPrefix("/") {
            outputFile = URL(fileURLWithPath: outputPath)
        } else {
            outputFile = workingDirectory.appendingPathComponent(outputPath)
        }

        legacyOutputFile = workingDirectory.appendingPathComponent("bilibili-FOCUS.js")
    }
}

private struct FocusUserscriptAssetBuilder {
    let outputFile: URL
    let legacyOutputFile: URL

    func build() throws {
        let fileManager = FileManager.default
        let outputDirectory = outputFile.deletingLastPathComponent()
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacyOutputFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let defaultsJSON = try encode(FocusSettings.defaults)
        let documentStartScript = try FocusScriptBuilder.makeRuntimeScript(
            for: .documentStart,
            configExpression: "window.__FOCUS_CONFIG__"
        )
        let documentEndScript = try FocusScriptBuilder.makeRuntimeScript(
            for: .documentEnd,
            configExpression: "window.__FOCUS_CONFIG__"
        )

        let script = """
        // ==UserScript==
        // @name         Bilibili Focus
        // @namespace    https://github.com/silhouette-my/bilibili-focus
        // @version      5.0.0
        // @description  Shared FocusCore-based Bilibili focus mode for Safari Userscripts on iPhone.
        // @match        *://*.bilibili.com/*
        // @match        *://bilibili.com/*
        // @grant        GM_getValue
        // @grant        GM_setValue
        // @run-at       document-start
        // ==/UserScript==

        (() => {
          const storageKey = "\(FocusSettings.storageKey)";
          const defaultConfig = \(defaultsJSON);

          const normalizeConfig = (value) => ({
            ...defaultConfig,
            ...(value || {})
          });

          const parseStoredConfig = (rawValue) => {
            if (!rawValue) {
              return null;
            }

            if (typeof rawValue === "object") {
              return rawValue;
            }

            if (typeof rawValue === "string") {
              try {
                return JSON.parse(rawValue);
              } catch (_) {
                return null;
              }
            }

            return null;
          };

          const readStoredConfig = () => {
            try {
              if (typeof GM_getValue === "function") {
                const stored = GM_getValue(storageKey, null);
                const parsed = parseStoredConfig(stored);
                if (parsed) {
                  return normalizeConfig(parsed);
                }
              }
            } catch (_) {}

            try {
              const stored = localStorage.getItem(storageKey);
              const parsed = parseStoredConfig(stored);
              if (parsed) {
                return normalizeConfig(parsed);
              }
            } catch (_) {}

            return normalizeConfig(null);
          };

          const persistConfig = () => {
            const serialized = JSON.stringify(window.__FOCUS_CONFIG__);
            try {
              if (typeof GM_setValue === "function") {
                GM_setValue(storageKey, serialized);
              }
            } catch (_) {}

            try {
              localStorage.setItem(storageKey, serialized);
            } catch (_) {}
          };

          const redirectTargetFor = (config) => config.defaultEntry === "search"
            ? "https://search.bilibili.com/all"
            : "https://t.bilibili.com/";

          const isHomepage = () => {
            const host = String(location.hostname || "").toLowerCase();
            const path = location.pathname || "/";
            const isBilibiliHost = host === "www.bilibili.com" || host === "bilibili.com" || host === "m.bilibili.com";
            return isBilibiliHost && (path === "/" || path === "/index.html" || path === "");
          };

          const maybeRedirect = () => {
            const config = window.__FOCUS_CONFIG__;
            if (!config.redirectEnabled || !isHomepage()) {
              return false;
            }

            const target = redirectTargetFor(config);
            if (location.href === target) {
              return false;
            }

            location.replace(target);
            return true;
          };

          const refreshRuntime = () => {
            const runtime = window.__FOCUS_RUNTIME__;
            if (!runtime) {
              return;
            }

            runtime.update(window.__FOCUS_CONFIG__, window.__FOCUS_RULES__ || []);
            runtime.applyAll();
          };

          const installSettingsPanel = () => {
            if (document.getElementById("bili-focus-panel")) {
              return;
            }

            const panel = document.createElement("details");
            panel.id = "bili-focus-panel";
            panel.innerHTML = `
              <summary>Focus</summary>
              <div class="focus-panel-body">
                <label><span>首页跳转</span><input data-focus-key="redirectEnabled" type="checkbox"></label>
                <label><span>动态去干扰</span><input data-focus-key="dynamicMaskEnabled" type="checkbox"></label>
                <label><span>搜索去干扰</span><input data-focus-key="searchMaskEnabled" type="checkbox"></label>
                <label><span>播放去干扰</span><input data-focus-key="playerMaskEnabled" type="checkbox"></label>
                <label><span>调试日志</span><input data-focus-key="debugMode" type="checkbox"></label>
                <label class="focus-panel-select">
                  <span>默认入口</span>
                  <select data-focus-key="defaultEntry">
                    <option value="dynamic">动态</option>
                    <option value="search">搜索</option>
                  </select>
                </label>
                <button type="button" data-focus-reset="true">恢复默认</button>
              </div>
            `;

            const style = document.createElement("style");
            style.id = "bili-focus-panel-style";
            style.textContent = `
              #bili-focus-panel {
                position: fixed;
                right: 12px;
                bottom: 18px;
                z-index: 2147483646;
                width: min(240px, calc(100vw - 24px));
                border-radius: 18px;
                overflow: hidden;
                background: rgba(255, 255, 255, 0.86);
                border: 1px solid rgba(148, 163, 184, 0.25);
                box-shadow: 0 16px 40px rgba(15, 23, 42, 0.16);
                backdrop-filter: blur(18px);
                color: #0f172a;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              }

              #bili-focus-panel summary {
                list-style: none;
                cursor: pointer;
                padding: 10px 14px;
                font-size: 13px;
                font-weight: 800;
                letter-spacing: 0.04em;
                text-transform: uppercase;
                color: #0284c7;
              }

              #bili-focus-panel summary::-webkit-details-marker {
                display: none;
              }

              #bili-focus-panel .focus-panel-body {
                display: grid;
                gap: 10px;
                padding: 0 14px 14px;
              }

              #bili-focus-panel label,
              #bili-focus-panel button {
                display: flex;
                align-items: center;
                justify-content: space-between;
                gap: 12px;
                width: 100%;
                min-width: 0;
                padding: 0;
                border: 0;
                background: transparent;
                color: inherit;
                font-size: 13px;
                font-weight: 600;
              }

              #bili-focus-panel input[type="checkbox"] {
                width: 18px;
                height: 18px;
                accent-color: #0ea5e9;
              }

              #bili-focus-panel select {
                min-width: 92px;
                padding: 7px 10px;
                border-radius: 12px;
                border: 1px solid rgba(148, 163, 184, 0.35);
                background: rgba(255, 255, 255, 0.9);
              }

              #bili-focus-panel button[data-focus-reset="true"] {
                justify-content: center;
                margin-top: 4px;
                min-height: 38px;
                border-radius: 12px;
                background: #e0f2fe;
                color: #0369a1;
                font-weight: 700;
              }
            `;

            document.documentElement.appendChild(style);
            document.body.appendChild(panel);

            const syncPanelFromConfig = () => {
              const config = window.__FOCUS_CONFIG__;
              panel.querySelectorAll("[data-focus-key]").forEach((field) => {
                const key = field.getAttribute("data-focus-key");
                if (!key) {
                  return;
                }

                if (field instanceof HTMLInputElement && field.type === "checkbox") {
                  field.checked = Boolean(config[key]);
                } else if (field instanceof HTMLSelectElement) {
                  field.value = String(config[key] || "");
                }
              });
            };

            panel.addEventListener("change", (event) => {
              const field = event.target;
              if (!(field instanceof HTMLInputElement || field instanceof HTMLSelectElement)) {
                return;
              }

              const key = field.getAttribute("data-focus-key");
              if (!key) {
                return;
              }

              const nextValue = field instanceof HTMLInputElement && field.type === "checkbox"
                ? field.checked
                : field.value;
              window.__FOCUS_CONFIG__ = normalizeConfig({
                ...window.__FOCUS_CONFIG__,
                [key]: nextValue
              });
              persistConfig();
              refreshRuntime();
            });

            panel.querySelector("[data-focus-reset=\"true\"]")?.addEventListener("click", () => {
              window.__FOCUS_CONFIG__ = normalizeConfig(null);
              persistConfig();
              syncPanelFromConfig();
              refreshRuntime();
            });

            syncPanelFromConfig();
          };

          window.__FOCUS_CONFIG__ = readStoredConfig();

          if (maybeRedirect()) {
            return;
          }

        \(documentStartScript)

          const runDocumentEndPhase = () => {
            installSettingsPanel();
        \(documentEndScript)
          };

          if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", runDocumentEndPhase, { once: true });
          } else {
            runDocumentEndPhase();
          }
        })();
        """

        try script.write(to: outputFile, atomically: true, encoding: .utf8)
        try script.write(to: legacyOutputFile, atomically: true, encoding: .utf8)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

@main
private enum FocusUserscriptBuilderMain {
    static func main() throws {
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let configuration = try FocusUserscriptBuildConfiguration(
            arguments: Array(CommandLine.arguments.dropFirst()),
            workingDirectory: workingDirectory
        )

        do {
            try FocusUserscriptAssetBuilder(
                outputFile: configuration.outputFile,
                legacyOutputFile: configuration.legacyOutputFile
            ).build()
        } catch {
            FileHandle.standardError.write(Data("FocusUserscriptBuilder failed: \(error)\n".utf8))
            throw error
        }
    }
}
