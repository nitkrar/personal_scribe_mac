import FluidAudio
import PersonalScribeCore
import XCTest
@testable import PersonalScribeTranscription

final class FluidAudioOfflineDiarizerAdapterTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testAdapterLoadsModelAndExtractsBasicResultUsingStubManager() async throws {
        let storageLocator = AppConfig.liveStorageLocator()
        let manager = StubOfflineDiarizerManager(
            result: DiarizationResult(
                segments: [
                    TimedSpeakerSegment(
                        speakerId: "speaker_0",
                        embedding: [],
                        startTimeSeconds: 0,
                        endTimeSeconds: 1.25,
                        qualityScore: 0.9
                    ),
                    TimedSpeakerSegment(
                        speakerId: "speaker_1",
                        embedding: [],
                        startTimeSeconds: 1.25,
                        endTimeSeconds: 2.0,
                        qualityScore: 0.8
                    ),
                ]
            )
        )
        let adapter = FluidAudioOfflineDiarizerAdapter(
            descriptor: BuiltInModelCatalog.speakerDiarization,
            storageLocator: storageLocator,
            manager: manager
        )
        let buffer = try PCMBuffer(
            samples: [0.1, 0.2, 0.3, 0.4],
            timestamp: ContinuousClock().now
        )

        let events = await collectEvents(from: adapter.diarize(buffer))

        XCTAssertEqual(
            events,
            [
                .terminal([
                    SpeakerTurn(
                        speakerID: "speaker_0",
                        start: .seconds(0),
                        end: .seconds(1.25)
                    ),
                    SpeakerTurn(
                        speakerID: "speaker_1",
                        start: .seconds(1.25),
                        end: .seconds(2.0)
                    ),
                ])
            ]
        )

        let preparedDirectories = await manager.preparedDirectories
        XCTAssertEqual(
            preparedDirectories,
            [storageLocator.url(for: .models).standardizedFileURL]
        )

        let processedAudio = await manager.processedAudio
        XCTAssertEqual(processedAudio, [[0.1, 0.2, 0.3, 0.4]])
    }

    private func collectEvents(
        from stream: AsyncStream<SpeakerDiarizationEvent>
    ) async -> [SpeakerDiarizationEvent] {
        var events: [SpeakerDiarizationEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }
}

private actor StubOfflineDiarizerManager: FluidAudioOfflineDiarizerManaging {
    private(set) var preparedDirectories: [URL?] = []
    private(set) var processedAudio: [[Float]] = []

    private let result: DiarizationResult

    init(result: DiarizationResult) {
        self.result = result
    }

    func prepareModels(directory: URL?) async throws {
        preparedDirectories.append(directory?.standardizedFileURL)
    }

    func process(audio: [Float]) async throws -> DiarizationResult {
        processedAudio.append(audio)
        return result
    }
}
