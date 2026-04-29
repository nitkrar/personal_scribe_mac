import XCTest
@testable import PersonalScribeAppKit

final class ModesListViewReorderTests: XCTestCase {
    func testPreviewMovesDraggedModeDownwardIntoHoveredSlot() {
        let ids = ["A", "B", "C", "D"]

        let preview = ModesListReorder.previewIDs(
            dragging: "B",
            over: "D",
            in: ids
        )

        XCTAssertEqual(preview, ["A", "C", "D", "B"])
    }

    func testPreviewMovesDraggedModeUpwardIntoHoveredSlot() {
        let ids = ["A", "B", "C", "D"]

        let preview = ModesListReorder.previewIDs(
            dragging: "D",
            over: "B",
            in: ids
        )

        XCTAssertEqual(preview, ["A", "D", "B", "C"])
    }

    func testCommitMoveReturnsSwiftUIMoveArgumentsForDownwardMove() {
        let original = ["A", "B", "C", "D"]
        let preview = ["A", "C", "D", "B"]

        let move = ModesListReorder.commitMove(
            dragging: "B",
            from: original,
            to: preview
        )

        XCTAssertEqual(move?.source, IndexSet(integer: 1))
        XCTAssertEqual(move?.destination, 4)
    }

    func testCommitMoveReturnsSwiftUIMoveArgumentsForUpwardMove() {
        let original = ["A", "B", "C", "D"]
        let preview = ["A", "D", "B", "C"]

        let move = ModesListReorder.commitMove(
            dragging: "D",
            from: original,
            to: preview
        )

        XCTAssertEqual(move?.source, IndexSet(integer: 3))
        XCTAssertEqual(move?.destination, 1)
    }

    func testCommitMoveReturnsNilWhenOrderDidNotChange() {
        let original = ["A", "B", "C"]

        let move = ModesListReorder.commitMove(
            dragging: "B",
            from: original,
            to: original
        )

        XCTAssertNil(move)
    }
}
