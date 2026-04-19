import XCTest
import SeshatCore
@testable import SeshatSession

final class PostProcessingPipelineTests: XCTestCase {
    private let pipeline = DefaultPostProcessingPipeline()

    func testEmptyInputReturnsEmpty() async throws {
        XCTAssertEqual(try await pipeline.run("", context: makeContext()), "")
        XCTAssertEqual(try await pipeline.run("   \n  ", context: makeContext()), "")
    }

    func testRemovesCommonFillers() async throws {
        XCTAssertEqual(
            try await pipeline.run("um hello uh world", context: makeContext()),
            "Hello world."
        )
    }

    func testRemovesHedges() async throws {
        XCTAssertEqual(
            try await pipeline.run("you know i think sort of it works", context: makeContext()),
            "I think it works."
        )
    }

    func testPreservesTerminalPunctuation() async throws {
        XCTAssertEqual(
            try await pipeline.run("hello!", context: makeContext()),
            "Hello!"
        )
    }

    func testAddsMissingPeriod() async throws {
        XCTAssertEqual(
            try await pipeline.run("hello", context: makeContext()),
            "Hello."
        )
    }

    func testCollapsesInternalWhitespace() async throws {
        XCTAssertEqual(
            try await pipeline.run("hello    world", context: makeContext()),
            "Hello world."
        )
    }

    func testIsDeterministic() async throws {
        let input = "um hello uh world"

        XCTAssertEqual(
            try await pipeline.run(input, context: makeContext()),
            try await pipeline.run(input, context: makeContext())
        )
    }

    func testDoesNotCorruptProperNouns() async throws {
        XCTAssertEqual(
            try await pipeline.run("my name is Matthew", context: makeContext()),
            "My name is Matthew."
        )
    }

    func testPipelinePassesContextThroughCustomStages() async throws {
        let stage = ContextRecordingStage()
        let expectedContext = makeContext()
        let pipeline = DefaultPostProcessingPipeline(stages: [stage])

        let output = try await pipeline.run("hello", context: expectedContext)
        let recordedContext = await stage.recordedContext()

        XCTAssertEqual(output, "hello")
        XCTAssertEqual(recordedContext, expectedContext)
    }

    private func makeContext() -> PostProcessingContext {
        let mode = ModeDescriptor(
            id: "dictation-plus",
            name: "Dictation Plus",
            voiceModelID: "voice.default",
            aiModelID: "gpt-5.4",
            systemPrompt: "Polish the final transcript."
        )
        return PostProcessingContext(
            recordingDuration: .seconds(1),
            activeMode: mode,
            activeAIModelID: mode.aiModelID,
            systemPrompt: mode.systemPrompt,
            segments: [
                .init(text: "hello world", start: .zero, end: .seconds(1)),
            ],
            asrConfidence: 0.92
        )
    }
}

private actor ContextRecordingStage: PostProcessingStage {
    nonisolated let name = "context-recording"
    private var lastContext: PostProcessingContext?

    func apply(_ text: String, context: PostProcessingContext) async throws -> String {
        lastContext = context
        return text
    }

    func recordedContext() -> PostProcessingContext? {
        lastContext
    }
}
