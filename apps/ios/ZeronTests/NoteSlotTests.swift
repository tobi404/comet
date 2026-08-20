// The five Colour Slots (spec §3; tests 8-13).
//
// Every assertion here measures the colour that actually PAINTS. The tone
// constants and the hues are file-private in `NoteSlots.swift` on purpose
// (§3), so these tests read the channels back off the rendered `Color` and
// re-derive L, C, luminance and ΔE from them. That is the honest measurement:
// a clamp inside `oklchToSrgb` is invisible to the recipe and visible here.

import SwiftUI
import XCTest

@testable import Zeron

// MARK: - Reading a painted colour back

/// What a `Color` actually paints: sRGB channels 0..1, and its alpha.
private func painted(_ color: Color) -> (rgb: [Double], alpha: Double) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
    return ([Double(r), Double(g), Double(b)], Double(a))
}

/// The sRGB channels a `Color` actually paints, 0..1.
private func channels(_ color: Color) -> [Double] { painted(color).rgb }

/// The alpha a `Color` actually paints — the wash tests read their alpha from
/// `Theme` rather than hardcoding 0.06 and 0.10, so a re-tune of the wash
/// moves the test with it.
private func alpha(_ color: Color) -> Double { painted(color).alpha }

// MARK: - Colour arithmetic, ported for the tests only

