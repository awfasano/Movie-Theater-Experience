import SwiftUI
import WebKit

// MARK: - Web View Navigation State (unchanged)
class WebViewNavigationState: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var urlString: String = "https://google.com"
    @Published var pendingRequest: URLRequest? = nil
    let homeURLString: String = "https://google.com"
}

// MARK: - Web Browser View
struct WebBrowserView: View {
    @AppStorage("sentMessageColorHex") private var accentColorHex: String = "#0A84FF"

    @StateObject private var navigationState = WebViewNavigationState()
    @State private var webView = WKWebView()
    @State private var urlFieldText: String = "https://google.com"
    @StateObject private var bookmarkManager = BookmarkManager()
    @State private var showingBookmarks = false

    // Toggle this to switch themes
    @State private var isDarkMode = false

    var body: some View {
        WebViewRepresentable(
            webView: $webView,
            navigationState: navigationState,
            isDarkMode: isDarkMode
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        .navigationTitle("Web Browser")
        .navigationBarTitleDisplayMode(.inline)
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.bottom),
            contentAlignment: .center
        ) {
            VStack {
                Spacer()
                    .frame(height: 20) // Add space between toolbar and bottom edge
                browserControls
            }
        }
        .onChange(of: navigationState.urlString) { _, newValue in
            urlFieldText = newValue
        }
        .sheet(isPresented: $showingBookmarks) {
            BookmarksView(bookmarkManager: bookmarkManager, webView: $webView)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onChange(of: isDarkMode) { _, _ in
            // Call the page helper so SPA pages update immediately
            let fn = isDarkMode ? "__forceDark_apply()" : "__forceDark_remove()"
            webView.evaluateJavaScript(fn, completionHandler: nil)
            // Also hint native color scheme on next nav
            webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        }
    }

    private var browserControls: some View {
        HStack(spacing: 16) {
            // Navigation Buttons
            HStack(spacing: 12) {
                browserNavButton(systemName: "chevron.left", enabled: navigationState.canGoBack) { webView.goBack() }
                browserNavButton(systemName: "chevron.right", enabled: navigationState.canGoForward) { webView.goForward() }
                browserNavButton(systemName: "house.fill", enabled: true) { loadHome() }
                browserNavButton(systemName: navigationState.isLoading ? "xmark" : "arrow.clockwise", enabled: true) {
                    if navigationState.isLoading {
                        webView.stopLoading()
                    } else {
                        _ = webView.reload()
                    }
                }
                browserNavButton(systemName: "book.fill", enabled: true) { showingBookmarks.toggle() }
                browserNavButton(systemName: "plus", enabled: true) {
                    if let url = webView.url {
                        bookmarkManager.addBookmark(name: webView.title ?? "", url: url)
                    }
                }
                browserNavButton(systemName: isDarkMode ? "sun.max.fill" : "moon.fill", enabled: true) {
                    isDarkMode.toggle()
                }
            }

            // URL Input Field
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(urlFieldText.hasPrefix("https://") ? 1 : 0)

                TextField("Enter URL", text: $urlFieldText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .truncationMode(.middle)
                    .onSubmit(loadUrl)
                    .frame(maxWidth: 300)

                if navigationState.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))  // Changed from .thinMaterial to .regularMaterial
            .hoverEffect(.highlight)

            Button(action: loadUrl) {
                Text("Go")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(hex: accentColorHex))
                    .clipShape(Capsule())
            }
            .buttonStyle(HighlightButtonStyle())
            .hoverEffect(.highlight)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))  // Changed from .thinMaterial to .regularMaterial
        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 5)
    }

    private func browserNavButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                // More opaque background circle
                Circle()
                    .fill((Color(hex: accentColorHex) ?? Color.blue).opacity(enabled ? 0.7 : 0.35))  // Increased from 0.15/0.05
                    .frame(width: 36, height: 36)
                    .overlay(
                        // Add a subtle material background for depth
                        Circle()
                            .fill(.regularMaterial)  // Changed from no background to regularMaterial
                            .opacity(0.8)  // Make it quite opaque
                    )
                
                // Icon
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(enabled ? Color.primary : Color.primary.opacity(0.4))  // Slightly more visible when disabled
            }
        }
        .disabled(!enabled)
        .buttonStyle(EnhancedButtonStyle(disabled: !enabled))
        .hoverEffect(.automatic, isEnabled: enabled)
    }

    private func loadUrl() {
        guard var urlString = urlFieldText.trimmed() else { return }
        if urlString.isValidURL {
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            if let url = URL(string: urlString) {
                navigationState.pendingRequest = URLRequest(url: url)
            }
        } else {
            let searchQuery = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.google.com/search?q=\(searchQuery)") {
                navigationState.pendingRequest = URLRequest(url: url)
            }
        }
    }

    private func loadHome() {
        if let url = URL(string: navigationState.homeURLString) {
            navigationState.pendingRequest = URLRequest(url: url)
        }
    }
}

// MARK: - Enhanced Button Style with Hover Support
struct EnhancedButtonStyle: ButtonStyle {
    let disabled: Bool
    @State private var isHovered: Bool = false
    
