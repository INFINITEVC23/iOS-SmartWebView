import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

class WebViewStore: ObservableObject {
    @Published var webView: WKWebView

    init() {
        // Initialize with a default configuration to avoid re-init cycles
        let configuration = WKWebViewConfiguration()
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
        
        // Essential: Set delegates before loading
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        
        // Initialize custom logic
        PluginManager.shared.initializePlugins(context: SWVContext.shared, webView: webView)
        
        // Pull to Refresh logic
        if SWVContext.shared.pullToRefreshEnabled {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
            webView.scrollView.refreshControl = refreshControl // Modern way to set refreshControl
            webView.scrollView.bounces = true
        }
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
        var parent: WebView
        var webView: WKWebView 
        private var filePickerCompletionHandler: (([URL]?) -> Void)?

        init(_ parent: WebView, webView: WKWebView) {
            self.parent = parent
            self.webView = webView
            super.init()
            
            let swvContext = SWVContext.shared
            let userContentController = self.webView.configuration.userContentController
            
            // Register JS handlers
            if swvContext.enabledPlugins.contains("Toast") { userContentController.add(self, name: "toast") }
            if swvContext.enabledPlugins.contains("Dialog") { userContentController.add(self, name: "dialog") }
            if swvContext.enabledPlugins.contains("Location") { userContentController.add(self, name: "location") }
        }
        
        // MARK: - WKUIDelegate (Popups & File Panels)
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle target="_blank" links
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.uiDelegate = self
            
            let vc = UIViewController()
            vc.view = popupWebView
            
            let nav = UINavigationController(rootViewController: vc)
            vc.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissPopup))
            
            if let root = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController {
                root.present(nav, animated: true)
            }
            return popupWebView
        }

        @objc func dismissPopup() {
            if let root = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController {
                root.dismiss(animated: true)
            }
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            guard SWVContext.shared.fileUploadsEnabled else {
                completionHandler(nil)
                return
            }
            self.filePickerCompletionHandler = completionHandler
            
            let alert = UIAlertController(title: "Upload Files", message: nil, preferredStyle: .actionSheet)
            
            // 1. Camera
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                alert.addAction(UIAlertAction(title: "Camera", style: .default) { _ in self.showImagePicker(sourceType: .camera) })
            }
            
            // 2. Photo Library (PHPicker)
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
                // Request a file representation compatible with the system
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { (url, error) in
                    if let originalUrl = url {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(originalUrl.pathExtension)
                        try? FileManager.default.copyItem(at: originalUrl, to: tempURL)
                        processedURLs.append(tempURL)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.filePickerCompletionHandler?(processedURLs.isEmpty ? nil : processedURLs)
            }
        }

        // MARK: - Helper Methods
        private func present(_ viewController: UIViewController) {
            if let rootVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first(where: \.isKeyWindow)?.rootViewController {
                rootVC.present(viewController, animated: true)
            }
        }

        private func showImagePicker(sourceType: UIImagePickerController.SourceType) {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = self
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            self.present(picker)
        }

        @objc func handleRefresh() {
            webView.reload()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            PluginManager.shared.handleScriptMessage(message: message)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.evaluateJavaScript("if (typeof setPlatform === 'function') { setPlatform('ios'); }")
            if let url = webView.url { PluginManager.shared.webViewDidFinishLoad(url: url) }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }
        
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }
    }
}

// MARK: - Downloads
extension WebView.Coordinator: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsURL.appendingPathComponent(suggestedFilename)
        completionHandler(fileURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        print("Download finished successfully.")
    }
}
