import Foundation
import Network

final class SWVContext {
    // The shared singleton instance
    static let shared = SWVContext()

    // --- CONFIGURATION PROPERTIES ---
    let debugMode: Bool
    let appURL: String
    let offlineURL: String
    let searchURL: String
    let shareURLSuffix: String
    let externalURLExceptionList: [String]
    let pullToRefreshEnabled: Bool
    let fileUploadsEnabled: Bool
    let multipleUploadsEnabled: Bool
    let openExternalURLs: Bool
    let enabledPlugins: [String]
    let playgroundEnabled: Bool
    let permissionsOnLaunch: [String]
    
    // --- DERIVED & STATE PROPERTIES ---
    let host: String
    var initialURL: URL!

    private init() {
        let config = ConfigLoader()
        
        // --- Load properties from config file ---
        self.debugMode = config.getBool(key: "debug.mode", defaultValue: false)
        self.appURL = config.getString(key: "app.url", defaultValue: "https://example.com")
        self.offlineURL = config.getString(key: "offline.url", defaultValue: "offline.html")
        self.searchURL = config.getString(key: "search.url", defaultValue: "https://www.google.com/search?q=")
        self.shareURLSuffix = config.getString(key: "share.url.suffix", defaultValue: "/?share=")
        self.externalURLExceptionList = config.getStringArray(key: "external.url.exception.list", defaultValue: [])
        self.pullToRefreshEnabled = config.getBool(key: "feature.pull.refresh", defaultValue: true)
        self.fileUploadsEnabled = config.getBool(key: "feature.uploads", defaultValue: true)
        self.multipleUploadsEnabled = config.getBool(key: "feature.multiple.uploads", defaultValue: true)
        self.openExternalURLs = config.getBool(key: "feature.open.external.urls", defaultValue: true)
        self.enabledPlugins = config.getStringArray(key: "plugins.enabled", defaultValue: [])
        self.playgroundEnabled = config.getBool(key: "plugins.playground.enabled", defaultValue: true)
        self.permissionsOnLaunch = config.getStringArray(key: "permissions.on.launch", defaultValue: [])
        
        // Extract host for domain checking
        self.host = URL(string: self.appURL)?.host ?? ""
        
        // --- Network Check & URL Selection ---
        if !isNetworkAvailable() {
            // Attempt to load from 'Resources/web/' as per your template structure
            if let offlinePath = Bundle.main.url(forResource: self.offlineURL, withExtension: nil, subdirectory: "web") {
                self.initialURL = offlinePath
                print("Offline: Loading local file from \(offlinePath.path)")
            } else {
                // Fallback to appURL if local file is missing
                self.initialURL = URL(string: self.appURL)
            }
        } else {
            // Online: Load the remote URL
            self.initialURL = URL(string: self.appURL)
        }
        
        // Final safety check to prevent crashing if the URL string was invalid
        if self.initialURL == nil {
            self.initialURL = URL(string: "https://google.com")!
        }

        print("SWVContext Initialized. App URL: \(self.appURL). Debug Mode: \(self.debugMode)")
    }
    
    // --- Functional Network Connectivity Check ---
    private func isNetworkAvailable() -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var isConnected = false
        
        monitor.pathUpdateHandler = { path in
            isConnected = (path.status == .satisfied)
            semaphore.signal()
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
        
        // Wait 0.5 seconds for a response, then move on
        _ = semaphore.wait(timeout: .now() + 0.5)
        monitor.cancel()
        
        return isConnected
    }
}
