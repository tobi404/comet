// The five Colour Slots a Chat Note can carry — spec §3.
//
// **The tone is L 0.660, C 0.130**: the desktop's lightness, at the largest
// chroma every hue can actually reach in sRGB. The lightness holds because a
// near-black page already clears 3:1 with room; what the darker page buys is
// headroom to separate the five harder, so the chroma rises from the desktop's
// 0.112 and lifts the closest pair from ΔE 0.109 to 0.126. Separation is the
// number that matters on a 3pt mark; contrast is the number already won.

import SwiftUI

/// A Colour Slot a Chat Note can carry. The wire id is the raw value.
///
/// The MODEL keeps the slot id as a `String` (§1) so no parse can downgrade an
/// id a newer desktop wrote. This enum lives at the PAINT layer only: it turns
/// a stored id into a colour, and answers an id it has never heard of.
enum NoteSlot: String, CaseIterable {
    case rose, amber, green, sky, violet

    /// Private on purpose: a caller that could see a hue would be tempted to
    /// store one, and a stored hue cannot follow a re-tune.
    private var hue: Double {
        switch self {
        case .rose: 20
        case .amber: 78
        case .green: 152
        case .sky: 232
        case .violet: 302
        }
    }

    /// The slot a new note starts on, and the fallback for an unknown id.
    static let fallback: NoteSlot = .rose

    /// Resolved at paint time through the same `oklch()` helper every other
    /// colour in the app goes through. The reference hexes in §3 are reference
    /// only — a stored hex could not follow a re-tune, which is the same
    /// reason the wire refuses hex.
    var color: Color { oklch(noteSlotL, noteSlotC, hue) }

    /// The colour a STORED slot id paints. The only entry point a view uses.
    ///
    /// An id no case matches — and the empty string — paints as `rose`,
    /// matching the desktop. A neutral grey fallback was refused: it would
    /// make one synced note violet on the desktop and grey on the phone, and a
    /// user reads that as the phone being broken rather than as the phone
    /// being honest. Both apps wrong in the same direction is the cheaper
    /// failure. The cost is named in §10, limit 14.
    static func color(for id: String) -> Color {
        (NoteSlot(rawValue: id) ?? .fallback).color
    }
}

/// The tone the five are derived at. File-local on purpose: these are not
/// `Theme` paint constants because they are not a colour — they are the recipe
/// for five. `Theme`'s own rule keeps colours and layout numbers apart, and
/// this is neither.
private let noteSlotL = 0.660

/// **A ceiling decision, not a taste one.** At L 0.660 the largest chroma all
/// five hues can reach inside sRGB is 0.1346, and `sky` is what limits it.
/// Above that, `oklchToSrgb`'s per-channel clamp in `gammaEncode` silently
/// drags the out-of-gamut slots back — at C 0.150, `amber` paints C 0.1395 and
/// `sky` paints L 0.6657 C 0.1411 — which breaks the one-lightness,
/// one-chroma premise the palette rests on, and breaks it invisibly. Do not
/// raise this without re-deriving that ceiling. Test 10 is the guard.
private let noteSlotC = 0.130
