import Foundation
import UIKit
import WebKit

class URLHandler {
    static func handle(url: URL, webView: WKWebView) -> Bool {
        let urlString = url.absoluteString
        let context = SWVContext.shared

        if url.scheme == "refresh" {
            if let appUrl = URL(string: context.appURL) {
                let request = URLRequest(url: appUrl)
                webView.load(request)
            }
            return true
        }

        if urlString.starts(with: "share:") {
            let textToShare = urlString.replacingOccurrences(of: "share:", with: "")
            let activityVC = UIActivityViewController(activityItems: [textToShare], applicationActivities: nil)
            if let rootVC = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
            return true
        }
        
        if urlString.starts(with: "print:") {
            let printInfo = UIPrintInfo.printInfo()
            printInfo.outputType = .general
            printInfo.jobName = "SmartWebView Print"
            let printController = UIPrintInteractionController.shared
            printController.printInfo = printInfo
            printController.printFormatter = webView.viewPrintFormatter()
            printController.present(animated: true, completionHandler: nil)
            return true
        }
        
        if ["tel", "sms", "mailto"].contains(url.scheme), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url); return true
        }

        if context.openExternalURLs, let host = url.host, host != context.host, !context.externalURLExceptionList.contains(host) {
            if UIApplication.shared.canOpenURL(url) { UIApplication.shared.open(url); return true }
        }
        
        return false
    }
}