    init(disabled: Bool = false) {
        self.disabled = disabled
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered && !disabled ? 1.08 : 1.0))
            .brightness(configuration.isPressed ? -0.1 : (isHovered && !disabled ? 0.1 : 0))
            .opacity(disabled ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Highlighting Button Style (for compatibility)
struct HighlightButtonStyle: ButtonStyle {
    let disabled: Bool
    
    init(disabled: Bool = false) {
        self.disabled = disabled
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 50)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.8 : 0))
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
            .opacity(disabled ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - WebView Representable
private struct WebViewRepresentable: UIViewRepresentable {
    @Binding var webView: WKWebView
    @ObservedObject var navigationState: WebViewNavigationState
    let isDarkMode: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        // Build a configuration with our user script installed at document start
        let config = WKWebViewConfiguration()
        config.userContentController.removeAllUserScripts()
        config.userContentController.addUserScript(Self.forceDarkUserScript)

        // Reuse incoming instance but with our config at init time
        let newWebView = WKWebView(frame: .zero, configuration: config)
        newWebView.navigationDelegate = context.coordinator
        newWebView.allowsBackForwardNavigationGestures = true
        newWebView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light

        // replace binding reference
        DispatchQueue.main.async { self.webView = newWebView }

        if let url = URL(string: navigationState.urlString) {
            newWebView.load(URLRequest(url: url))
        }
        return newWebView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let request = navigationState.pendingRequest {
            uiView.load(request)
            // Defer state mutation to avoid "Publishing changes from within view updates..."
            DispatchQueue.main.async { navigationState.pendingRequest = nil }
        }
        uiView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        // Live‑toggle when the SwiftUI toggle changes
        uiView.evaluateJavaScript(isDarkMode ? "__forceDark_apply()" : "__forceDark_remove()", completionHandler: nil)
    }

    // MARK: - User Script (document-start)
    // Provides window.__forceDark_apply() and window.__forceDark_remove()
    private static let forceDarkUserScript: WKUserScript = {
        let js = """
        (function() {
          // Safe re-entry guards
          if (window.__forceDark_loaded) return;
          window.__forceDark_loaded = true;

          const STYLE_ID = '__forceDarkStyle';
          const OBS_KEY  = '__forceDarkObserver';

          function baseCSS() {
            return `
              :root { color-scheme: dark !important; }
              html, body { background-color:#121212 !important; color:#e0e0e0 !important; }
              /* Avoid inverting media */
              img, video, canvas, svg, picture, iframe { filter:none !important; }
              /* Links */
              a { color:#8ab4f8 !important; }
              /* Common resets to neutralize hard-coded white panes */
              [style*="background:#fff"], [style*="background: #fff"], [style*="background-color:#fff"], [style*="background-color: #fff"] {
                background-color: #1b1b1b !important; color:#e0e0e0 !important;
              }
              /* YouTube-specific containers */
              ytd-app, ytd-watch-flexy, #page-manager, #columns, #primary, #secondary, #content, #container, #chips-wrapper, #contents {
                background-color:#0f0f0f !important; color:#e0e0e0 !important;
              }
            `;
          }

          function injectStyle() {
            let style = document.getElementById(STYLE_ID);
            if (!style) {
              style = document.createElement('style');
              style.id = STYLE_ID;
              style.type = 'text/css';
              style.appendChild(document.createTextNode(baseCSS()));
              (document.head || document.documentElement).appendChild(style);
            }
          }

          function removeStyle() {
            const s = document.getElementById(STYLE_ID);
            if (s) s.remove();
          }

          function ensureObserver() {
            if (window[OBS_KEY]) return;
            const obs = new MutationObserver(function() {
              // Re-assert presence on DOM changes (SPA / virtual DOM)
              injectStyle();
            });
            obs.observe(document.documentElement, { childList: true, subtree: true });
            window[OBS_KEY] = obs;
          }

          function disconnectObserver() {
            const obs = window[OBS_KEY];
            if (obs && obs.disconnect) obs.disconnect();
            window[OBS_KEY] = null;
          }

          // Public helpers for native code
          window.__forceDark_apply = function() {
            // Hint native dark theme to cooperating sites ASAP
            try {
              document.documentElement.style.colorScheme = 'dark';
              let meta = document.querySelector('meta[name="color-scheme"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.setAttribute('name','color-scheme');
                document.head.appendChild(meta);
              }
              meta.setAttribute('content','dark light');
            } catch (e) {}

            injectStyle();
            ensureObserver();

            // YouTube SPA hook
            document.addEventListener('yt-navigate-finish', injectStyle);
          };

          window.__forceDark_remove = function() {
            document.documentElement.style.colorScheme = '';
            removeStyle();
            disconnectObserver();
            document.removeEventListener('yt-navigate-finish', injectStyle);
          };
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }()

    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        init(_ parent: WebViewRepresentable) { self.parent = parent }

        // Prefer sites' native dark themes when they support it
        // Drop the variant that has `preferences:`; use this one instead.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }


        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.navigationState.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.navigationState.isLoading = false
            parent.navigationState.canGoBack = webView.canGoBack
            parent.navigationState.canGoForward = webView.canGoForward
            if let url = webView.url?.absoluteString {
                parent.navigationState.urlString = url
            }
            // Re-apply helpers after each load (covers YouTube route changes too)
            let fn = parent.isDarkMode ? "__forceDark_apply()" : "__forceDark_remove()"
            webView.evaluateJavaScript(fn, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.navigationState.isLoading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.navigationState.isLoading = false
        }
    }
}

// MARK: - Legacy Button Style (kept for compatibility)
struct BrowserButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension String {
    func trimmed() -> String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    var isValidURL: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: utf16.count)) {
            return match.range.length == utf16.count
        } else { return false }
    }
}

