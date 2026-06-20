(() => {
  const incomingConfig = __FOCUS_CONFIG_JSON__;
  const incomingRules = __FOCUS_RULES_JSON__;
  const phase = "__FOCUS_PHASE__";
  const runtimeKey = "__FOCUS_RUNTIME__";
  const configKey = "__FOCUS_CONFIG__";
  const stylePrefix = "bili-focus-style-";
  const scriptStateKey = "__FOCUS_FEATURE_SCRIPT_STATE__";

  function makeStyleId(ruleId, featureId) {
    return (stylePrefix + ruleId + "-" + featureId).replace(/[^a-zA-Z0-9_-]/g, "-");
  }

  function createRuntime() {
    const state = {
      observerInstalled: false,
      historyInstalled: false,
      applyTimer: null,
      lastApplyAt: 0,
      featureScriptState: window[scriptStateKey] || {}
    };

    function currentConfig() {
      return window[configKey] || {};
    }

    function postDebug(message, extra) {
      if (!currentConfig().debugMode) {
        return;
      }

      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.logDebug) {
          window.webkit.messageHandlers.logDebug.postMessage({
            message,
            extra: extra || null,
            url: location.href
          });
        }
      } catch (_) {}

      try {
        console.debug("[Focus]", message, extra || "");
      } catch (_) {}
    }

    function ensureStyle(styleId, css) {
      if (!css) {
        return;
      }

      let style = document.getElementById(styleId);
      if (!style) {
        style = document.createElement("style");
        style.id = styleId;
        (document.head || document.documentElement).appendChild(style);
      }

      if (style.textContent !== css) {
        style.textContent = css;
      }
    }

    function removeStyle(styleId) {
      const style = document.getElementById(styleId);
      if (style) {
        style.remove();
      }
    }

    function ensureViewport(content) {
      if (!content) {
        return;
      }

      let viewport = document.querySelector('meta[name="viewport"]');
      if (!viewport) {
        viewport = document.createElement("meta");
        viewport.name = "viewport";
        (document.head || document.documentElement).appendChild(viewport);
      }
      viewport.content = content;
    }

    function canonicalizeBilibiliURL(rawValue) {
      try {
        const url = new URL(rawValue, location.href);
        const host = (url.hostname || "").toLowerCase();
        const path = (url.pathname || "").toLowerCase();
        const isBilibiliHost = host === "www.bilibili.com" || host === "bilibili.com" || host === "m.bilibili.com";

        if (isBilibiliHost && (path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0)) {
          url.hostname = "www.bilibili.com";
        }

        return url.toString();
      } catch (_) {
        return rawValue;
      }
    }

    function featureState(ruleId, featureId) {
      const key = ruleId + "::" + featureId;
      if (!state.featureScriptState[key]) {
        state.featureScriptState[key] = {};
      }
      window[scriptStateKey] = state.featureScriptState;
      return state.featureScriptState[key];
    }

    function runFeatureScript(rule, feature) {
      if (!feature.script) {
        return;
      }

      try {
        const executor = new Function("config", "helpers", feature.script);
        executor(currentConfig(), {
          canonicalizeBilibiliURL,
          featureState: featureState(rule.id, feature.featureId),
          postDebug,
        });
      } catch (error) {
        postDebug("featureScriptError", {
          ruleId: rule.id,
          featureId: feature.featureId,
          message: String(error && error.message ? error.message : error)
        });
      }
    }

    function matchesRule(rule) {
      const host = location.hostname;
      const path = location.pathname || "/";
      const hostMatch = !rule.hosts || rule.hosts.length === 0 || rule.hosts.indexOf(host) >= 0;
      const pathMatch = !rule.pathPrefixes || rule.pathPrefixes.length === 0 || rule.pathPrefixes.some((prefix) => path.indexOf(prefix) === 0);
      return hostMatch && pathMatch;
    }

    function isFeatureEnabled(feature) {
      const key = feature.settingKey;
      if (!key) {
        return true;
      }
      return !!currentConfig()[key];
    }

    function clearRule(rule) {
      (rule.features || []).forEach((feature) => removeStyle(makeStyleId(rule.id, feature.featureId)));
    }

    function applyRule(rule) {
      if (!matchesRule(rule)) {
        clearRule(rule);
        return;
      }

      if (rule.metaViewport) {
        ensureViewport(rule.metaViewport);
      }

      (rule.features || []).forEach((feature) => {
        const styleId = makeStyleId(rule.id, feature.featureId);
        if (isFeatureEnabled(feature)) {
          ensureStyle(styleId, feature.css);
          runFeatureScript(rule, feature);
        } else {
          removeStyle(styleId);
        }
      });
    }

    function applyPhase(requestedPhase) {
      const applicableRules = (window.__FOCUS_RULES__ || []).filter((rule) => rule.runPhase === requestedPhase);
      applicableRules.forEach(applyRule);
      postDebug("applyPhase", requestedPhase);
    }

    function applyAll() {
      applyPhase("documentStart");
      applyPhase("documentEnd");
    }

    function scheduleApply(reason) {
      clearTimeout(state.applyTimer);
      const now = Date.now();
      const isVideoPage = location.pathname.indexOf("/video/") === 0 || location.pathname.indexOf("/bangumi/play/") === 0;
      const delay = isVideoPage ? Math.max(180, 280 - (now - state.lastApplyAt)) : 80;
      state.applyTimer = setTimeout(() => {
        state.lastApplyAt = Date.now();
        applyAll();
        postDebug("scheduleApply", reason);
      }, Math.max(delay, 40));
    }

    function isIgnoredPlayerMutationTarget(node) {
      if (!node || !node.closest) {
        return false;
      }

      return !!node.closest([
        "#bilibili-player",
        "#playerWrap",
        ".player-wrap",
        ".bpx-player-container",
        ".bpx-player-video-wrap",
        ".bpx-player-video-area",
        ".bpx-player-row-dm-wrap",
        ".bpx-player-video-dm-wrap",
        ".bpx-player-dm-wrap",
        ".bilibili-player-video-danmaku"
      ].join(","));
    }

    function shouldScheduleForMutations(mutations) {
      if (!mutations || mutations.length === 0) {
        return false;
      }

      const path = location.pathname || "/";
      const isVideoPage = path.indexOf("/video/") === 0 || path.indexOf("/bangumi/play/") === 0;
      if (!isVideoPage) {
        return true;
      }

      const importantVideoSelectors = [
        "#arc_toolbar_report",
        "#commentapp",
        "bili-comments",
        ".video-toolbar-container",
        ".video-pod",
        ".video-pod__body",
        ".video-pod__list",
        ".multi-page",
        ".left-container",
        ".right-container"
      ].join(",");

      return mutations.some((mutation) => {
        const target = mutation.target;
        if (target && target.nodeType === 1 && !isIgnoredPlayerMutationTarget(target)) {
          return true;
        }

        const changedNodes = []
          .concat(Array.from(mutation.addedNodes || []))
          .concat(Array.from(mutation.removedNodes || []));

        return changedNodes.some((node) => {
          if (!node || node.nodeType !== 1) {
            return false;
          }

          if (!isIgnoredPlayerMutationTarget(node)) {
            return true;
          }

          return !!node.matches?.(importantVideoSelectors)
            || !!node.querySelector?.(importantVideoSelectors);
        });
      });
    }

    function installHistoryHooks() {
      if (state.historyInstalled) {
        return;
      }

      state.historyInstalled = true;
      const wrap = (method) => {
        const original = history[method];
        history[method] = function () {
          const result = original.apply(this, arguments);
          scheduleApply(method);
          return result;
        };
      };

      wrap("pushState");
      wrap("replaceState");
      window.addEventListener("popstate", () => scheduleApply("popstate"));
      window.addEventListener("hashchange", () => scheduleApply("hashchange"));
    }

    function installObserver() {
      if (state.observerInstalled) {
        return;
      }

      state.observerInstalled = true;
      const observer = new MutationObserver((mutations) => {
        if (shouldScheduleForMutations(mutations)) {
          scheduleApply("mutation");
        }
      });
      observer.observe(document.documentElement, {
        childList: true,
        subtree: true
      });
    }

    return {
      update(config, rules) {
        window[configKey] = config;
        window.__FOCUS_RULES__ = rules;
      },
      applyPhase,
      applyAll,
      installHistoryHooks,
      installObserver
    };
  }

  const runtime = window[runtimeKey] || createRuntime();
  runtime.update(incomingConfig, incomingRules);
  window[runtimeKey] = runtime;

  if (phase === "documentEnd") {
    runtime.installHistoryHooks();
    runtime.installObserver();
  }

  runtime.applyPhase(phase);
})();
