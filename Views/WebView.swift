import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers
import CoreLocation

// MARK: - WebView Store
class WebViewStore: ObservableObject {
    let webView: WKWebView
    init() {
        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
    }
}

// MARK: - Main WebView Struct
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
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
            webView.scrollView.addSubview(refreshControl)
            webView.scrollView.bounces = true
        }
        
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate, WKDownloadDelegate {
        
        var parent: WebView
        var webView: WKWebView 
        private var filePickerCompletionHandler: (([URL]?) -> Void)?

        init(_ parent: WebView, webView: WKWebView) {
            self.parent = parent
            self.webView = webView
            super.init()
            
            let swvContext = SWVContext.shared
            let userContentController = self.webView.configuration.userContentController
            let leakFree = LeakFreeScriptHandler(delegate: self)
            
            if swvContext.enabledPlugins.contains("Toast") { userContentController.add(leakFree, name: "toast") }
            if swvContext.enabledPlugins.contains("Dialog") { userContentController.add(leakFree, name: "dialog") }
            if swvContext.enabledPlugins.contains("Location") { userContentController.add(leakFree, name: "location") }
        }
        
        // ... (Keep all your existing Coordinator methods here exactly as they were) ...
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let refreshControl = webView.scrollView.subviews.first(where: { $0 is UIRefreshControl }) as? UIRefreshControl {
                refreshControl.endRefreshing()
            }
            webView.evaluateJavaScript("if (typeof setPlatform === 'function') { setPlatform('ios'); }", completionHandler: nil)
            PluginManager.shared.webViewDidFinishLoad(url: webView.url ?? parent.url)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, URLHandler.handle(url: url, webView: webView) {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if !navigationResponse.canShowMIMEType { decisionHandler(.download) } else { decisionHandler(.allow) }
        }
        
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { PluginManager.shared.handleScriptMessage(message: message) }
        @objc func handleRefresh() { webView.reload() }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            guard SWVContext.shared.fileUploadsEnabled else { completionHandler(nil); return }
            self.filePickerCompletionHandler = completionHandler
            let alert = UIAlertController(title: "Select Source", message: nil, preferredStyle: .actionSheet)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                alert.addAction(UIAlertAction(title: "Camera", style: .default) { _ in self.showImagePicker(sourceType: .camera) })
            }
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                var config = PHPickerConfiguration(photoLibrary: .shared())
                config.selectionLimit = SWVContext.shared.multipleUploadsEnabled && parameters.allowsMultipleSelection ? 0 : 1
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                self.present(picker)
            })
            alert.addAction(UIAlertAction(title: "Browse Files", style: .default) { _ in
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                picker.delegate = self
                self.present(picker)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in self.filePickerCompletionHandler?(nil) })
            self.present(alert)
        }
        
        private func present(_ viewController: UIViewController) {
            UIApplication.shared.windows.first(where: \.isKeyWindow)?.rootViewController?.present(viewController, animated: true)
        }

        private func showImagePicker(sourceType: UIImagePickerController.SourceType) {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = self
            picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            self.present(picker)
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            var urls: [URL] = []; let group = DispatchGroup()
            for result in results {
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                    if let url = url {
                        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                        try? FileManager.default.copyItem(at: url, to: temp)
                        urls.append(temp)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.filePickerCompletionHandler?(urls) }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            let url = (info[.mediaURL] as? URL) ?? (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.5).map { data in
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? data.write(to: temp)
                return temp
            }
            self.filePickerCompletionHandler?(url != nil ? [url!] : nil)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true); self.filePickerCompletionHandler?(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { self.filePickerCompletionHandler?(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { self.filePickerCompletionHandler?(nil) }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            completionHandler(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(suggestedFilename))
        }
    }
}
