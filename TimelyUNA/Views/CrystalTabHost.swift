import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Crystallize outgoing tab → shards fall into one randomized black hole → destination slides in.
/// Snapshot is taken from the already-rendered host so ImageRenderer never remounts tab views
/// (which would restart Horizon LightLine via onAppear).
struct CrystalTabHost<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    /// Mounted body + chrome (header). Trails `selection` until the destination is revealed.
    @Binding var displayed: Selection
    var order: [Selection]
    @ViewBuilder var content: (Selection) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .idle
    @State private var pending: Selection?
    @State private var session: Session?
    @State private var incomingOpacity: Double = 1
    @State private var incomingOffset: CGFloat = 0
    @State private var token = UUID()
    @State private var canvasSize: CGSize = .zero
    @State private var snapshotBox = LiveSnapshotBox()

    private enum Phase: Equatable {
        case idle, shattering, revealing
    }

    struct Session {
        let image: CGImage
        let shards: [TabCrystalShard]
        let focus: UnitPoint
        let startedAt: Date
        let reduceMotion: Bool
        let forward: Bool
        let duration: Double
        let crystallizeEnd: Double
    }

    init(
        selection: Binding<Selection>,
        displayed: Binding<Selection>,
        order: [Selection],
        @ViewBuilder content: @escaping (Selection) -> Content
    ) {
        self._selection = selection
        self._displayed = displayed
        self.order = order
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if phase == .shattering {
                    TransitionUniverseBackdrop()
                        .zIndex(0)
                }

                content(displayed)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(incomingOpacity)
                    .offset(x: incomingOffset)
                    .zIndex(1)

                LiveSnapshotAnchor(box: snapshotBox)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(2)

                if let session {
                    TabCrystalOverlay(
                        image: session.image,
                        shards: session.shards,
                        focus: session.focus,
                        startedAt: session.startedAt,
                        duration: session.duration,
                        crystallizeEnd: session.crystallizeEnd,
                        reduceMotion: session.reduceMotion
                    )
                    .allowsHitTesting(true)
                    .accessibilityHidden(true)
                    .zIndex(10)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .background(Color.clear)
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { _, s in canvasSize = s }
        }
        .onChange(of: selection) { _, newValue in
            request(newValue)
        }
    }

    private func request(_ newValue: Selection) {
        if newValue == displayed, phase == .idle {
            pending = nil
            return
        }
        if phase != .idle {
            // Ignore overlapping taps. Keep the in-flight destination selected;
            // do not revert chrome to the outgoing screen or start a second run.
            let keep = pending ?? displayed
            if selection != keep {
                selection = keep
            }
            return
        }
        pending = newValue
        if reduceMotion {
            runReduceMotion(to: newValue)
            return
        }
        runShatter(to: newValue)
    }

    private func isForward(to newValue: Selection) -> Bool {
        let a = order.firstIndex(of: displayed) ?? 0
        let b = order.firstIndex(of: newValue) ?? 0
        return b >= a
    }

    private func runReduceMotion(to newValue: Selection) {
        let t = UUID()
        token = t
        phase = .shattering
        let forward = isForward(to: newValue)

        if let image = snapshotBox.capture?(),
           let shards = Optional(TabCrystalShard.make(seed: UInt64.random(in: 1...UInt64.max), dense: false)),
           !shards.isEmpty {
            session = Session(
                image: image,
                shards: shards,
                focus: randomFocus(seed: UInt64.random(in: 1...UInt64.max)),
                startedAt: Date(),
                reduceMotion: true,
                forward: forward,
                duration: 0.36,
                crystallizeEnd: 0.20
            )
        }

        withAnimation(.easeInOut(duration: 0.20)) {
            incomingOpacity = 0
            incomingOffset = forward ? -10 : 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard token == t else { return }
            displayed = newValue
            incomingOffset = forward ? 16 : -16
            incomingOpacity = 0
            phase = .revealing
            withAnimation(.easeOut(duration: 0.28)) {
                incomingOpacity = 1
                incomingOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard token == t else { return }
            session = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            guard token == t else { return }
            incomingOpacity = 1
            incomingOffset = 0
            pending = nil
            phase = .idle
        }
    }

    private func runShatter(to newValue: Selection) {
        let size = canvasSize
        guard size.width > 8, size.height > 8 else {
            displayed = newValue
            pending = nil
            phase = .idle
            return
        }

        let t = UUID()
        token = t
        phase = .shattering
        let forward = isForward(to: newValue)
        let seed = UInt64.random(in: 1...UInt64.max)
        let focus = randomFocus(seed: seed)

        guard let image = snapshotBox.capture?() else {
            runCrossfade(to: newValue, token: t, forward: forward)
            return
        }
        let shards = TabCrystalShard.make(seed: seed, dense: true)
        guard !shards.isEmpty else {
            runCrossfade(to: newValue, token: t, forward: forward)
            return
        }

        let duration = 1.18
        let crystallizeEnd = 0.16
        // Overlay mounts on top of the still-visible outgoing screen.
        session = Session(
            image: image,
            shards: shards,
            focus: focus,
            startedAt: Date(),
            reduceMotion: false,
            forward: forward,
            duration: duration,
            crystallizeEnd: crystallizeEnd
        )

        // Next frame: hide live body so shard gaps reveal CosmicBackground, not a black plate.
        DispatchQueue.main.async {
            guard token == t else { return }
            incomingOpacity = 0
            incomingOffset = 0
        }

        // Destination waits until outgoing shards have faded to zero.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard token == t else { return }
            session = nil
            displayed = newValue
            incomingOffset = forward ? 22 : -22
            incomingOpacity = 0
            phase = .revealing
            withAnimation(.easeOut(duration: 0.40)) {
                incomingOpacity = 1
                incomingOffset = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.46) {
            guard token == t else { return }
            incomingOpacity = 1
            incomingOffset = 0
            pending = nil
            phase = .idle
        }
    }

    /// Snapshot-less fallback — still directional, still locked against overlap.
    private func runCrossfade(to newValue: Selection, token t: UUID, forward: Bool) {
        token = t
        phase = .shattering
        withAnimation(.easeInOut(duration: 0.22)) {
            incomingOpacity = 0
            incomingOffset = forward ? -10 : 10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard token == t else { return }
            displayed = newValue
            incomingOffset = forward ? 16 : -16
            incomingOpacity = 0
            phase = .revealing
            withAnimation(.easeOut(duration: 0.28)) {
                incomingOpacity = 1
                incomingOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                guard token == t else { return }
                pending = nil
                phase = .idle
            }
        }
    }

    /// Stay inside the visible content plate — away from edges and chrome.
    private func randomFocus(seed: UInt64) -> UnitPoint {
        var rng = TabCrystalRNG(seed: seed ^ 0xB10C)
        let x = 0.24 + rng.unit() * 0.52
        let y = 0.28 + rng.unit() * 0.40
        return UnitPoint(x: x, y: y)
    }
}

