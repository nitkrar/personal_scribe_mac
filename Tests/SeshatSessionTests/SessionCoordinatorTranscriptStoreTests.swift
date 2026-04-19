import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorTranscriptStoreTests: XCTestCase {
    func testSuccessfulTranscriptionAppendsEntryToSQLiteStore() async throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: tempDirectory)
        let coordinator = try makeCoordinator(
            resultText: "hello",
            audioSeconds: 1.0,
            processingSeconds: 0.2,
            store: store
        )

        try await driveToggleCycle(on: coordinator)
        try await waitUntilStoreHasEntries(store, minimum: 1)

        let entries = await store.recent(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Hello.")
        XCTAssertEqual(entries.first?.audioDuration ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(entries.first?.processingDuration ?? 0, 0.2, accuracy: 0.01)
    }

    func testCoordinatorWithoutStoreRunsHappyPath() async throws {
        let coordinator = try makeCoordinator(
            resultText: "hello",
            audioSeconds: 1.0,
            processingSeconds: 0.2,
            store: nil
        )

        try await driveToggleCycle(on: coordinator)
        let lastResult = await coordinator.lastResult()

        XCTAssertEqual(lastResult?.text, "Hello.")
    }

    // MARK: - Helpers

    private func makeCoordinator(
        resultText: String,
        audioSeconds: Double,
        processingSeconds: Double,
        store: SQLiteTranscriptStore?
    ) throws -> SessionCoordinator {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturing(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: .init(
                text: resultText,
                audioDuration: .seconds(audioSeconds),
                processingDuration: .seconds(processingSeconds)
            )
        )

        return SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session),
            transcriptStore: store
        )
    }

    private func driveToggleCycle(on coordinator: SessionCoordinator) async throws {
        let stream = await coordinator.stateStream()
        let observed = Task { () -> [SessionState] in
            var states: [SessionState] = []
            for await state in stream.prefix(4) {
                states.append(state)
            }
            return states
        }

        await coordinator.toggle()
        await coordinator.toggle()
        _ = try await withTimeout(.seconds(1)) { await observed.value }
    }

    private func waitUntilStoreHasEntries(
        _ store: SQLiteTranscriptStore,
        minimum: Int
    ) async throws {
        for _ in 0..<100 {
            let count = await store.count()
            if count >= minimum {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("SQLiteTranscriptStore never reached \(minimum) entries")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private struct TimeoutError: Error {}
}
