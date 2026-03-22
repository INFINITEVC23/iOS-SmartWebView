import Foundation
import WebKit

final class PluginManager {
    static let shared = PluginManager()
    private var plugins: [String: PluginInterface] = [:]
    private weak var webView: WKWebView?

    private init() {}
    
    func registerPlugin(_ plugin: PluginInterface) {
        guard plugins[plugin.name] == nil else { return }
        plugins[plugin.name] = plugin
    }
    
    func getPlugin(named name: String) -> PluginInterface? {
        return plugins[name]
    }
    
    func evaluateJavaScript(_ script: String) {
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
    
    func initializePlugins(context: SWVContext, webView: WKWebView) {
        self.webView = webView
        for plugin in plugins.values {
            plugin.initialize(context: context, webView: webView)
        }
    }
    
    func webViewDidFinishLoad(url: URL) { for plugin in plugins.values { plugin.webViewDidFinishLoad(url: url) } }
    
    func handleScriptMessage(message: WKScriptMessage) {
        let handlerName = message.name.lowercased()
        for plugin in plugins.values {
            if plugin.name.lowercased() == handlerName {
                plugin.handleScriptMessage(message: message)
                return
            }
        }
    }
}
