import SwiftUI

struct EpochCollectionView: View {
    @EnvironmentObject private var model: HorizonModel
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 18) {
                ForEach(Array(Epoch.allCases.enumerated()), id: \.element.id) { index, epoch in
                    let unlocked = index < 2
                    Button { if unlocked { model.selectedEpoch = epoch } } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            ZStack { LinearGradient(colors: colors(epoch), startPoint: .top, endPoint: .bottom); Circle().fill(.yellow.opacity(unlocked ? 1 : .25)).frame(width: 85).shadow(color: .yellow.opacity(.35), radius: 25); if !unlocked { Image(systemName: "lock.fill").font(.title) } }.frame(height: 190).clipShape(RoundedRectangle(cornerRadius: 18))
                            Text(epoch.rawValue).papyrus(20, weight: .bold); Text(epoch.subtitle).papyrus(13).foregroundStyle(.secondary); Text(unlocked ? (model.selectedEpoch == epoch ? "ACTIVE SKY" : "EXPLORE") : "LOCKED").papyrus(11, weight: .bold).foregroundStyle(unlocked ? .yellow : .secondary)
                        }.padding().background(.white.opacity(.05), in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain).disabled(!unlocked)
                }
            }.padding(24)
        }.navigationTitle("Epoch Collection")
    }
    private func colors(_ e: Epoch) -> [Color] { switch e { case .present: [.indigo, .black]; case .cretaceous: [.orange, .brown]; case .jurassic: [.purple, .black]; case .deepTime: [.black, .blue.opacity(.4)] } }
}
