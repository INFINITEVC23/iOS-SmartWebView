import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

// --- NEW: MODERN SURVEY CONTAINER ---
// This wraps your WebView to provide the clean title bar you asked for
struct SurveyView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss // For the close button
    
    var body: some View {
        VStack(spacing: 0) {
            // --- MODERN TITLE BAR ---
            ZStack {
                Color.black // Matches BloxTime theme
                
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    Text("Survey")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        // Triggers the reload notification in your Coordinator
                        NotificationCenter.default.post(name: NSNotification.Name("ReloadWebView"), object: nil)
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }
            .frame(height: 60)
            
            // --- THE WEBVIEW ---
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

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
        
        // --- FIX: VIEWPORT INJECTION ---
        // Forces the site to respect the mobile screen width and fixes scaling
        let viewportScript = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
        document.getElementsByTagName('head')[0].appendChild(meta);
        """
        let userScript = WKUserScript(source: viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)
        
        // 1. Enable the JavaScript Bridge
        let leakFreeHandler = LeakFreeScriptHandler(delegate: context.coordinator)
        config.userContentController.add(leakFreeHandler, name: "nativeApp")
        
        // --- FIX: Media Playback ---
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // 2. Setup Delegates
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // --- FIX: LAYOUT & SCALING ---
        // .always tells the webview to handle the safe area naturally 
        // while the script forces the 1:1 scale
        webView.scrollView.contentInsetAdjustmentBehavior = .always 
        webView.isOpaque = false
        webView.backgroundColor = .black
        
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
        weak var webViewInstance: WKWebView? 

        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            // Link for the modern Title Bar Refresh button
            NotificationCenter.default.addObserver(self, selector: #selector(triggerReload), name: NSNotification.Name("ReloadWebView"), object: nil)
        }
        
        @objc func triggerReload() {
            webViewInstance?.reload()
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
