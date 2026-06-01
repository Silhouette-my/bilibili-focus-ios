// ==UserScript==
// @name         Bilibili FOCUS
// @namespace    http://tampermonkey.net/
// @version      4.0
// @description  专注模式：拦截首页推荐，放行动态，彻底重构桌面版动态页适配手机
// @author       Silhouette-my
// @match        *://*.bilibili.com/*
// @match        *://bilibili.com/*
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-start
// ==/UserScript==

(function () {
  'use strict';

  // 读取配置
  const getVal = (key, defaultVal) => typeof GM_getValue === 'function' ? GM_getValue(key, defaultVal) : defaultVal;
  const setVal = (key, val) => typeof GM_setValue === 'function' ? GM_setValue(key, val) : null;

  const config = {
    redirectEnabled: getVal('redirectEnabled', true),
    playerMaskEnabled: getVal('playerMaskEnabled', true),
    searchMaskEnabled: getVal('searchMaskEnabled', true)
  };

  function injectStyle(css) {
    const style = document.createElement('style');
    style.textContent = css;
    if (document.head) {
      document.head.appendChild(style);
    } else {
      const observer = new MutationObserver(() => {
        if (document.head) {
          document.head.appendChild(style);
          observer.disconnect();
        }
      });
      observer.observe(document.documentElement, { childList: true });
    }
  }

  // 注入 Viewport
  function enforceMobileViewport() {
    const host = window.location.hostname;
    if (host === 't.bilibili.com' || host === 'www.bilibili.com') {
      let metaViewport = document.querySelector('meta[name="viewport"]');
      if (!metaViewport) {
        metaViewport = document.createElement('meta');
        metaViewport.name = 'viewport';
        if (document.head) {
          document.head.appendChild(metaViewport);
        } else {
          const observer = new MutationObserver(() => {
            if (document.head) {
              document.head.appendChild(metaViewport);
              observer.disconnect();
            }
          });
          observer.observe(document.documentElement, { childList: true });
        }
      }
      metaViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
    }
  }
  enforceMobileViewport();

  // 重定向逻辑
  function runRedirect() {
    if (!config.redirectEnabled) return;
    const host = window.location.hostname;
    const path = window.location.pathname;
    const isHomepage = (host === 'm.bilibili.com' || host === 'www.bilibili.com' || host === 'bilibili.com') && 
                       (path === '/' || path === '/index.html' || path === '');
    if (isHomepage) {
      window.location.replace("https://m.bilibili.com/search");
    }
  }
  runRedirect();

  function initDOMFeatures() {
    // 1. 控制面板
    function injectControlPanel() {
      if (document.getElementById('bili-focus-panel')) return;
      const panel = document.createElement('div');
      panel.id = 'bili-focus-panel';
      panel.innerHTML = `
        <div class="focus-panel-header">FOCUS</div>
        <div class="focus-toggle-group">
          <label><input type="checkbox" id="gm-toggle-redirect" ${config.redirectEnabled ? 'checked' : ''}> 首页转搜索</label>
          <label><input type="checkbox" id="gm-toggle-player" ${config.playerMaskEnabled ? 'checked' : ''}> 播放页去推荐</label>
          <label><input type="checkbox" id="gm-toggle-search" ${config.searchMaskEnabled ? 'checked' : ''}> 搜索页专注</label>
        </div>
      `;
      injectStyle(`
        #bili-focus-panel { position: fixed; bottom: 20px; right: 20px; width: 140px; background: rgba(28, 28, 30, 0.65); backdrop-filter: blur(24px) saturate(180%); -webkit-backdrop-filter: blur(24px) saturate(180%); border: 1px solid rgba(255, 255, 255, 0.15); border-radius: 16px; padding: 14px; color: #f5f5f7; font-family: -apple-system, sans-serif; z-index: 2147483647; box-shadow: 0 12px 32px rgba(0, 0, 0, 0.4); }
        .focus-panel-header { font-size: 13px; font-weight: 600; margin-bottom: 10px; text-align: center; opacity: 0.9; }
        .focus-toggle-group { display: flex; flex-direction: column; gap: 8px; }
        .focus-toggle-group label { display: flex; align-items: center; font-size: 12px; cursor: pointer; white-space: nowrap; }
        .focus-toggle-group input[type="checkbox"] { margin-right: 6px; accent-color: #0A84FF; width: 14px; height: 14px; }
      `);
      document.body.appendChild(panel);
      document.getElementById('gm-toggle-redirect').addEventListener('change', (e) => setVal('redirectEnabled', e.target.checked));
      document.getElementById('gm-toggle-player').addEventListener('change', (e) => { setVal('playerMaskEnabled', e.target.checked); setTimeout(() => window.location.reload(), 100); });
      document.getElementById('gm-toggle-search').addEventListener('change', (e) => { setVal('searchMaskEnabled', e.target.checked); setTimeout(() => window.location.reload(), 100); });
    }
    injectControlPanel();

    // 2. 动态页排版重构
    if (window.location.hostname === 't.bilibili.com') {
      injectStyle(`
        /* --- 彻底干掉页面的横向滚动条 --- */
        html, body, #app { width: 100% !important; max-width: 100vw !important; overflow-x: hidden !important; margin: 0 !important; padding: 0 !important; }

        /* --- 修复顶部导航栏 --- */
        #bili-header-container, .bili-header, .bili-header__bar { width: 100% !important; min-width: 0 !important; max-width: 100vw !important; overflow: hidden !important; padding: 0 !important; }
        
        /* 屏蔽首页等入口，并将第一个图标改为 FOCUS 贴图并禁用点击 */
        .left-entry { display: flex !important; align-items: center !important; flex-shrink: 0 !important; }
        .left-entry .v-popover-wrap:not(:first-child) { display: none !important; }
        .left-entry .v-popover-wrap:first-child { pointer-events: none !important; width: auto !important; margin-right: 10px !important; }
        .left-entry .v-popover-wrap:first-child * { display: none !important; }
        .left-entry .v-popover-wrap:first-child::after {
            content: "FOCUS" !important;
            display: inline-block !important;
            font-weight: 900 !important;
            font-size: 16px !important;
            color: #0A84FF !important;
            padding: 0 15px !important;
            letter-spacing: 1px !important;
        }

        /* 隐藏右侧多余图标和频道菜单 */
        .right-entry, .bili-header__channel { display: none !important; }
        
        /* 搜索框居中适配 */
        .center-search-container { min-width: 0 !important; width: 100% !important; flex: 1 !important; margin: 0 15px 0 0 !important; }

        /* --- 修复动态内容区 --- */
        .bili-dyn-home--member, .bili-layout, main, .bili-dyn-content { width: 100% !important; min-width: 0 !important; max-width: 100vw !important; margin: 0 !important; padding: 0 !important; display: block !important; box-sizing: border-box !important; }
        aside.left, aside.right, .bili-dyn-sidebar { display: none !important; }

        /* 修复头像被挤压的问题 */
        main > section, .bili-dyn-item, .bili-dyn-pub { 
            width: 100% !important; min-width: 0 !important; max-width: 100vw !important; 
            border-radius: 0 !important; margin-bottom: 8px !important; box-sizing: border-box !important; 
            position: relative !important; 
        }
        /* 恢复头像的绝对定位 */
        .bili-dyn-item__avatar { 
            position: absolute !important; left: 16px !important; top: 16px !important; 
            margin: 0 !important; transform: none !important; 
        }
        /* 强制主内容区留出左侧边距（72px = 48px头像 + 24px间距） */
        .bili-dyn-item__main { 
            padding: 16px 16px 16px 76px !important; 
            width: 100% !important; box-sizing: border-box !important; 
        }
      `);
    }

    // 3. 搜索页
    if (config.searchMaskEnabled && window.location.pathname.startsWith('/search')) {
      injectStyle(`.m-bottom-app-download, .m-nav-bottom, .search-recommend { display: none !important; }`);
    }

    // 4. 播放页
    if (config.playerMaskEnabled && window.location.pathname.startsWith('/video/')) {
      injectStyle(`
        /* 恢复隐藏相关推荐和所有 App 推广按钮 */
        .m-video-related, .m-video2-recom, .m-video-related-wrap, .recom-wrapper, .recom-list, .card-box { display: none !important; } 
        .launch-app-btn, .m-bottom-app-download, .m-video-up-app, .m-nav-bottom, .v-card-module { display: none !important; }
      `);
    }

    // 5. SPA 监听
    let lastUrl = location.href;
    new MutationObserver(() => {
      const url = location.href;
      if (url !== lastUrl) {
        lastUrl = url;
        runRedirect(); 
      }
    }).observe(document, {subtree: true, childList: true});
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initDOMFeatures);
  } else {
    initDOMFeatures();
  }

})();