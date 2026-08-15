import SwiftUI

struct PostcardsView: View {
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [.orange, .yellow, .green.opacity(.55)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading) { Text("POSTCARD FROM").papyrus(11, weight: .bold).tracking(2); Text("THE CRETACEOUS").papyrus(34, weight: .bold); Spacer(); Text("“The sky is warmer here.\nSaturn hangs low in the east.”").papyrus(20) }.padding(28)
            }.frame(maxWidth: 620, minHeight: 390).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(radius: 35).rotationEffect(.degrees(-2))
            Text("Complete Chronos jumps to collect atmospheric records from vanished skies.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }.padding().navigationTitle("Deep-Time Postcards")
    }
}
