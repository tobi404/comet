// Rendering a SwiftUI view to pixels, and measuring what came out.
//
// Shared by the resting marker's tests (§4) and the Note Card's (§5), because
// both measure a RENDERED result rather than reading a constant back: a rule
// that resolves to the right number in arithmetic and the wrong number on
// screen is exactly the class of defect these two sections found by building.

import SwiftUI
import XCTest

@testable import Zeron

/// The pixel scale views render at. 3 is a real device's, and it is what makes
/// a sub-point measurement honest: one pixel is 1/3 of a point.
let renderScale: CGFloat = 3

/// An iPhone 17 Pro's width in points.
let screenWidth: CGFloat = 402

struct Raster {
    let pixels: [UInt8]  // RGBA8, premultiplied-last
    let width: Int
    let height: Int

    /// The rendered size in POINTS.
    var size: CGSize {
        CGSize(width: CGFloat(width) / renderScale, height: CGFloat(height) / renderScale)
    }

    /// The colour at a POINT coordinate, sampled at the pixel that contains it.
    func at(x: CGFloat, y: CGFloat) -> [Double] {
        pixel(px: Int(x * renderScale), py: Int(y * renderScale))
    }

    /// The vertical extent, in POINTS, of everything in the column at `x`
    /// that differs from `background` by more than half the way to `ink`.
    /// Half-way is the antialiased edge, so the run this returns is the mark's
    /// true extent to within a third of a point.
    func runHeight(atX x: CGFloat, ink: [Double], background: [Double]) -> CGFloat {
        let px = clampX(Int(x * renderScale))
        let full = distance(ink, background)
        var first = -1, last = -1
        for py in 0..<height where distance(pixel(px: px, py: py), background) > full / 2 {
            if first < 0 { first = py }
            last = py
        }
        guard first >= 0 else { return 0 }
        return CGFloat(last - first + 1) / renderScale
    }

    /// The first POINT along the row at `y`, scanning from `from` rightwards,
    /// whose colour differs from `background` by more than `tolerance`.
    /// `nil` when the row is background all the way across.
    func firstDifferingX(atY y: CGFloat, from: CGFloat, background: [Double],
                         tolerance: Double = 0.02) -> CGFloat? {
        let py = clampY(Int(y * renderScale))
        for px in clampX(Int(from * renderScale))..<width
        where distance(pixel(px: px, py: py), background) > tolerance {
            return CGFloat(px) / renderScale
        }
        return nil
    }

    /// The same scan down the column at `x`.
    func firstDifferingY(atX x: CGFloat, from: CGFloat, background: [Double],
                         tolerance: Double = 0.02) -> CGFloat? {
        let px = clampX(Int(x * renderScale))
        for py in clampY(Int(from * renderScale))..<height
        where distance(pixel(px: px, py: py), background) > tolerance {
            return CGFloat(py) / renderScale
        }
        return nil
    }

    /// Whether any pixel in the POINT rectangle differs from `background`.
    func hasInk(in rect: CGRect, background: [Double], tolerance: Double = 0.02) -> Bool {
        let x0 = clampX(Int(rect.minX * renderScale)), x1 = clampX(Int(rect.maxX * renderScale))
        let y0 = clampY(Int(rect.minY * renderScale)), y1 = clampY(Int(rect.maxY * renderScale))
        guard x0 <= x1, y0 <= y1 else { return false }
        for py in y0...y1 {
            for px in x0...x1 where distance(pixel(px: px, py: py), background) > tolerance {
                return true
            }
        }
        return false
    }

    /// The vertical runs of ink inside a POINT rectangle — one per drawn line
    /// of text. `minLuma` is what separates painted glyphs from the surface
    /// they sit on.
    func inkBands(in rect: CGRect, minLuma: Double) -> [(top: CGFloat, bottom: CGFloat)] {
        let x0 = clampX(Int(rect.minX * renderScale)), x1 = clampX(Int(rect.maxX * renderScale))
        let y0 = clampY(Int(rect.minY * renderScale)), y1 = clampY(Int(rect.maxY * renderScale))
        var bands: [(CGFloat, CGFloat)] = []
        var start: Int?
        for py in y0...y1 {
            let inked = (x0...x1).contains { luma(pixel(px: $0, py: py)) > minLuma }
            if inked, start == nil { start = py }
            if !inked, let s = start {
                bands.append((CGFloat(s) / renderScale, CGFloat(py - 1) / renderScale))
                start = nil
            }
        }
        if let s = start { bands.append((CGFloat(s) / renderScale, CGFloat(y1) / renderScale)) }
        return bands
    }

    private func luma(_ c: [Double]) -> Double {
        0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
    }

    private func pixel(px: Int, py: Int) -> [Double] {
        let i = (clampY(py) * width + clampX(px)) * 4
        return [Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255]
    }

    private func clampX(_ px: Int) -> Int { min(width - 1, max(0, px)) }
    private func clampY(_ py: Int) -> Int { min(height - 1, max(0, py)) }

    private func distance(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }
}

@MainActor
func raster<V: View>(_ view: V) -> Raster {
    let renderer = ImageRenderer(content: AnyView(view))
    renderer.scale = renderScale
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { preconditionFailure("view did not render") }
    let (w, h) = (cg.width, cg.height)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Raster(pixels: pixels, width: w, height: h)
}

/// A colour's sRGB channels, 0...1.
func srgb(_ color: Color) -> [Double] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return [Double(r), Double(g), Double(b)]
}

/// The same channels as whole 0...255 units, which is how §5's veil constant
/// and §9's "within 2 per channel" are both stated.
func units(_ color: Color) -> [Int] {
    srgb(color).map { Int(($0 * 255).rounded()) }
}
