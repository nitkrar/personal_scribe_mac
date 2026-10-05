import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// Paste rule shared by batch paste and live cursor output: Cmd+V goes to
/// another app, or to Ninimma when one of its own text inputs has focus.
final class PasteTargetTests: XCTestCase {
    private let selfBundle = "com.nitkrar.personal_scribe"

    func testPastesIntoAnyOtherFrontmostApp() {
        // Includes Electron apps like Slack, whose AX focus isn't readable —
        // the rule doesn't depend on AX.
        let target = PasteTarget.frontmost(bundleID: "com.tinyspeck.slackmacgap", pid: 42)
        XCTAssertTrue(target.permitsPaste(selfBundleID: selfBundle))
    }

    func testDoesNotPasteWhenNinimmaIsFrontmost() {
        let target = PasteTarget.frontmost(bundleID: selfBundle, pid: 7)
        XCTAssertFalse(target.permitsPaste(selfBundleID: selfBundle))
    }

    @MainActor
    func testLiveFocusCheckAcceptsEditableTextViewAndRejectsReadOnlyTextView() {
        let window = NSWindow()
        let textView = NSTextView()
        window.contentView = textView

        textView.isEditable = true
        window.makeFirstResponder(textView)
        XCTAssertTrue(PasteTarget.hasEditableTextInputFocus(in: window))

        textView.isEditable = false
        XCTAssertFalse(PasteTarget.hasEditableTextInputFocus(in: window))
    }

    @MainActor
    func testLiveFocusCheckUsesFieldEditorEditabilityAndRejectsSecureField() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        window.contentView?.addSubview(field)
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(PasteTarget.hasEditableTextInputFocus(in: window))

        field.isEditable = false
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertFalse(PasteTarget.hasEditableTextInputFocus(in: window))

        let secure = NSSecureTextField(frame: field.frame)
        window.contentView?.replaceSubview(field, with: secure)
        XCTAssertTrue(window.makeFirstResponder(secure))
        XCTAssertFalse(PasteTarget.hasEditableTextInputFocus(in: window))
    }

    func testResolveFindsOwnFocusedTextInputInProcess() {
        XCTAssertEqual(
            PasteTarget.resolve(
                frontmostBundleID: selfBundle,
                frontmostPID: 7,
                currentPID: 7,
                hasOwnTextInputFocus: true
            ),
            .ownTextInput
        )
    }

    func testResolveKeepsNinimmaBlockedWithoutFocusedTextInput() {
        XCTAssertEqual(
            PasteTarget.resolve(
                frontmostBundleID: selfBundle,
                frontmostPID: 7,
                currentPID: 7,
                hasOwnTextInputFocus: false
            ),
            .frontmost(bundleID: selfBundle, pid: 7)
        )
    }

    func testDoesNotPasteWithNoFrontmostApp() {
        XCTAssertFalse(PasteTarget.noFrontmostApp.permitsPaste(selfBundleID: selfBundle))
    }

    func testLogDescriptionNamesTheFrontmostApp() {
        XCTAssertEqual(
            PasteTarget.frontmost(bundleID: "com.tinyspeck.slackmacgap", pid: 42).logDescription,
            "frontmost=com.tinyspeck.slackmacgap pid=42"
        )
        XCTAssertEqual(PasteTarget.ownTextInput.logDescription, "frontmost=self target=text-input")
        XCTAssertEqual(PasteTarget.noFrontmostApp.logDescription, "frontmost=none")
    }
}
