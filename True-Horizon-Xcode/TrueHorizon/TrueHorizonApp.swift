import SwiftUI

@main
struct TrueHorizonApp: App {
    @StateObject private var model = HorizonModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.font, .custom("Papyrus", size: 17))
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        #endif
    }
}
