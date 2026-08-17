import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// Process-lifetime opening ownership. Cannot skip mid-crystal or run twice.
private enum OpeningSessionPhase: Equatable {
    case playing
    case crystallizing
    case revealed
}

@main
struct TimelyUNAApp: App {
    /// True only for this process’s first composition — not persisted across launches.
    @State private var openingPhase: OpeningSessionPhase = StartupColdLaunchGate.claimIfNeeded()
        ? .playing
        : .revealed

    init() {
        Self.configureBlackChrome()
    }

    var body: some Scene {
        WindowGroup(Brand.productDisplayName) {
            ZStack {
                // Root stays black so LaunchScreen → transition → app never flashes white.
                // ContentView is mounted underneath for the entire opening so the
                // crystalline breakup reveals the live interface, not a black plate.
                Color.black
                    .ignoresSafeArea()

                ContentView()

                if openingPhase != .revealed {
                    StartupTransitionView(
                        onCrystalStart: {
                            if openingPhase == .playing {
                                openingPhase = .crystallizing
                            }
                        },
                        onFinished: {
                            openingPhase = .revealed
                        }
                    )
                    .zIndex(1000)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            // Stable root-owned failsafe. It survives redraws of the opening overlay and
            // releases either an interrupted title phase or an interrupted breakup.
            .task {
                guard openingPhase != .revealed else { return }
                do {
                    try await Task.sleep(nanoseconds: 22_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if openingPhase != .revealed {
                    openingPhase = .revealed
                }
            }
            .environment(\.horizonInterfaceRevealed, openingPhase == .revealed)
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
