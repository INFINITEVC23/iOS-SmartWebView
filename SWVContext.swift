// Update SWVContext.swift to safely unwrap and verify initial URLs before usage.

import Foundation

class SWVContext {
    var initialURLs: [URL]?

    init(urls: [String]) {
        // Convert Strings to URLs and safely unwrap
        self.initialURLs = urls.compactMap { URL(string: $0) }
        // Validate the URLs
        self.initialURLs = self.initialURLs?.filter { $0.scheme != nil && $0.host != nil }
    }

    func useURLs() {
        guard let urls = initialURLs else {
            print("No valid URLs available.")
            return
        }
        // Proceed to use the urls safely
        for url in urls {
            print("Using URL: \(url)")
        }
    }
}