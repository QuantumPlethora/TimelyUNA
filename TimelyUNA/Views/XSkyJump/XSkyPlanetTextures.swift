import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
public typealias XSkyImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias XSkyImage = NSImage
#endif

/// Procedural educational planet textures (no external assets / licenses).
enum XSkyPlanetTextures {
    static func earthDiffuse(size: Int = 512) -> XSkyImage {
        makeImage(size: size) { ctx, w, h in
            // Ocean base
            ctx.setFillColor(CGColor(red: 0.12, green: 0.28, blue: 0.55, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Continents (soft blobs)
            let land = CGColor(red: 0.22, green: 0.42, blue: 0.20, alpha: 1)
            let desert = CGColor(red: 0.55, green: 0.48, blue: 0.28, alpha: 0.85)
            ctx.setFillColor(land)
            addBlob(ctx, cx: w * 0.28, cy: h * 0.42, rx: w * 0.16, ry: h * 0.22)
            addBlob(ctx, cx: w * 0.55, cy: h * 0.38, rx: w * 0.12, ry: h * 0.18)
            addBlob(ctx, cx: w * 0.72, cy: h * 0.55, rx: w * 0.10, ry: h * 0.14)
            addBlob(ctx, cx: w * 0.40, cy: h * 0.62, rx: w * 0.14, ry: h * 0.10)
            ctx.setFillColor(desert)
            addBlob(ctx, cx: w * 0.52, cy: h * 0.48, rx: w * 0.06, ry: h * 0.05)

            // Polar ice
            ctx.setFillColor(CGColor(red: 0.92, green: 0.95, blue: 0.98, alpha: 0.9))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: w, height: h * 0.08))
            ctx.fillEllipse(in: CGRect(x: 0, y: h * 0.92, width: w, height: h * 0.08))

            // Soft noise speckles
            for i in 0..<400 {
                let x = pseudo(i * 13) * w
                let y = pseudo(i * 29 + 3) * h
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.04 + pseudo(i) * 0.05))
                ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }

    static func earthClouds(size: Int = 512) -> XSkyImage {
        makeImage(size: size) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0, alpha: 0))
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
            for i in 0..<28 {
                let x = pseudo(i * 17 + 2) * w
                let y = pseudo(i * 41 + 5) * h
                let rx = w * (0.04 + pseudo(i * 3) * 0.08)
                let ry = h * (0.015 + pseudo(i * 7) * 0.03)
                addBlob(ctx, cx: x, cy: y, rx: rx, ry: ry)
            }
        }
    }

    static func earthNightLights(size: Int = 512) -> XSkyImage {
        makeImage(size: size) { ctx, w, h in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for i in 0..<180 {
                let x = pseudo(i * 19 + 1) * w
                let y = pseudo(i * 37 + 9) * h * 0.7 + h * 0.15
                let a = 0.25 + pseudo(i * 5) * 0.55
                ctx.setFillColor(CGColor(red: 1.0, green: 0.9, blue: 0.55, alpha: a))
                let s = 1.0 + pseudo(i) * 1.8
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
            }
        }
    }

    static func marsDiffuse(size: Int = 512) -> XSkyImage {
        makeImage(size: size) { ctx, w, h in
            ctx.setFillColor(CGColor(red: 0.55, green: 0.28, blue: 0.16, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Dark volcanic plains
            ctx.setFillColor(CGColor(red: 0.28, green: 0.14, blue: 0.10, alpha: 0.75))
            addBlob(ctx, cx: w * 0.35, cy: h * 0.45, rx: w * 0.18, ry: h * 0.12)
            addBlob(ctx, cx: w * 0.65, cy: h * 0.55, rx: w * 0.14, ry: h * 0.10)

            // Ochre highlands
            ctx.setFillColor(CGColor(red: 0.72, green: 0.42, blue: 0.22, alpha: 0.65))
            addBlob(ctx, cx: w * 0.55, cy: h * 0.35, rx: w * 0.16, ry: h * 0.14)
            addBlob(ctx, cx: w * 0.25, cy: h * 0.60, rx: w * 0.12, ry: h * 0.08)

            // Polar caps
            ctx.setFillColor(CGColor(red: 0.95, green: 0.93, blue: 0.90, alpha: 0.85))
            ctx.fillEllipse(in: CGRect(x: w * 0.35, y: 0, width: w * 0.3, height: h * 0.07))
            ctx.fillEllipse(in: CGRect(x: w * 0.38, y: h * 0.93, width: w * 0.24, height: h * 0.07))

            // Subtle crater speckles
            for i in 0..<90 {
                let x = pseudo(i * 23) * w
                let y = pseudo(i * 47 + 4) * h
                let r = 1.5 + pseudo(i * 3) * 4
                ctx.setStrokeColor(CGColor(red: 0.2, green: 0.1, blue: 0.08, alpha: 0.35))
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
    }

    // MARK: - Helpers

    private static func makeImage(size: Int, draw: (CGContext, CGFloat, CGFloat) -> Void) -> XSkyImage {
        let w = size
        let h = size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            #if canImport(UIKit)
            return UIImage()
            #else
            return NSImage(size: NSSize(width: w, height: h))
            #endif
        }
        draw(ctx, CGFloat(w), CGFloat(h))
        guard let cg = ctx.makeImage() else {
            #if canImport(UIKit)
            return UIImage()
            #else
            return NSImage(size: NSSize(width: w, height: h))
            #endif
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        #endif
    }

    private static func addBlob(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) {
        ctx.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func pseudo(_ seed: Int) -> CGFloat {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return CGFloat(v - floor(v))
    }
}
