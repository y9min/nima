import SwiftUI
import WebKit

struct SVGView: UIViewRepresentable {
    let svgName: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        
        if let path = Bundle.main.path(forResource: svgName, ofType: "svg"),
           let svgString = try? String(contentsOfFile: path) {
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    body {
                        margin: 0;
                        padding: 0;
                        background: transparent;
                        overflow: hidden;
                    }
                    svg {
                        width: 100%;
                        height: 100%;
                    }
                </style>
            </head>
            <body>
                \(svgString)
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}
