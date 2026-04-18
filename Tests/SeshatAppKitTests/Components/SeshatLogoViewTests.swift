import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for the quill `SeshatLogoView`.
///
/// The view itself is pure SwiftUI geometry; we test:
///   * The `AnimationState` enum rounds out all four states.
///   * The view's public initializer accepts size + state + tint.
///   * Default tint for dark / light palettes matches the theme's
///     `brandChampagne` token.
///   * `ImageProvider` pre-computes deterministic geometry that the view
///     renders (so we can test geometry without XCTest'ing SwiftUI).
final class SeshatLogoViewTests: XCTestCase {
    func testAnimationStateEnumHasAllFourCases() {
        let cases: Set<SeshatLogoView.AnimationState> = Set(SeshatLogoView.AnimationState.allCases)
        XCTAssertEqual(
            cases,
            [.idle, .listening, .transcribing, .error],
            "AnimationState must cover all four states from logo_animation_states.png"
        )
    }

    func testInitializerAcceptsSizeAndState() {
        let view = SeshatLogoView(size: 64, state: .listening)
        XCTAssertEqual(view.size, 64, accuracy: 0.001)
        XCTAssertEqual(view.state, .listening)
    }

    func testInitializerDefaultsToIdleState() {
        let view = SeshatLogoView(size: 48)
        XCTAssertEqual(view.state, .idle)
    }

    func testExplicitTintOverridesDefaultBrandChampagne() {
        let customTint = Color.red
        let view = SeshatLogoView(size: 48, state: .idle, tint: customTint)
        XCTAssertNotNil(view.explicitTint)
    }

    func testDefaultTintIsNilWhenNotSpecified() {
        let view = SeshatLogoView(size: 48, state: .idle)
        XCTAssertNil(view.explicitTint, "when tint is nil, view resolves from theme palette")
    }

    func testGeometryStrokeWidthScalesWithSize() {
        let small = SeshatLogoView.Geometry(size: 24)
        let large = SeshatLogoView.Geometry(size: 96)
        XCTAssertLessThan(small.strokeWidth, large.strokeWidth)
        XCTAssertGreaterThan(small.strokeWidth, 0)
    }

    func testGeometryInkDripOnlyVisibleInTranscribingState() {
        XCTAssertFalse(SeshatLogoView.Geometry.showsInkDrip(for: .idle))
        XCTAssertFalse(SeshatLogoView.Geometry.showsInkDrip(for: .listening))
        XCTAssertTrue(SeshatLogoView.Geometry.showsInkDrip(for: .transcribing))
        XCTAssertFalse(SeshatLogoView.Geometry.showsInkDrip(for: .error))
    }

    func testGeometryWaveformVisibleForIdleAndListeningAndTranscribing() {
        XCTAssertTrue(SeshatLogoView.Geometry.showsWaveform(for: .idle))
        XCTAssertTrue(SeshatLogoView.Geometry.showsWaveform(for: .listening))
        XCTAssertTrue(SeshatLogoView.Geometry.showsWaveform(for: .transcribing))
        XCTAssertFalse(SeshatLogoView.Geometry.showsWaveform(for: .error))
    }

    func testGeometryStateAnimationSpeedDiffersAcrossStates() {
        // Listening should animate faster than idle; transcribing goes flat.
        let idle = SeshatLogoView.Geometry.animationSpeed(for: .idle)
        let listening = SeshatLogoView.Geometry.animationSpeed(for: .listening)
        let transcribing = SeshatLogoView.Geometry.animationSpeed(for: .transcribing)
        XCTAssertGreaterThan(listening, idle)
        XCTAssertEqual(transcribing, 0, "transcribing = flat wave, no animation")
    }
}
