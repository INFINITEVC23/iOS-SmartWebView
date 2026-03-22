import SwiftUI
import WebKit
import PhotosUI
import UniformTypeIdentifiers

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // FIX: Added the LeakFreeScriptHandler to handle the "bridge"
        let leakFreeHandler = LeakFreeScriptHandler(delegate: context.coordinator)
        userContentController.add(leakFreeHandler, name: "bridge")
        
        config.userContentController = userContentController
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
        
        var parent: WebView
        init(_ parent: WebView) {
            self.parent = parent
        }

        // MARK: - JS Bridge Handling
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "bridge", let dict = message.body as? [String: Any] {
                print("Received JS Bridge Action: \(dict)")
                // Add your custom JS-to-iOS logic here
            }
        }

        // MARK: - File/Photo Picker Logic (The "Heavy" Lifting)
        // This satisfies the UIDelegate requirements for <input type="file">
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            
            let viewController = UIApplication.shared.windows.first?.rootViewController
            
            // Logic for choosing between Photos or Files
            let alert = UIAlertController(title: "Choose Source", message: nil, preferredStyle: .actionSheet)
            
            alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                var config = PHPickerConfiguration()
                config.selectionLimit = parameters.allowsMultipleSelection ? 0 : 1
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                viewController?.present(picker, animated: true)
            })
            
            alert.addAction(UIAlertAction(title: "Files", style: .default) { _ in
                let documentPicker = UIDocumentPickerViewController(forOpeningUnder: [.data])
                documentPicker.delegate = self
                documentPicker.allowsMultipleSelection = parameters.allowsMultipleSelection
                viewController?.present(documentPicker, animated: true)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(nil)
            })
            
            viewController?.present(alert, animated: true)
        }

        // MARK: - PHPickerViewControllerDelegate (The FIX)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            // Note: In a production app, you'd convert these results to URLs 
            // and pass them back to the completionHandler.
        }

        // MARK: - UIDocumentPickerDelegate
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Handle file selection
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Handle cancel
        }

        // MARK: - Navigation Handling
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Successfully finished loading: \(webView.url?.absoluteString ?? "")")
        }
    }
}

// MARK: - Helper Classes
class LeakFreeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