/// sRGB gamma → linear. The inverse of `gammaEncode` in `Theme.swift`.
private func linearize(_ v: Double) -> Double {
    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

/// WCAG relative luminance.
private func luminance(_ rgb: [Double]) -> Double {
    0.2126 * linearize(rgb[0]) + 0.7152 * linearize(rgb[1]) + 0.0722 * linearize(rgb[2])
}

/// WCAG contrast ratio between two opaque sRGB colours.
private func contrastRatio(_ a: [Double], _ b: [Double]) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

/// A white wash composited over an opaque surface in gamma space, which is
/// what CoreAnimation does over an opaque sRGB layer (§3).
private func composite(white opacity: Double, over back: [Double]) -> [Double] {
    back.map { opacity * 1.0 + (1 - opacity) * $0 }
}

/// sRGB → OKLab. The forward direction of the matrices `Theme.swift` inverts.
private func oklab(_ rgb: [Double]) -> (l: Double, a: Double, b: Double) {
    let r = linearize(rgb[0]), g = linearize(rgb[1]), b = linearize(rgb[2])
    let lCbrt = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let mCbrt = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let sCbrt = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (
        l: 0.2104542553 * lCbrt + 0.7936177850 * mCbrt - 0.0040720468 * sCbrt,
        a: 1.9779984951 * lCbrt - 2.4285922050 * mCbrt + 0.4505937099 * sCbrt,
        b: 0.0259040371 * lCbrt + 0.7827717662 * mCbrt - 0.8086757660 * sCbrt
    )
}

/// Euclidean distance in OKLab — the honest measure between colours that
/// share a lightness, where a WCAG ratio reads ~1.00 and measures nothing.
private func deltaE(_ x: [Double], _ y: [Double]) -> Double {
    let (p, q) = (oklab(x), oklab(y))
    return sqrt(pow(p.l - q.l, 2) + pow(p.a - q.a, 2) + pow(p.b - q.b, 2))
}

// MARK: - Resolving a stored id (tests 8, 9, 13)

final class NoteSlotResolutionTests: XCTestCase {
    /// Test 8. An id this build has never heard of paints as `rose`, matching
    /// the desktop. A neutral grey was refused: one synced note showing two
    /// different colours across the two apps reads as the phone being broken
    /// (§3, and the cost is named in §10 limit 14).
    func testAnUnknownIdAndTheEmptyStringResolveToRose() {
        let rose = channels(NoteSlot.rose.color)
        XCTAssertEqual(channels(NoteSlot.color(for: "teal")), rose)
        XCTAssertEqual(channels(NoteSlot.color(for: "")), rose)
        XCTAssertEqual(channels(NoteSlot.color(for: "Rose")), rose, "the wire id is case-sensitive")
        XCTAssertEqual(channels(NoteSlot.color(for: "#d66f71")), rose, "the wire refuses hex")
    }

    /// Test 8, second half. The fallback is also the slot a new note starts
    /// on, so the two are one constant and cannot drift apart.
    func testTheFallbackIsRose() {
        XCTAssertEqual(NoteSlot.fallback, .rose)
    }

    /// Test 9. Each of the five wire ids round-trips to its OWN colour — the
    /// mapping is total and injective, so no two slots collide.
    func testEachIdRoundTripsToItsOwnColour() {
        for slot in NoteSlot.allCases {
            XCTAssertEqual(
                channels(NoteSlot.color(for: slot.rawValue)), channels(slot.color),
                "\(slot.rawValue) did not resolve to its own colour")
        }

        let painted = NoteSlot.allCases.map { channels($0.color) }
        for i in painted.indices {
            for j in painted.indices where j > i {
                XCTAssertNotEqual(
                    painted[i], painted[j],
                    "\(NoteSlot.allCases[i].rawValue) and \(NoteSlot.allCases[j].rawValue) paint the same")
            }
        }
    }

    /// Test 13. `allCases` IS the Note Editor's row order, and it is the
    /// wheel order the desktop uses. Reordering the cases reorders the sheet.
    func testAllCasesIsInWheelOrder() {
        XCTAssertEqual(
            NoteSlot.allCases.map(\.rawValue), ["rose", "amber", "green", "sky", "violet"])
    }
}

// MARK: - The palette holds up (tests 10, 11, 12)

final class NoteSlotPaletteTests: XCTestCase {
    /// The tone the palette is derived at (§3). Duplicated here deliberately:
    /// the shipping constants are file-private, and a test that imported them
    /// would agree with any value they were changed to.
    private let tone = (l: 0.660, c: 0.130)

    /// Test 10. GUARD: all five slots are inside sRGB at the shipping tone,
    /// with no channel clamps.
    ///
    /// The palette rests on one lightness and one chroma across all five, so
    /// no slot shouts louder. Above the gamut ceiling — 0.1346 at L 0.660,
    /// limited by `sky` — `gammaEncode`'s per-channel clamp drags the
    /// out-of-gamut slots back and breaks that premise INVISIBLY: at C 0.150
    /// `amber` paints C 0.1395 and `sky` paints L 0.6657 C 0.1411 while the
    /// recipe still reads one tone. Reading the painted colour back is the
    /// only way to see it.
    func testEverySlotReachesTheToneExactly() {
        for slot in NoteSlot.allCases {
            let rgb = channels(slot.color)
            let lab = oklab(rgb)
            let chroma = sqrt(lab.a * lab.a + lab.b * lab.b)

            // The painted tone must equal the SHIPPING tone. A clip shows up
            // here as a slot that lands short; a re-tune shows up as all five
            // landing somewhere else together, and that is a failure too —
            // moving the tone means re-deriving the ceiling and this test.
            XCTAssertEqual(
                lab.l, tone.l, accuracy: 0.002, "\(slot.rawValue) does not paint L \(tone.l)")
            XCTAssertEqual(
                chroma, tone.c, accuracy: 0.002, "\(slot.rawValue) does not paint C \(tone.c)")

            // A clamp lands a channel exactly on a rail. Catch it directly too.
            for (i, v) in rgb.enumerated() {
                XCTAssertGreaterThan(v, 0.0, "\(slot.rawValue) channel \(i) clamped to black")
                XCTAssertLessThan(v, 1.0, "\(slot.rawValue) channel \(i) clamped to white")
            }
        }
    }

    /// Test 11. Worst-of-five contrast clears 3:1 on every surface the marker
    /// actually paints on.
    ///
    /// The background is `Theme.surface` `#0d0d0d`, the REAL page colour of
    /// the Sessions list and the archived shelf — not `Theme.bg` `#060606`,
    /// which is the app root behind them. This test is also what pins §3's
    /// two derived wash numbers.
    func testWorstContrastClearsThreeToOneOnTheRealPage() {
        let page = channels(Theme.surface)
        // `UIColor` carries its components as `CGFloat`, so a read-back lands
        // within float precision of the constant rather than on it.
        for channel in page {
            XCTAssertEqual(channel, 13.0 / 255, accuracy: 1e-6, "the page is #0d0d0d")
        }

        let pressed = composite(white: alpha(Theme.elementHover), over: page)
        let selected = composite(white: alpha(Theme.elementActive), over: page)

        func worst(against back: [Double]) -> Double {
            NoteSlot.allCases.map { contrastRatio(channels($0.color), back) }.min() ?? 0
        }

        let onPage = worst(against: page)
        let onPressed = worst(against: pressed)
        let onSelected = worst(against: selected)

        XCTAssertGreaterThanOrEqual(onPage, 3.0)
        XCTAssertGreaterThanOrEqual(onPressed, 3.0)
        XCTAssertGreaterThanOrEqual(onSelected, 3.0)

        // §3's table. The two wash rows are marked `≈` there because they were
        // re-derived rather than measured, and §3 names THIS test as what pins
        // them — so the numbers here are the ones of record. The arithmetic is
        // deterministic, so all three pin at the same accuracy as test 12; a
        // looser tolerance on the washes would only paper over the 0.02 the
        // spec's estimate was out by. §3's rows are corrected to match.
        XCTAssertEqual(onPage, 5.88, accuracy: 0.01, "§3: worst on Theme.surface")
        XCTAssertEqual(onPressed, 5.18, accuracy: 0.01, "§3: worst on the pressed wash")
        XCTAssertEqual(onSelected, 4.62, accuracy: 0.01, "§3: worst on the selected wash")
    }

    /// Test 12. The closest pair stays far enough apart to be told from each
    /// other on a 3pt mark. `rose`/`amber` at ΔE 0.126 is the pair, the same
    /// one the desktop found, so the wheel order is confirmed not changed.
    func testTheClosestPairIsAtLeastPointOneTwoApart() {
        let painted = NoteSlot.allCases.map { channels($0.color) }
        var closest = Double.infinity
        for i in painted.indices {
            for j in painted.indices where j > i {
                closest = min(closest, deltaE(painted[i], painted[j]))
            }
        }
        XCTAssertGreaterThanOrEqual(closest, 0.12)
        XCTAssertEqual(closest, 0.126, accuracy: 0.002, "§3: rose/amber is the closest pair")
    }
}
