import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: HorizonModel
    @State private var selection: NavigationSection? = .horizon
    enum NavigationSection: String, CaseIterable, Identifiable { case horizon = "True Horizon", epochs = "Epochs", postcards = "Postcards", settings = "Settings"; var id: String { rawValue } }

    var body: some View {
        NavigationSplitView {
            List(NavigationSection.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: icon(item)).tag(item)
            }
            .navigationTitle("True Horizon")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BECAUSE THE SUN IS ALWAYS LATE").papyrus(11, weight: .bold).foregroundStyle(.secondary)
                    Text("to its own Dawn. ☀️").papyrus(17)
                }.padding()
            }
        } detail: {
            switch selection ?? .horizon {
            case .horizon: TrueHorizonView()
            case .epochs: EpochCollectionView()
            case .postcards: PostcardsView()
            case .settings: SettingsView()
            }
        }
    }

    private func icon(_ item: NavigationSection) -> String {
        switch item { case .horizon: "sun.horizon.fill"; case .epochs: "clock.arrow.trianglehead.counterclockwise.rotate.90"; case .postcards: "photo.stack"; case .settings: "gearshape" }
    }
}
