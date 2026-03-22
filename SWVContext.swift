import Foundation
import WebKit

class SWVContext {
    static let shared = SWVContext()
    var pullToRefreshEnabled = true
    var fileUploadsEnabled = true
    var multipleUploadsEnabled = true
    var enabledPlugins = ["Toast", "Dialog", "Location", "Playground", "Rating"]
}

class PluginManager {
    static let shared = PluginManager()
    func initializePlugins(context: SWVContext, webView: WKWebView) {}
    func handleScriptMessage(message: WKScriptMessage) {}
    func webViewDidFinishLoad(url: URL) {}
}

class URLHandler {
    static func handle(url: URL, webView: WKWebView) -> Bool {
        if ["tel", "mailto", "sms"].contains(url.scheme) {
            UIApplication.shared.open(url); return true
        }
        return false
    }
}

class LeakFreeScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// STUBS: These keep your App file from throwing errors until you build these plugins
class ToastPlugin { static func register() {} }
class Playground { static func register() {} }
class DialogPlugin { static func register() {} }
class RatingPlugin { static func register() {} }
