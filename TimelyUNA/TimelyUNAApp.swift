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
                    // Failsafe: never leave the user stuck on the opening overlay.
                    .task {
                        try? await Task.sleep(nanoseconds: 18_000_000_000)
                        if showStartupTransition {
                            showStartupTransition = false
                        }
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
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
        // Window background before first SwiftUI frame only — do not paint all UIViews black.
        UIWindow.appearance().backgroundColor = .black
        #endif
        #if os(macOS)
        // No global NSWindow appearance change required; SwiftUI root is black.
        #endif
    }
}
