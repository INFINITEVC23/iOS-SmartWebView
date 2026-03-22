import SwiftUI

struct ContentView: View {
    private let initialURL = SWVContext.shared.initialURL

    var body: some View {
        ZStack {
            if let url = initialURL {
                WebView(url: url)
                    .ignoresSafeArea()
            } else {
                Text("Error: Initial URL could not be determined.")
            }
        }
    }
}

#Preview {
    ContentView()
}
