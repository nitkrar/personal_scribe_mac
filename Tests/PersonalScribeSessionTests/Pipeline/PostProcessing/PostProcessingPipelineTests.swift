import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class PostProcessingPipelineTests: XCTestCase {
    private let pipeline = DefaultPostProcessingPipeline()

    func testEmptyInputReturnsEmpty() async throws {
        let emptyOutput = try await pipeline.run("", context: makeContext())
        XCTAssertEqual(emptyOutput, "")
        let whitespaceOutput = try await pipeline.run("   \n  ", context: makeContext())
        XCTAssertEqual(whitespaceOutput, "")
    }

    func testRemovesCommonFillers() async throws {
        let output = try await pipeline.run("um hello uh world", context: makeContext())
        XCTAssertEqual(output, "Hello world.")
    }

    /// Phrases a regex can't tell from fillers stay; these sentences come from real dictations.
    func testKeepsWordsThatCanCarryMeaning() async throws {
        let sentences = [
            "This is what the image looks like.",
            "Sunset is also good and I like how I can change this.",
            "I feel like I wasted so much time.",
            "I guess it could be slightly more vertical.",
            "I mean the point is we can keep it string.",
            "So our tool sort of honors it.",
            "One of the apps does this kind of animation.",
            "Do you know what it does?",
        ]
        for sentence in sentences {
            let output = try await pipeline.run(sentence, context: makeContext())
            XCTAssertEqual(output, sentence)
        }
    }

    func testCleanupDisabledReturnsTranscriptUnchanged() async throws {
        let context = PostProcessingContext(recordingDuration: .seconds(1), cleanupEnabled: false)

        let output = try await pipeline.run("um hello uh world", context: context)

        XCTAssertEqual(output, "um hello uh world")
    }

    func testPreservesTerminalPunctuation() async throws {
        let output = try await pipeline.run("hello!", context: makeContext())
        XCTAssertEqual(output, "Hello!")
    }

    func testAddsMissingPeriod() async throws {
        let output = try await pipeline.run("hello", context: makeContext())
        XCTAssertEqual(output, "Hello.")
    }

    func testCollapsesInternalWhitespace() async throws {
        let output = try await pipeline.run("hello    world", context: makeContext())
        XCTAssertEqual(output, "Hello world.")
    }

    func testPreservesLineBreaksBetweenDiarizedTurns() async throws {
        let output = try await pipeline.run(
            "Speaker 1: alpha\n\nSpeaker 2: beta",
            context: makeContext()
        )

        XCTAssertEqual(output, "Speaker 1: alpha.\n\nSpeaker 2: beta.")
    }

    func testIsDeterministic() async throws {
        let input = "um hello uh world"
        let first = try await pipeline.run(input, context: makeContext())
        let second = try await pipeline.run(input, context: makeContext())
        XCTAssertEqual(first, second)
    }

    func testDoesNotCorruptProperNouns() async throws {
        let output = try await pipeline.run("my name is Matthew", context: makeContext())
        XCTAssertEqual(output, "My name is Matthew.")
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
        // #078.31a: activeMode field now carries the new `WorkflowMode`
        // shape. The legacy aiModelID + systemPrompt remain as
        // separate context fields.
        return PostProcessingContext(
            recordingDuration: .seconds(1),
            activeMode: WorkflowMode.dictation,
            activeAIModelID: "gpt-5.4",
            systemPrompt: "Polish the final transcript.",
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