/// Text-free eclipse artwork shown only beneath the outgoing crystalline shards.
/// `scaledToFit` keeps the complete surrounding universe visible on every canvas;
/// the black base naturally fills any letterboxed space without stretching the art.
private struct TransitionUniverseBackdrop: View {
    var body: some View {
        ZStack {
            Color.black

            Image("TimelyUNATransitionBackdrop")
                .resizable()
                .scaledToFit()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Live snapshot (already-rendered host, no view remount)

final class LiveSnapshotBox {
    var capture: (() -> CGImage?)?
}

#if os(macOS)
private final class SnapshotHostView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func captureVisible() -> CGImage? {
        guard bounds.width > 8, bounds.height > 8 else { return nil }
        if let image = captureAncestor() { return image }
        return captureWindowPixels()
    }

    /// Walk to a real hosting ancestor and cache the probe’s rectangle.
    private func captureAncestor() -> CGImage? {
        var node = superview
        var target: NSView?
        while let cur = node {
            if cur.bounds.width + 1 >= bounds.width, cur.bounds.height + 1 >= bounds.height {
                target = cur
            }
            node = cur.superview
        }
        guard let target else { return nil }
        let rect = convert(bounds, to: target)
        guard rect.width > 8, rect.height > 8 else { return nil }
        target.layoutSubtreeIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        target.cacheDisplay(in: rect, to: rep)
        guard let image = rep.cgImage, image.width > 2, image.height > 2 else { return nil }
        if isMostlyEmpty(image) { return nil }
        return image
    }

    /// Last resort: the actual on-screen window pixels for this rect.
    private func captureWindowPixels() -> CGImage? {
        guard let window, let primary = NSScreen.screens.first else { return nil }
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        let q = CGRect(
            x: screenRect.origin.x,
            y: primary.frame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
        guard let image = CGWindowListCreateImage(
            q,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ), image.width > 2, image.height > 2 else { return nil }
        if isMostlyEmpty(image) { return nil }
        return image
    }
}

private struct LiveSnapshotAnchor: NSViewRepresentable {
    let box: LiveSnapshotBox

    func makeNSView(context: Context) -> SnapshotHostView {
        let view = SnapshotHostView()
        box.capture = { [weak view] in view?.captureVisible() }
        return view
    }

    func updateNSView(_ nsView: SnapshotHostView, context: Context) {
        box.capture = { [weak nsView] in nsView?.captureVisible() }
    }
}
#else
private final class SnapshotHostView: UIView {
    func captureVisible() -> CGImage? {
        guard bounds.width > 8, bounds.height > 8 else { return nil }
        if let image = captureAncestor() { return image }
        return captureWindowPixels()
    }

    private func captureAncestor() -> CGImage? {
        var node = superview
        var target: UIView?
        while let cur = node {
            if cur.bounds.width + 1 >= bounds.width, cur.bounds.height + 1 >= bounds.height {
                target = cur
            }
            node = cur.superview
        }
        guard let target else { return nil }
        let rect = convert(bounds, to: target)
        guard rect.width > 8, rect.height > 8 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: rect.size), format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            target.drawHierarchy(in: target.bounds, afterScreenUpdates: false)
        }
        guard let cg = image.cgImage, cg.width > 2 else { return nil }
        if isMostlyEmpty(cg) { return nil }
        return cg
    }

    private func captureWindowPixels() -> CGImage? {
        guard let window else { return nil }
        let rect = convert(bounds, to: window)
        guard rect.width > 8, rect.height > 8 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: bounds.size), format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let cg = image.cgImage, cg.width > 2 else { return nil }
        if isMostlyEmpty(cg) { return nil }
        return cg
    }
}

