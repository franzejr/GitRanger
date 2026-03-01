import SwiftUI
import WebKit

struct MermaidWebView: NSViewRepresentable {
    let mermaidCode: String
    var zoom: CGFloat = 1.0

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        loadMermaid(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.magnification != zoom {
            webView.magnification = zoom
        }
        if context.coordinator.lastCode != mermaidCode {
            context.coordinator.lastCode = mermaidCode
            loadMermaid(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastCode: String = ""
    }

    private func loadMermaid(in webView: WKWebView) {
        let html = buildHTML()
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML() -> String {
        let isDark = NSApp.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        let theme = isDark ? "dark" : "default"
        let textColor = isDark ? "#e5e5e5" : "#1a1a1a"
        let bgColor = isDark ? "#1e1e1e" : "#ffffff"
        let escaped = mermaidCode
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            body {
                margin: 0;
                padding: 16px;
                background: \(bgColor);
                color: \(textColor);
                display: flex;
                justify-content: center;
            }
            .mermaid { max-width: 100%; }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        </head>
        <body>
        <div class="mermaid">
        \(escaped)
        </div>
        <script>
            mermaid.initialize({
                startOnLoad: true,
                theme: '\(theme)',
                securityLevel: 'strict'
            });
        </script>
        </body>
        </html>
        """
    }
}
