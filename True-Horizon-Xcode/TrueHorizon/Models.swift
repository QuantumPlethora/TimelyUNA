import Foundation
import CoreLocation

struct HorizontalPosition: Equatable {
    let altitude: Double
    let azimuth: Double
}

struct SolarSnapshot {
    let date: Date
    let location: CLLocationCoordinate2D
    let apparent: HorizontalPosition
    let truePosition: HorizontalPosition
    let distanceAU: Double
    let lightTimeSeconds: Double
    let sunrise: Date?
    let trueSunrise: Date?
}

enum Epoch: String, CaseIterable, Identifiable {
    case present = "Present"
    case cretaceous = "Cretaceous"
    case jurassic = "Jurassic"
    case deepTime = "Deep Time"
    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .present: "Right now"
        case .cretaceous: "86 million years ago"
        case .jurassic: "171 million years ago"
        case .deepTime: "Beyond the known sky"
        }
    }
}

