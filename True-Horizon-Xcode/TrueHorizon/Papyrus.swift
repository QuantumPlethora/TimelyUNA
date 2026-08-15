import SwiftUI

extension View {
    /// The project's single typographic voice. Papyrus is bundled with Apple platforms.
    func papyrus(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.custom("Papyrus", size: size).weight(weight))
    }
}
