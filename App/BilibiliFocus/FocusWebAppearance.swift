#if canImport(UIKit)
import Foundation

enum FocusWebAppearance {
    static func script(isDarkMode: Bool) -> String {
        let darkLiteral = isDarkMode ? "true" : "false"
        return """
        (function() {
          var isDark = \(darkLiteral);
          var root = document.documentElement;
          if (!root) {
            return;
          }
          var body = document.body;
          root.classList.toggle('night-mode', isDark);
          root.classList.toggle('light-mode', !isDark);
          root.setAttribute('data-focus-theme', isDark ? 'dark' : 'light');
          root.setAttribute('data-focus-platform', 'ios');
          root.style.colorScheme = isDark ? 'dark' : 'light';
          root.style.backgroundColor = isDark ? '#0F1115' : '#FFFFFF';
          if (body) {
            body.classList.toggle('night-mode', isDark);
            body.style.colorScheme = isDark ? 'dark' : 'light';
            if (!body.style.backgroundColor || body.style.backgroundColor === 'transparent' || body.style.backgroundColor === 'rgba(0, 0, 0, 0)') {
              body.style.backgroundColor = isDark ? '#0F1115' : '#FFFFFF';
            }
          }
          var meta = document.querySelector('meta[name="color-scheme"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'color-scheme';
            (document.head || root).appendChild(meta);
          }
          meta.content = isDark ? 'dark light' : 'light dark';
        })();
        """
    }
}
#endif
