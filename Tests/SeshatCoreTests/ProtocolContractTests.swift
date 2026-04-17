import XCTest
@testable import SeshatCore

private struct StubPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool { true }
}

private actor StubAudioCapturing: AudioCapturing {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor StubTranscribing: Transcribing {
    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(.init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil))
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", audioDuration: .zero, processingDuration: .zero)
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", audioDuration: .zero, processingDuration: .zero)
    }
}

final class ProtocolContractTests: XCTestCase {
    func testSharedProtocolsAcceptTrivialConformers() async throws {
        let permission = StubPermissionRequester()
        let capture = StubAudioCapturing()
        let transcriber = StubTranscribing()

        let accessGranted = await permission.requestAccess()
        XCTAssertTrue(accessGranted)
        _ = try await capture.start()
        try await transcriber.prepare()
        _ = transcriber.modelDownloadProgress()
    }
}
