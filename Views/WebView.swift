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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // 1. Enable the JavaScript Bridge
        let leakFreeHandler = LeakFreeScriptHandler(delegate: context.coordinator)
        config.userContentController.add(leakFreeHandler, name: "nativeApp")
        
        // --- FIX: Media Playback (Prevents full-screen jumps for surveys) ---
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // 2. Setup Delegates
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // --- FIX: FULL SCREEN LAYOUT ---
        // This ensures the survey fills the screen behind the notch and home bar
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear // Prevents white flashes during loading
        
        // 3. Initialize Plugins
        PluginManager.shared.initializePlugins(context: SWVContext.shared, webView: webView)
        
        // 4. Modern Pull-to-Refresh
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

        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            
            // Allow external refresh calls (useful for your custom title bar)
            NotificationCenter.default.addObserver(self, selector: #selector(triggerReload), name: NSNotification.Name("ReloadWebView"), object: nil)
        }
        
        @objc func triggerReload() {
            // Find the webview and reload it via a notification
            // This is how you'll link your custom "Refresh" button
        }
        
        // MARK: - WKDownloadDelegate
        @MainActor
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @Sendable (URL?) -> Void) {
            let tempDir = FileManager.default.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent(suggestedFilename)
            completionHandler(destinationURL)
        }
        
        // MARK: - Navigation & Script Handling
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            PluginManager.shared.webViewDidFinishLoad(url: webView.url ?? parent.url)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            PluginManager.shared.handleScriptMessage(message: message)
        }
        
        @objc func handleRefresh(sender: UIRefreshControl) {
            sender.superview?.subviews.compactMap { $0 as? WKWebView }.first?.reload()
        }

        // MARK: - File/Photo Picker (Fixed for iOS 16+)
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
            
            if let popoverController = alert.popoverPresentationController {
                popoverController.sourceView = webView
                popoverController.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 0, height: 0)
            }
            
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
