import SwiftUI

struct TrueHorizonView: View {
    @EnvironmentObject private var model: HorizonModel
    @State private var launching = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.05, blue: 0.06), Color(red: 0.12, green: 0.11, blue: 0.08)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if let snapshot = model.snapshot { sky(snapshot); metrics(snapshot); ritual(snapshot) }
                    else { ProgressView("Calculating the true Sun…").frame(height: 420) }
                }.padding(24).frame(maxWidth: 1050)
            }
        }
        .navigationTitle("True Horizon")
        .toolbar { Text("\(model.streak) day streak").papyrus(13, weight: .bold).foregroundStyle(.yellow) }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("TRUE HORIZON · DAILY RITUAL").papyrus(13, weight: .bold).tracking(2).foregroundStyle(.secondary)
            Text("See the Sun where it truly is.").papyrus(42, weight: .bold).multilineTextAlignment(.center)
            Text(model.locationName).papyrus(13).foregroundStyle(.secondary)
        }
    }

    private func sky(_ s: SolarSnapshot) -> some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<70, id: \.self) { i in Circle().fill(.white.opacity(Double((i % 4) + 1) / 8)).frame(width: 2, height: 2).position(x: CGFloat((i * 79) % max(1, Int(geo.size.width))), y: CGFloat((i * 47) % 300)) }
                Circle().stroke(.white.opacity(0.12)).frame(width: 310, height: 310)
                sun(label: "APPARENT", color: .orange, size: 92).offset(x: -95, y: 22)
                Path { p in p.move(to: CGPoint(x: geo.size.width/2-45, y: 200)); p.addLine(to: CGPoint(x: geo.size.width/2+90, y: 145)) }.stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5]))
                sun(label: "TRUE NOW", color: Color(red: 0.85, green: 1, blue: 0.25), size: 130).offset(x: 110, y: -35)
                Image(systemName: "globe.americas.fill").font(.system(size: 28)).foregroundStyle(.cyan, .indigo).offset(y: 145)
                Image(systemName: "paperplane.fill").font(.system(size: 30)).foregroundStyle(.white, .orange).rotationEffect(.degrees(-25)).offset(x: launching ? 190 : -20, y: launching ? -230 : 115).opacity(launching ? 0 : 1).animation(.easeIn(duration: 1.1), value: launching)
            }
        }.frame(height: 390).background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 28))
    }

    private func sun(label: String, color: Color, size: CGFloat) -> some View {
        VStack { Circle().fill(RadialGradient(colors: [.white, color], center: .topLeading, startRadius: 0, endRadius: size/2)).shadow(color: color.opacity(0.5), radius: 35).frame(width: size, height: size); Text(label).papyrus(11, weight: .bold).tracking(1.5) }
    }

    private func metrics(_ s: SolarSnapshot) -> some View {
        HStack(spacing: 12) {
            metric("LIGHT DELAY", duration(s.lightTimeSeconds))
            metric("TRUE ALTITUDE", String(format: "%.2f°", s.truePosition.altitude))
            metric("TRUE AZIMUTH", String(format: "%.2f°", s.truePosition.azimuth))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).papyrus(11, weight: .bold).foregroundStyle(.secondary); Text(value).papyrus(23, weight: .bold).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func ritual(_ s: SolarSnapshot) -> some View {
        VStack(spacing: 14) {
            Text(model.ritualComplete ? "Reality corrected." : "The apparent Sun is \(angleDifference(s))° behind its true position.").papyrus(17, weight: .bold)
            Button { launching = true; model.completeRitual(); DispatchQueue.main.asyncAfter(deadline: .now()+1.3) { launching = false } } label: { Label(model.ritualComplete ? "Today's launch complete" : "Launch & correct reality", systemImage: model.ritualComplete ? "checkmark.circle.fill" : "paperplane.fill").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent).tint(Color(red: 0.82, green: 1, blue: 0.2)).foregroundStyle(.black).disabled(model.ritualComplete)
            if let trueRise = s.trueSunrise, let rise = s.sunrise { Text("True sunrise \(trueRise.formatted(date: .omitted, time: .shortened)) · Visible sunrise \(rise.formatted(date: .omitted, time: .shortened))").papyrus(13).foregroundStyle(.secondary) }
        }.padding(22).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func duration(_ seconds: Double) -> String { "\(Int(seconds)/60)m \(Int(seconds)%60)s" }
    private func angleDifference(_ s: SolarSnapshot) -> String {
        let altitudeDelta = s.truePosition.altitude - s.apparent.altitude
        var azimuthDelta = (s.truePosition.azimuth - s.apparent.azimuth).truncatingRemainder(dividingBy: 360)
        if azimuthDelta > 180 { azimuthDelta -= 360 }
        if azimuthDelta < -180 { azimuthDelta += 360 }
        return String(format: "%.3f", hypot(altitudeDelta, azimuthDelta))
    }
}
