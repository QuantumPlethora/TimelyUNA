import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

@main
struct TimelyUNAApp: App {
    /// True only for this process’s first composition — not persisted across launches.
    @State private var showStartupTransition = StartupColdLaunchGate.claimIfNeeded()

    init() {
        Self.configureBlackChrome()
    }

    var body: some Scene {
        WindowGroup(Brand.productDisplayName) {
            ZStack {
                // Root stays black so LaunchScreen → transition → app never flashes white.
                Color.black
                    .ignoresSafeArea()

                ContentView()

                if showStartupTransition {
                    StartupTransitionView {
                        showStartupTransition = false
                    }
                    .zIndex(1000)
                }
            }
            .background(Color.black.ignoresSafeArea())
            #if os(macOS)
            .frame(minWidth: 900, minHeight: 640)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 860)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About \(Brand.productDisplayName)") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: Brand.productDisplayName,
                            .credits: NSAttributedString(
                                string: "\(Brand.studioCredit)\n\(Brand.technologyCredit)\nEducational visualization only."
                            )
                        ]
                    )
                }
            }
        }
        #endif
    }

    /// Keep system chrome black during cold launch to avoid white interstitial frames.
    private static func configureBlackChrome() {
        #if os(iOS)
        // Window / hosting background before first SwiftUI frame.
        let black = UIColor.black
        UIWindow.appearance().backgroundColor = black
        #endif
        #if os(macOS)
        // No global NSWindow appearance change required; SwiftUI root is black.
        #endif
    }
}
