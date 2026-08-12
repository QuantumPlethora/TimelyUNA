import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct TimelyUNAApp: App {
    var body: some Scene {
        WindowGroup("True Horizon") {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About True Horizon") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "True Horizon",
                            .credits: NSAttributedString(
                                string: "Powered by the TimelyUNA light-time engine.\nEducational visualization only."
                            )
                        ]
                    )
                }
            }
        }
        #endif
    }
}
