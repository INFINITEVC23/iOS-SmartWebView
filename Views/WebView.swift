import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

// --- Memory Management Helper ---
class LeakFreeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// --- WEBVIEW IMPLEMENTATION ---
struct WebView: UIViewRepresentable {
    let url: URL
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // --- BUG FIX: VIEWPORT & POPUP BLOCKER ---
        let viewportScript = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
        document.getElementsByTagName('head')[0].appendChild(meta);
        
        // Overriding window.open to stop redirecting to Safari
        window.open = function(url) {
            window.location.href = url;
            return null;
        };

        var style = document.createElement('style');
        style.innerHTML = `
            :root {
                --sat: env(safe-area-inset-top);
                --sab: env(safe-area-inset-bottom);
            }
            body { 
                padding-bottom: var(--sab) !important;
                -webkit-text-size-adjust: 100%;
                background-color: black !important;
            }
        `;
        document.head.appendChild(style);
        """
        // Injected at START to catch popups before they trigger
        let userScript = WKUserScript(source: viewportScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        let leakFreeHandler = LeakFreeScriptHandler(delegate: context.coordinator)
        config.userContentController.add(leakFreeHandler, name: "nativeApp")
        
        // Settings for Movie Streaming
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic 
        webView.scrollView.bounces = true 
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        PluginManager.shared.initializePlugins(context: SWVContext.shared, webView: webView)
        
        if SWVContext.shared.pullToRefreshEnabled {
            let refresh = UIRefreshControl()
            refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
            webView.scrollView.refreshControl = refresh
        }
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, WKDownloadDelegate {
        
        var parent: WebView
        private var filePickerCompletionHandler: (([URL]?) -> Void)?
        weak var webViewInstance: WKWebView? 

        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(triggerReload), name: NSNotification.Name("ReloadWebView"), object: nil)
        }
        
        @objc func triggerReload() {
            webViewInstance?.reload()
        }

        // --- CRITICAL FIX: STOP SAFARI REDIRECTS ---
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // If a movie site tries to open a new tab/window, force it to stay in the app
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        @MainActor
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @Sendable (URL?) -> Void) {
            let tempDir = FileManager.default.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent(suggestedFilename)
            completionHandler(destinationURL)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webViewInstance = webView
            webView.scrollView.refreshControl?.endRefreshing()
            PluginManager.shared.webViewDidFinishLoad(url: webView.url ?? parent.url)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            PluginManager.shared.handleScriptMessage(message: message)
        }
        
        @objc func handleRefresh(sender: UIRefreshControl) {
            webViewInstance?.reload()
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            self.filePickerCompletionHandler = completionHandler
            let alert = UIAlertController(title: "Upload File", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                var config = PHPickerConfiguration()
                config.selectionLimit = parameters.allowsMultipleSelection ? 0 : 1
                config.filter = .any(of: [.images, .videos])
                DispatchQueue.main.async {
                    let picker = PHPickerViewController(configuration: config)
                    picker.delegate = self
                    self.getTopVC()?.present(picker, animated: true)
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in 
                completionHandler(nil) 
            })
            getTopVC()?.present(alert, animated: true)
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider else {
                self.filePickerCompletionHandler?(nil)
                return
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
                    if let url = url {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: tempURL)
                        try? FileManager.default.copyItem(at: url, to: tempURL)
                        self.filePickerCompletionHandler?([tempURL])
                    } else {
                        self.filePickerCompletionHandler?(nil)
                    }
                }
            } else {
                self.filePickerCompletionHandler?(nil)
            }
        }

        private func getTopVC() -> UIViewController? {
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            var topController = keyWindow?.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            return topController
        }
    }
}

// --- UPDATED: BOREDFLIX CONTAINER ---
struct SurveyContainerView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    var body: some View {
        WebView(url: url)
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        
                        Spacer()
                        
                        Text("BOREDFLIX")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.red)
                        
                        Spacer()
                        
                        Button(action: {
                            NotificationCenter.default.post(name: NSNotification.Name("ReloadWebView"), object: nil)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.blue.opacity(0.12)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black)
                    
                    Divider().background(Color.red.opacity(0.3))
                }
            }
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