private struct LiveSnapshotAnchor: UIViewRepresentable {
    let box: LiveSnapshotBox

    func makeUIView(context: Context) -> SnapshotHostView {
        let view = SnapshotHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        box.capture = { [weak view] in view?.captureVisible() }
        return view
    }

    func updateUIView(_ uiView: SnapshotHostView, context: Context) {
        box.capture = { [weak uiView] in uiView?.captureVisible() }
    }
}
#endif

/// Reject fully transparent / near-black empty plates so we fall back to a crossfade.
private func isMostlyEmpty(_ image: CGImage) -> Bool {
    let w = min(image.width, 48)
    let h = min(image.height, 48)
    guard w > 2, h > 2 else { return true }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var data = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(
        data: &data,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return false }
    ctx.interpolationQuality = .low
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var opaque = 0
    var i = 0
    while i < data.count {
        if data[i + 3] > 16 { opaque += 1 }
        i += 4
    }
    return opaque < (w * h) / 12
}

// MARK: - Overlay

private struct TabCrystalOverlay: View {
    let image: CGImage
    let shards: [TabCrystalShard]
    let focus: UnitPoint
    let startedAt: Date
    let duration: Double
    let crystallizeEnd: Double
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let raw = min(1, max(0, elapsed / duration))
            let t = raw * raw * (3 - 2 * raw)
            Canvas { context, canvas in
                draw(context: &context, size: canvas, progress: t)
            }
        }
        .allowsHitTesting(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize, progress t: Double) {
        let resolved = context.resolve(Image(decorative: image, scale: 1, orientation: .up))
        // Invisible attraction point — drives shard trajectories only; nothing is drawn here.
        let fx = focus.x * size.width
        let fy = focus.y * size.height

        for shard in shards {
            let start = CGPoint(x: shard.centroid.x * size.width, y: shard.centroid.y * size.height)
            let delay = shard.delay
            let span = max(0.16, 1 - delay)
            let local = min(1, max(0, (t - delay) / span))

            let pull: Double
            let facet: Double
            if reduceMotion {
                pull = 0
                facet = local
            } else if local < crystallizeEnd {
                pull = 0
                facet = local / max(0.001, crystallizeEnd)
            } else {
                let u = (local - crystallizeEnd) / max(0.001, 1 - crystallizeEnd)
                pull = u * u * (3 - 2 * u)
                facet = 1
            }

            let ease = pull
            let px = start.x + (fx - start.x) * ease
            let py = start.y + (fy - start.y) * ease
            let sc = reduceMotion
                ? max(0.72, 1 - 0.28 * facet)
                : max(0.04, 1 - 0.94 * ease)
            let fade = reduceMotion
                ? max(0, 1 - facet * 1.05)
                : max(0, 1 - ease)
            let spin = reduceMotion ? shard.spin * 6 * facet : shard.spin * 52 * ease
            let persp = reduceMotion ? 1.0 : (1 - 0.18 * ease)

            var localCtx = context
            localCtx.translateBy(x: px, y: py)
            localCtx.rotate(by: .degrees(spin))
            localCtx.scaleBy(x: sc, y: sc * persp)
            localCtx.opacity = fade
            localCtx.translateBy(x: -start.x, y: -start.y)
            var plate = Path()
            plate.move(to: CGPoint(x: shard.u0.x * size.width, y: shard.u0.y * size.height))
            plate.addLine(to: CGPoint(x: shard.u1.x * size.width, y: shard.u1.y * size.height))
            plate.addLine(to: CGPoint(x: shard.u2.x * size.width, y: shard.u2.y * size.height))
            plate.closeSubpath()
            localCtx.clip(to: plate)
            localCtx.draw(resolved, in: CGRect(origin: .zero, size: size))

            var edge = context
            edge.translateBy(x: px, y: py)
            edge.rotate(by: .degrees(spin))
            edge.scaleBy(x: sc, y: sc * persp)
            edge.opacity = fade * (0.35 + 0.35 * facet)
            edge.translateBy(x: -start.x, y: -start.y)
            edge.stroke(plate, with: .color(Color.white.opacity(0.32)), lineWidth: 0.65)
        }
    }
}

