import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `ModeCard` — Settings Modes-tab composite showing voice
/// + AI model preset with an active/inactive status pill.
@MainActor
final class ModeCardTests: XCTestCase {
    // MARK: - Initializer / stored state

    func testInitializerStoresAllFields() {
        let card = ModeCard(
            modeName: "Dictation",
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Fast rewrite",
            isActive: true
        )
        XCTAssertEqual(card.modeName, "Dictation")
        XCTAssertEqual(card.voiceModel, "Parakeet-TDT")
        XCTAssertEqual(card.aiModelPreset, "Fast rewrite")
        XCTAssertTrue(card.isActive)
    }

    func testDefaultIsInactive() {
        let card = ModeCard(
            modeName: "Dictation",
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Fast rewrite"
        )
        XCTAssertFalse(card.isActive)
    }

    // MARK: - Subtitle formatting

    func testSubtitleCombinesVoiceAndAiWithMiddleDot() {
        let subtitle = ModeCard.Formatters.subtitle(
            voiceModel: "Parakeet-TDT",
            aiModelPreset: "Fast rewrite"
        )
        XCTAssertEqual(subtitle, "Voice: Parakeet-TDT \u{00B7} AI: Fast rewrite")
    }

    func testSubtitleSubstitutesEmDashForEmptyVoice() {
        let subtitle = ModeCard.Formatters.subtitle(
            voiceModel: "",
            aiModelPreset: "Fast rewrite"
        )
        XCTAssertEqual(subtitle, "Voice: \u{2014} \u{00B7} AI: Fast rewrite")
    }

    func testSubtitleSubstitutesEmDashForEmptyAi() {
        let subtitle = ModeCard.Formatters.subtitle(
            voiceModel: "Parakeet-TDT",
            aiModelPreset: ""
        )
        XCTAssertEqual(subtitle, "Voice: Parakeet-TDT \u{00B7} AI: \u{2014}")
    }

    func testSubtitlePropertyReflectsFormatters() {
        let card = ModeCard(
            modeName: "M",
            voiceModel: "V",
            aiModelPreset: "P"
        )
        XCTAssertEqual(card.subtitle, "Voice: V \u{00B7} AI: P")
    }

    // MARK: - StatusPill mapping

    func testActiveMapsToReadyStatusWithActiveLabel() {
        let card = ModeCard(
            modeName: "M",
            voiceModel: "V",
            aiModelPreset: "P",
            isActive: true
        )
        XCTAssertEqual(card.statusPillStatus, .ready)
        XCTAssertEqual(card.statusPillLabel, "Active")
    }

    func testInactiveMapsToNeutralStatusWithInactiveLabel() {
        let card = ModeCard(
            modeName: "M",
            voiceModel: "V",
            aiModelPreset: "P",
            isActive: false
        )
        XCTAssertEqual(card.statusPillStatus, .neutral)
        XCTAssertEqual(card.statusPillLabel, "Inactive")
    }
}
