import SwiftUI

struct ContentView: View {
    @StateObject private var simulation = SimulationState()
    @State private var selectedTab: AppTab = .labyrinth

    enum AppTab: Hashable {
        case labyrinth
        case sextant
        case chronos
        case about
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PhotonLabyrinthView()
            }
            .tabItem {
                Label("Labyrinth", systemImage: "puzzlepiece.extension.fill")
            }
            .tag(AppTab.labyrinth)

            NavigationStack {
                SunSextantView()
            }
            .tabItem {
                Label("Sextant", systemImage: "sun.max.fill")
            }
            .tag(AppTab.sextant)

            NavigationStack {
                ChronosModeView()
            }
            .tabItem {
                Label("Chronos", systemImage: "atom")
            }
            .tag(AppTab.chronos)

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("About", systemImage: "scroll.fill")
            }
            .tag(AppTab.about)
        }
        .environmentObject(simulation)
        .tint(TimelyUNATheme.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