struct TabCrystalShard {
    let u0: CGPoint
    let u1: CGPoint
    let u2: CGPoint
    let delay: Double
    let spin: Double
    var centroid: CGPoint {
        CGPoint(x: (u0.x + u1.x + u2.x) / 3, y: (u0.y + u1.y + u2.y) / 3)
    }

    static func make(seed: UInt64, dense: Bool) -> [TabCrystalShard] {
        var rng = TabCrystalRNG(seed: seed)
        let cols = dense ? 6 : 4
        let rows = dense ? 7 : 5
        var pts: [[CGPoint]] = []
        for r in 0...rows {
            var row: [CGPoint] = []
            for c in 0...cols {
                var u = CGFloat(c) / CGFloat(cols)
                var v = CGFloat(r) / CGFloat(rows)
                if c > 0, c < cols, r > 0, r < rows {
                    u += CGFloat(rng.unitSigned()) * 0.11
                    v += CGFloat(rng.unitSigned()) * 0.11
                    u = min(0.999, max(0.001, u))
                    v = min(0.999, max(0.001, v))
                }
                row.append(CGPoint(x: u, y: v))
            }
            pts.append(row)
        }
        var shards: [TabCrystalShard] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let p00 = pts[r][c], p10 = pts[r][c + 1], p01 = pts[r + 1][c], p11 = pts[r + 1][c + 1]
                let tris: [(CGPoint, CGPoint, CGPoint)] = rng.unit() > 0.5
                    ? [(p00, p10, p11), (p00, p11, p01)]
                    : [(p00, p10, p01), (p10, p11, p01)]
                for tri in tris {
                    shards.append(
                        TabCrystalShard(
                            u0: tri.0, u1: tri.1, u2: tri.2,
                            delay: rng.unit() * 0.20,
                            spin: rng.unitSigned()
                        )
                    )
                }
            }
        }
        return shards
    }
}

struct TabCrystalRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000 }
    mutating func unitSigned() -> Double { unit() * 2 - 1 }
}
