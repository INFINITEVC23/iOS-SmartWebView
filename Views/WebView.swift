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
        
        webView.load(URLRequest(url: url))
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
            setupScriptHandlers()
        }
        
        private func setupScriptHandlers() {
            let userContentController = self.webView.configuration.userContentController
            userContentController.removeAllScriptMessageHandlers()
            
            // Fixed naming to match the class below
            let leakFreeHandler = LeakFreeScriptHandler(delegate: self)
            
            let plugins = ["toast", "dialog", "location"]
            for plugin in plugins {
                if SWVContext.shared.enabledPlugins.contains(plugin.capitalized) {
                    userContentController.add(leakFreeHandler, name: plugin)
                }
            }
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            webView.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sender.endRefreshing() }
        }

        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            PluginManager.shared.handleScriptMessage(message: message)
        }

        // MARK: - WKUIDelegate
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            self.filePickerCompletionHandler = completionHandler
            let alert = UIAlertController(title: "Upload", message: nil, preferredStyle: .actionSheet)
            
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                var config = PHPickerConfiguration()
                config.selectionLimit = parameters.allowsMultipleSelection ? 0 : 1
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                self.present(picker)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            self.present(alert)
        }

        // MARK: - PHPickerViewControllerDelegate
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let group = DispatchGroup()
            var urls: [URL] = []
            
            for result in results {
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                    if let url = url {
                        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: temp)
                        urls.append(temp)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { self.filePickerCompletionHandler?(urls) }
        }

        // MARK: - Navigation
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("setPlatform('ios')")
        }

        private func present(_ vc: UIViewController) {
            UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true)
        }
    }
}

// Fixed class name to match the caller
class LeakFreeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
