import Foundation
import WebKit

protocol PluginInterface {
    var name: String { get }
    func initialize(context: SWVContext, webView: WKWebView)
    func webViewDidFinishLoad(url: URL)
    func handleScriptMessage(message: WKScriptMessage)
}

extension PluginInterface {
    func initialize(context: SWVContext, webView: WKWebView) {}
    func webViewDidFinishLoad(url: URL) {}
    func handleScriptMessage(message: WKScriptMessage) {}
}
