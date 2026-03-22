import Foundation
import WebKit
import UIKit

class ToastPlugin: PluginInterface {
    var name: String = "Toast"
    private weak var webView: WKWebView?

    static func register() {
        PluginManager.shared.registerPlugin(ToastPlugin())
    }
    
    func initialize(context: SWVContext, webView: WKWebView) {
        self.webView = webView
    }
    
    func handleScriptMessage(message: WKScriptMessage) {
        if message.name == "toast", let body = message.body as? String {
            showToast(message: body)
        }
    }
    
    func webViewDidFinishLoad(url: URL) {
        let script = """
            if (!window.Toast) {
                window.Toast = {
                    show: function(message) {
                        if (window.webkit && window.webkit.messageHandlers.toast) {
                            window.webkit.messageHandlers.toast.postMessage(message);
                        }
                    }
                };
            }
        """
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(script) { _, _ in
                if SWVContext.shared.debugMode {
                    let testScript = "setTimeout(() => window.Toast.show('Hello from iOS! (Debug)'), 2000);"
                    self.webView?.evaluateJavaScript(testScript, completionHandler: nil)
                }
            }
        }
    }

    private func showToast(message: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { return }
        
        let toastContainer = UIView()
        let toastLabel = UILabel()
        
        toastLabel.text = message
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.numberOfLines = 0
        
        toastContainer.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toastContainer.layer.cornerRadius = 18
        toastContainer.clipsToBounds = true
        toastContainer.alpha = 0.0
        
        toastContainer.addSubview(toastLabel)
        window.addSubview(toastContainer)
        
        toastContainer.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            toastLabel.topAnchor.constraint(equalTo: toastContainer.topAnchor, constant: 10),
            toastLabel.bottomAnchor.constraint(equalTo: toastContainer.bottomAnchor, constant: -10),
            toastLabel.leadingAnchor.constraint(equalTo: toastContainer.leadingAnchor, constant: 20),
            toastLabel.trailingAnchor.constraint(equalTo: toastContainer.trailingAnchor, constant: -20),
            toastContainer.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toastContainer.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            toastContainer.widthAnchor.constraint(lessThanOrEqualTo: window.widthAnchor, constant: -40),
        ])

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            toastContainer.alpha = 1.0
        }) { _ in
            UIView.animate(withDuration: 0.5, delay: 2.5, animations: { toastContainer.alpha = 0.0 }) { _ in
                toastContainer.removeFromSuperview()
            }
        }
    }
}
