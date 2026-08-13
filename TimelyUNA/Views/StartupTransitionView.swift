import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Cold-launch gate (in-memory only; resets every process launch)

/// Claims the one-time cold-launch startup presentation for this process.
/// Not persisted — future cold launches show the sequence again.
enum StartupColdLaunchGate {
    private static var claimed = false

    /// Returns `true` only once per process lifetime.
    static func claimIfNeeded() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }
}

// MARK: - Startup transition

/// Cinematic cold-launch bridge: studio credit → darkened QuantumRootz tree → True Horizon title card.
/// App initialization continues underneath; this view is presentation only.
struct StartupTransitionView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var studioMarkOpacity: Double = 0
    @State private var studioCreditOpacity: Double = 0
    @State private var artworkOpacity: Double = 0
    /// Non-destructive black overlay over artwork (~78–84%).
    @State private var artworkDimOpacity: Double = 0.84
    @State private var productTitleOpacity: Double = 0
    @State private var technologyOpacity: Double = 0
    @State private var dedicationOpacity: Double = 0
    @State private var overlayOpacity: Double = 1
    @State private var sequenceTask: Task<Void, Never>?

    private let textColor = TimelyUNATheme.papyrus.opacity(0.90)

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            // Phase: darkened tree artwork
            artworkLayer
                .opacity(artworkOpacity)
                .accessibilityHidden(true)

            // Phase: studio mark + credit
            studioComposition
                .accessibilityHidden(true)

            // Phase: product title card
            productComposition
                .accessibilityHidden(true)
        }
        .opacity(overlayOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Brand.studioMark). \(Brand.studioCredit). \(Brand.productDisplayName). \(Brand.technologyCredit). \(Brand.cosmicDedication)")
        .onAppear { startSequenceIfNeeded() }
        .onDisappear { sequenceTask?.cancel() }
    }

    // MARK: Studio phase

    private var studioComposition: some View {
        VStack(spacing: studioSpacing) {
            Text(Brand.studioMark)
                .font(studioMarkFont)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .opacity(studioMarkOpacity)

            Text(Brand.studioCredit)
                .font(studioCreditFont)
                .foregroundStyle(textColor.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .opacity(studioCreditOpacity)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
    }

    // MARK: Product title phase

    private var productComposition: some View {
        VStack(spacing: productSpacing) {
            Text(Brand.productDisplayName)
                .font(productTitleFont)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .opacity(productTitleOpacity)

            Text(Brand.technologyCredit)
                .font(technologyFont)
                .foregroundStyle(textColor.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .opacity(technologyOpacity)

            dedicationText
                .opacity(dedicationOpacity)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var dedicationText: some View {
        if useTwoLineDedication {
            VStack(spacing: 4) {
                Text("Congruent with the")
                    .font(dedicationFont)
                Text("Ancestors of the Cosmos")
                    .font(dedicationFont)
            }
            .foregroundStyle(textColor.opacity(0.82))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
        } else {
            Text(Brand.cosmicDedication)
                .font(dedicationFont)
                .foregroundStyle(textColor.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
        }
    }

    private var useTwoLineDedication: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    // MARK: Artwork

    @ViewBuilder
    private var artworkLayer: some View {
        ZStack {
            Color.black

            #if os(macOS)
            Image("QuantumRootzTree")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 520, maxHeight: 680)
                .opacity(0.55)
                .padding(32)
            #else
            Image("QuantumRootzTree")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .opacity(0.55)
            #endif

            Color.black
                .opacity(artworkDimOpacity)
                .allowsHitTesting(false)

            vignetteOverlay
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var vignetteOverlay: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.20),
                    Color.black.opacity(0.60),
                    Color.black.opacity(0.92)
                ],
                center: .center,
                startRadius: 16,
                endRadius: 460
            )
            LinearGradient(
                colors: [Color.black.opacity(0.90), .clear, .clear, Color.black.opacity(0.90)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [Color.black.opacity(0.82), .clear, .clear, Color.black.opacity(0.82)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .blendMode(.multiply)
    }

    // MARK: Papyrus type scale (all opening text)

    private var studioMarkFont: Font {
        papyrus(compact: 28, regular: 34, mac: 36)
    }

    private var studioCreditFont: Font {
        papyrus(compact: 16, regular: 18, mac: 20)
    }

    private var productTitleFont: Font {
        papyrus(compact: 30, regular: 36, mac: 38)
    }

    private var technologyFont: Font {
        papyrus(compact: 16, regular: 18, mac: 19)
    }

    private var dedicationFont: Font {
        papyrus(compact: 13, regular: 14, mac: 15)
    }

    private func papyrus(compact: CGFloat, regular: CGFloat, mac: CGFloat) -> Font {
        #if os(macOS)
        return Font.custom("Papyrus", size: mac, relativeTo: .title3)
        #else
        let size = horizontalSizeClass == .regular ? regular : compact
        return Font.custom("Papyrus", size: size, relativeTo: .title3)
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 56
        #else
        return horizontalSizeClass == .regular ? 44 : 32
        #endif
    }

    private var studioSpacing: CGFloat { 12 }
    private var productSpacing: CGFloat { 14 }

    // MARK: Sequence

    private func startSequenceIfNeeded() {
        sequenceTask?.cancel()
        studioMarkOpacity = 0
        studioCreditOpacity = 0
        artworkOpacity = 0
        artworkDimOpacity = 0.84
        productTitleOpacity = 0
        technologyOpacity = 0
        dedicationOpacity = 0
        overlayOpacity = 1
        sequenceTask = Task { @MainActor in
            await runSequence()
        }
    }

    @MainActor
    private func runSequence() async {
        // Calm cinematic pacing. Reduce Motion: same order, shorter easeInOut fades.
        let rm = reduceMotion
        let blackLead: UInt64 = rm ? 80_000_000 : 200_000_000
        let markIn: UInt64 = rm ? 120_000_000 : 900_000_000
        let creditIn: UInt64 = rm ? 90_000_000 : 650_000_000
        let studioHold: UInt64 = rm ? 180_000_000 : 600_000_000
        let studioOut: UInt64 = rm ? 110_000_000 : 850_000_000
        let blackPause: UInt64 = rm ? 60_000_000 : 150_000_000
        let artIn: UInt64 = rm ? 140_000_000 : 1_100_000_000
        let artHold: UInt64 = rm ? 180_000_000 : 650_000_000
        let artOut: UInt64 = rm ? 110_000_000 : 900_000_000
        let titleIn: UInt64 = rm ? 120_000_000 : 900_000_000
        let techIn: UInt64 = rm ? 80_000_000 : 550_000_000
        let dedicIn: UInt64 = rm ? 90_000_000 : 650_000_000
        let finalHold: UInt64 = rm ? 200_000_000 : 750_000_000
        let crossOut: UInt64 = rm ? 120_000_000 : 900_000_000

        func ease(_ d: Double) -> Animation { .easeInOut(duration: d) }
        let dMarkIn = rm ? 0.12 : 0.90
        let dCreditIn = rm ? 0.09 : 0.65
        let dStudioOut = rm ? 0.11 : 0.85
        let dArtIn = rm ? 0.14 : 1.10
        let dArtOut = rm ? 0.11 : 0.90
        let dTitleIn = rm ? 0.12 : 0.90
        let dTechIn = rm ? 0.08 : 0.55
        let dDedicIn = rm ? 0.09 : 0.65
        let dCross = rm ? 0.12 : 0.90

        // 1) Pure black
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: blackLead)

        // 2) QuantumRootz
        guard !Task.isCancelled else { return }
        withAnimation(ease(dMarkIn)) { studioMarkOpacity = 1 }
        try? await Task.sleep(nanoseconds: markIn)

        // 3) A QuantumRootz Studio
        guard !Task.isCancelled else { return }
        withAnimation(ease(dCreditIn)) { studioCreditOpacity = 1 }
        try? await Task.sleep(nanoseconds: creditIn)

        // 4) Hold studio composition
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: studioHold)

        // 5) Fade studio to black
        guard !Task.isCancelled else { return }
        withAnimation(ease(dStudioOut)) {
            studioMarkOpacity = 0
            studioCreditOpacity = 0
        }
        try? await Task.sleep(nanoseconds: studioOut)

        // 6) Brief black
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: blackPause)

        // 7) Darkened tree fade in (overlay ~84% → ~80% clearest)
        guard !Task.isCancelled else { return }
        artworkDimOpacity = 0.84
        withAnimation(ease(dArtIn)) { artworkOpacity = 1 }
        try? await Task.sleep(nanoseconds: artIn / 2)
        guard !Task.isCancelled else { return }
        withAnimation(ease(rm ? 0.10 : 0.40)) { artworkDimOpacity = 0.80 }
        try? await Task.sleep(nanoseconds: artIn - artIn / 2)

        // 8) Hold artwork
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: artHold)

        // 9) Fade artwork toward black
        guard !Task.isCancelled else { return }
        withAnimation(ease(dArtOut)) {
            artworkDimOpacity = 0.94
            artworkOpacity = 0
        }
        try? await Task.sleep(nanoseconds: artOut)

        // 10) True Horizon
        guard !Task.isCancelled else { return }
        withAnimation(ease(dTitleIn)) { productTitleOpacity = 1 }
        try? await Task.sleep(nanoseconds: titleIn)

        // 11) Driven by TimelyUNA (Brand.technologyCredit)
        guard !Task.isCancelled else { return }
        withAnimation(ease(dTechIn)) { technologyOpacity = 1 }
        try? await Task.sleep(nanoseconds: techIn)

        // 12) Dedication
        guard !Task.isCancelled else { return }
        withAnimation(ease(dDedicIn)) { dedicationOpacity = 1 }
        try? await Task.sleep(nanoseconds: dedicIn)

        // 13) Hold final composition
        guard !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: finalHold)

        // 14) Crossfade into app
        guard !Task.isCancelled else { return }
        withAnimation(ease(dCross)) {
            productTitleOpacity = 0
            technologyOpacity = 0
            dedicationOpacity = 0
            overlayOpacity = 0
        }
        try? await Task.sleep(nanoseconds: crossOut)

        guard !Task.isCancelled else { return }
        // Remove from hierarchy via parent flag — cannot intercept touches after finish.
        onFinished()
    }
}
