import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: HorizonModel
    var body: some View {
        Form {
            Section("Astronomical engine") { LabeledContent("Source", value: "Offline NOAA/Meeus equations"); LabeledContent("Location", value: model.locationName); Button("Refresh location") { model.requestLocation() } }
            Section("About") { LabeledContent("App", value: "True Horizon 1.0"); Text("True Horizon reveals the live gap between the Sun you see and the Sun as it exists now."); Text("Educational visualization; not for navigation or safety-critical astronomy.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).navigationTitle("Settings")
    }
}
