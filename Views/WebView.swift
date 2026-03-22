import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

class WebViewStore: ObservableObject {
    @Published var webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // Optimization: Use a non-persistent data store if needed, or stick to default
        self.webView = WKWebView(frame: .zero, configuration: configuration)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @StateObject private var webViewStore = WebViewStore()

    func makeCoordinator() -> Coordinator {
        Coordinator(self, webView: webViewStore.webView)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewStore.webView
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        PluginManager.shared.initializePlugins(context: SWVContext.shared, webView: webView)
        
        if SWVContext.shared.pullToRefreshEnabled {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)
            webView.scrollView.refreshControl = refreshControl
            webView.scrollView.bounces = true
        }
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
        
        var parent: WebView
        var webView: WKWebView 
        private var filePickerCompletionHandler: (([URL]?) -> Void)?

        init(_ parent: WebView, webView: WKWebView) {
            self.parent = parent
            self.webView = webView
            super.init()
            
            setupScriptHandlers()
        }
        
        private func setupScriptHandlers() {
            let swvContext = SWVContext.shared
            let userContentController = self.webView.configuration.userContentController
            
            userContentController.removeAllScriptMessageHandlers()
            
            // Use a weak wrapper to prevent memory leaks
            let leakFreeHandler = LeakFreeLeakFreeScriptHandler(delegate: self)
            
            let plugins = ["toast", "dialog", "location"]
            for plugin in plugins {
                if swvContext.enabledPlugins.contains(plugin.capitalized) {
                    userContentController.add(leakFreeHandler, name: plugin)
                }
            }
        }

        // MARK: - WKUIDelegate (Popups & Panels)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            guard SWVContext.shared.fileUploadsEnabled else {
                completionHandler(nil)
                return
            }
            self.filePickerCompletionHandler = completionHandler
            
            let alert = UIAlertController(title: "Upload Files", message: nil, preferredStyle: .actionSheet)
            
            // 1. Camera Option
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                alert.addAction(UIAlertAction(title: "Take Photo or Video", style: .default) { _ in 
                    self.showImagePicker(sourceType: .camera) 
                })
            }
            
            // 2. Photo Library (Modern PHPicker)
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                var config = PHPickerConfiguration(photoLibrary: .shared())
                config.selectionLimit = (SWVContext.shared.multipleUploadsEnabled && parameters.allowsMultipleSelection) ? 0 : 1
                config.filter = .any(of: [.images, .videos])
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                self.present(picker)
            })
            
            // 3. Document Browser
            alert.addAction(UIAlertAction(title: "Browse Files", style: .default) { _ in
                let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                documentPicker.delegate = self
                documentPicker.allowsMultipleSelection = SWVContext.shared.multipleUploadsEnabled && parameters.allowsMultipleSelection
                self.present(documentPicker)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            
            // iPad Support for ActionSheets
            if let popover = alert.popoverPresentationController {
                popover.sourceView = self.webView
                popover.sourceRect = CGRect(x: self.webView.bounds.midX, y: self.webView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            self.present(alert)
        }

        // MARK: - PHPickerViewControllerDelegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                self.filePickerCompletionHandler?(nil)
                return
            }

            var processedURLs: [URL] = []
            let group = DispatchGroup()

            for result in results {
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { (url, error) in
                    if let originalUrl = url {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(originalUrl.pathExtension)
                        try? FileManager.default.copyItem(at: originalUrl, to: tempURL)
                        DispatchQueue.main.async { processedURLs.append(tempURL) }
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.filePickerCompletionHandler?(processedURLs)
            }
        }

        // MARK: - UIImagePickerControllerDelegate (Camera Support)
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            
            if let url = info[.imageURL] as? URL ?? info[.mediaURL] as? URL {
                self.filePickerCompletionHandler?([url])
            } else if let image = info[.originalImage] as? UIImage {
                // Camera images are often in-memory; save to temp disk
                if let data = image.jpegData(compressionQuality: 0.8) {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                    try? data.write(to: tempURL)
                    self.filePickerCompletionHandler?([tempURL])
                    return
                }
                self.filePickerCompletionHandler?(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            self.filePickerCompletionHandler?(nil)
        }

        // MARK: - UIDocumentPickerDelegate
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            self.filePickerCompletionHandler?(urls)
        }

        func documentPickerDidCancel(_ controller: UIDocumentPickerViewController) {
            self.filePickerCompletionHandler?(nil)
        }

        // MARK: - Helpers & Script Handling
        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webView.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                sender.endRefreshing()
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            PluginManager.shared.handleScriptMessage(message: message)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.evaluateJavaScript("if (typeof setPlatform === 'function') { setPlatform('ios'); }")
            if let url = webView.url { PluginManager.shared.webViewDidFinishLoad(url: url) }
        }

        private func present(_ viewController: UIViewController) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                // Ensure we present on the top-most controller
                var topVC = rootVC
                while let presentedVC = topVC.presentedViewController { topVC = presentedVC }
                topVC.present(viewController, animated: true)
            }
        }

        private func showImagePicker(sourceType: UIImagePickerController.SourceType) {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = self
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            self.present(picker)
        }
    }
}

// MARK: - Weak Script Handler Wrapper (Prevents Retain Cycles)
class LeakFreeLeakFreeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: - Downloads Support
extension WebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsURL.appendingPathComponent(suggestedFilename)
        completionHandler(fileURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        print("Download successfully finished.")
    }
}
