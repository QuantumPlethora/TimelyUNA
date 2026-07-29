import SwiftUI

@main
struct TimelyUNAApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        #endif
    }
}
