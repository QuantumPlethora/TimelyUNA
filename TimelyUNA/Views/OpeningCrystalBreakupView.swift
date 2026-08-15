import SwiftUI

/// Irregular crystalline shards of the opening still. Progress 0 = assembled plate;
/// progress 1 = dispersed / faded. Content behind shows through the gaps.
struct OpeningCrystalBreakupView: View {
    let progress: Double
    let reduceMotion: Bool
    let presentation: OpeningArtworkPresentation
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let frame = presentation.imageFrame(in: size)
        let resolved = context.resolve(Image("QuantumRootzTree"))
        let shards = CrystalShard.makeMesh(in: size, seed: seed, reduceMotion: reduceMotion)
        let t = min(1, max(0, progress))
        let ease = t * t * (3 - 2 * t)

        for shard in shards {
            var local = context
            let fly = reduceMotion ? ease * 0.22 : ease
            let dx = shard.outward.x * size.width * (reduceMotion ? 0.04 : 0.22) * fly
            let dy = shard.outward.y * size.height * (reduceMotion ? 0.03 : 0.18) * fly
            let lift = reduceMotion ? 0.0 : (1 - shard.depth) * 28 * fly
            local.translateBy(x: shard.centroid.x * size.width + dx, y: shard.centroid.y * size.height + dy - lift)
            let spin = reduceMotion ? shard.spin * 8 * ease : shard.spin * 38 * ease
            local.rotate(by: .degrees(spin))
            let sc = reduceMotion
                ? (1 - 0.18 * ease)
                : max(0.12, 1 - 0.55 * ease) * (0.88 + shard.depth * 0.22)
            local.scaleBy(x: sc, y: sc * (1 - 0.18 * fly * (1 - shard.depth)))
            local.opacity = max(0, 1 - ease * (reduceMotion ? 1.05 : 1.15))
            local.translateBy(x: -shard.centroid.x * size.width, y: -shard.centroid.y * size.height)

            var plate = Path()
            plate.move(to: CGPoint(x: shard.u0.x * size.width, y: shard.u0.y * size.height))
            plate.addLine(to: CGPoint(x: shard.u1.x * size.width, y: shard.u1.y * size.height))
            plate.addLine(to: CGPoint(x: shard.u2.x * size.width, y: shard.u2.y * size.height))
            plate.closeSubpath()
            local.clip(to: plate)
            local.draw(resolved, in: frame)

            // Hairline facet edge — sells crystal without a second mesh.
            var edge = context
            edge.translateBy(x: shard.centroid.x * size.width + dx, y: shard.centroid.y * size.height + dy - lift)
            edge.rotate(by: .degrees(spin))
            edge.scaleBy(x: sc, y: sc * (1 - 0.18 * fly * (1 - shard.depth)))
            edge.opacity = max(0, 0.55 * (1 - ease))
            edge.translateBy(x: -shard.centroid.x * size.width, y: -shard.centroid.y * size.height)
            edge.stroke(
                plate,
                with: .color(Color.white.opacity(0.28)),
                lineWidth: reduceMotion ? 0.4 : 0.7
            )
        }
    }
}

// MARK: - Irregular triangular mesh (unit UV)

private struct CrystalShard {
    let u0: CGPoint
    let u1: CGPoint
    let u2: CGPoint
    let outward: CGPoint
    let spin: Double
    let depth: Double

    var centroid: CGPoint {
        CGPoint(x: (u0.x + u1.x + u2.x) / 3, y: (u0.y + u1.y + u2.y) / 3)
    }

    static func makeMesh(in size: CGSize, seed: UInt64, reduceMotion: Bool) -> [CrystalShard] {
        var rng = CrystalRNG(seed: seed == 0 ? 0xC051_CB1A : seed)
        let cols = reduceMotion ? 4 : 5
        let rows = reduceMotion ? 5 : 6
        var pts: [[CGPoint]] = []
        for r in 0...rows {
            var row: [CGPoint] = []
            for c in 0...cols {
                var u = CGFloat(c) / CGFloat(cols)
                var v = CGFloat(r) / CGFloat(rows)
                if c > 0, c < cols, r > 0, r < rows {
                    let j: CGFloat = 0.13
                    u += CGFloat(rng.unitSigned()) * j
                    v += CGFloat(rng.unitSigned()) * j
                    u = min(0.999, max(0.001, u))
                    v = min(0.999, max(0.001, v))
                }
                row.append(CGPoint(x: u, y: v))
            }
            pts.append(row)
        }

        var shards: [CrystalShard] = []
        for r in 0..<rows {
            for c in 0..<cols {
                let p00 = pts[r][c]
                let p10 = pts[r][c + 1]
                let p01 = pts[r + 1][c]
                let p11 = pts[r + 1][c + 1]
                let flip = rng.unit() > 0.5
                let tris: [(CGPoint, CGPoint, CGPoint)] = flip
                    ? [(p00, p10, p11), (p00, p11, p01)]
                    : [(p00, p10, p01), (p10, p11, p01)]
                for tri in tris {
                    let mid = CGPoint(
                        x: (tri.0.x + tri.1.x + tri.2.x) / 3,
                        y: (tri.0.y + tri.1.y + tri.2.y) / 3
                    )
                    var ox = mid.x - 0.5
                    var oy = mid.y - 0.5
                    let len = max(0.08, sqrt(ox * ox + oy * oy))
                    ox /= len
                    oy /= len
                    shards.append(
                        CrystalShard(
                            u0: tri.0,
                            u1: tri.1,
                            u2: tri.2,
                            outward: CGPoint(x: ox, y: oy),
                            spin: rng.unitSigned() * 1.0,
                            depth: rng.unit()
                        )
                    )
                }
            }
        }
        return shards
    }
}

private struct CrystalRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
    mutating func unit() -> Double { Double(next() % 10_000) / 10_000.0 }
    mutating func unitSigned() -> Double { unit() * 2 - 1 }
}
