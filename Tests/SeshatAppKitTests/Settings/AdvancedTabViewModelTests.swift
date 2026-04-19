import Foundation
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class AdvancedTabViewModelTests: XCTestCase {
    func testChangeBaseDirectory_reportsMovedSubdirsOnSuccess() async {
        let currentBase = URL(fileURLWithPath: "/tmp/current-base", isDirectory: true).standardizedFileURL
        let selectedBase = URL(fileURLWithPath: "/tmp/next-base", isDirectory: true).standardizedFileURL
        let migrator = FakeBaseDirectoryMigrator(
            outcome: .success(.migrated(movedSubdirs: ["models", "recordings"], totalBytes: 2_048))
        )
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(currentBase),
            migrator: migrator,
            selectDirectory: { currentDirectory in
                XCTAssertEqual(currentDirectory, currentBase)
                return selectedBase
            }
        )

        await viewModel.changeBaseDirectory()

        XCTAssertFalse(viewModel.isMigrating)
        XCTAssertEqual(try? viewModel.baseDirectoryResult.get(), selectedBase)

        guard case .success(let message)? = viewModel.feedback else {
            return XCTFail("Expected a success message after migration.")
        }
        XCTAssertTrue(message.contains("models"))
        XCTAssertTrue(message.contains("recordings"))
        XCTAssertEqual(await migrator.recordedDestinations(), [selectedBase])
    }

    func testChangeBaseDirectory_reportsErrorMessageOnFailure() async {
        let currentBase = URL(fileURLWithPath: "/tmp/current-base", isDirectory: true).standardizedFileURL
        let selectedBase = URL(fileURLWithPath: "/tmp/next-base", isDirectory: true).standardizedFileURL
        let migrator = FakeBaseDirectoryMigrator(
            outcome: .failure(StubMigrationError(message: "Existing recordings folder blocked the move."))
        )
        let viewModel = AdvancedTabViewModel(
            baseDirectoryResult: .success(currentBase),
            migrator: migrator,
            selectDirectory: { _ in selectedBase }
        )

        await viewModel.changeBaseDirectory()

        XCTAssertFalse(viewModel.isMigrating)
        XCTAssertEqual(try? viewModel.baseDirectoryResult.get(), currentBase)

        guard case .failure(let message)? = viewModel.feedback else {
            return XCTFail("Expected a failure message after migration fails.")
        }
        XCTAssertEqual(message, "Existing recordings folder blocked the move.")
        XCTAssertEqual(await migrator.recordedDestinations(), [selectedBase])
    }
}

private actor FakeBaseDirectoryMigrator: BaseDirectoryMigrating {
    enum Outcome: Sendable {
        case success(MigrationReport)
        case failure(StubMigrationError)
    }

    private let outcome: Outcome
    private var destinations: [URL] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func migrate(to newBase: URL) async throws -> MigrationReport {
        destinations.append(newBase.standardizedFileURL)

        switch outcome {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        }
    }

    func recordedDestinations() -> [URL] {
        destinations
    }
}

private struct StubMigrationError: LocalizedError, Sendable, Equatable {
    let message: String

    var errorDescription: String? {
        message
    }
}
