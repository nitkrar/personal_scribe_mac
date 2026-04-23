import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for the quill `PersonalScribeLogoView`.
///
/// The 2026-04-18 redesign replaced the stylised hand-coded
/// `QuillShape` with an SVG-traced version (vtracer spline trace of
/// the master logo asset at 2048×2048). Public API simplified from
/// `(size:state:tint:)` to `(color:)` — animation states and
/// `Geometry` helpers are gone because the pill overlay no longer
/// drives them (the pill uses `SineWaveView` + `ProgressView` for
/// motion).
@MainActor
final class PersonalScribeLogoViewTests: XCTestCase {
    func testDefaultColorIsChampagneFromDarkPalette() {
        let view = PersonalScribeLogoView()
        XCTAssertEqual(view.color, PersonalScribeTheme.Palette.dark.brandChampagne)
    }

    func testQuillShapeProducesNonEmptyPath() {
        // Rendering into a 100×100 rect — the SVG-parsed path should
        // produce a visible path. Empty would mean the parser failed
        // silently or the embedded path data is malformed.
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = QuillShape().path(in: rect)
        XCTAssertFalse(path.isEmpty, "QuillShape must produce a non-empty path")
    }

    func testQuillShapeFitsRoughlyWithinProvidedRect() {
        // Scaling from the 2048×2048 source should keep the path's
        // bounding box within the target rect (±small tolerance for
        // curve control points + anti-alias overspray).
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        let path = QuillShape().path(in: rect)
        let bounds = path.boundingRect
        let tolerance: CGFloat = 4
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - tolerance)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + tolerance)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - tolerance)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + tolerance)
    }
}
