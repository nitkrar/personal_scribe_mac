import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.12 — `WorkflowModeDocument` is the on-disk schema for
/// `workflow-modes.json`. Tests pin schema-version round-trip, the
/// `activeModeID` default, and tolerant decoding of an absent
/// `customModes` field.
final class WorkflowModeDocumentTests: XCTestCase {

    func testDocumentRoundTripPreservesSchemaVersion() throws {
        let original = WorkflowModeDocument(
            schemaVersion: 1,
            activeModeID: "dictation",
            customModes: [RecipeWorkflowMode.dictation]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WorkflowModeDocument.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.activeModeID, "dictation")
        XCTAssertEqual(decoded.customModes.count, 1)
        XCTAssertEqual(decoded.customModes.first?.id, "dictation")
    }

    func testDocumentDefaultsActiveModeIDToNil() {
        let fresh = WorkflowModeDocument()

        XCTAssertEqual(
            fresh.schemaVersion,
            WorkflowModeDocument.currentSchemaVersion
        )
        XCTAssertNil(fresh.activeModeID)
        XCTAssertTrue(fresh.customModes.isEmpty)
    }

    func testDocumentDecodesEmptyCustomModesAsEmptyArray() throws {
        // Hand-rolled JSON without a `customModes` field — decoder
        // must surface an empty list, not throw.
        let json = """
        {
            "schemaVersion": 1,
            "activeModeID": null
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(
            WorkflowModeDocument.self,
            from: json
        )

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.activeModeID)
        XCTAssertTrue(decoded.customModes.isEmpty)
    }
}
