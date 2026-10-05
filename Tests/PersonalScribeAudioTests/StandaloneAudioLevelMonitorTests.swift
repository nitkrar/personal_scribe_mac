import AVFoundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

final class StandaloneAudioLevelMonitorTests: XCTestCase {
    func testStartEmitsNormalizedLevelsAndStopTearsDownEngine() async throws {
        let box = ThreadSafeEngineBox()
        let monitor = StandaloneAudioLevelMonitor(
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 44_100, channels: 1, box: box),
            inputDeviceProvider: NoOpAudioInputDeviceProvider()
        )
        let stream = try await monitor.start()
        let level = expectation(description: "level emitted")
        let reader = Task {
            for await value in stream {
                XCTAssertEqual(value, 0.5, accuracy: 0.001)
                level.fulfill()
                return
            }
        }

        box.emit(
            AudioTestSupport.makeFloatBuffer(
                sampleRate: 44_100,
                channels: 1,
                frames: 4_096,
                fill: { _, _ in 0.5 }
            )
        )
        await fulfillment(of: [level], timeout: 1)
        await monitor.stop()
        _ = await reader.result

        XCTAssertEqual(box.installCount, 1)
        XCTAssertEqual(box.startCount, 1)
        XCTAssertEqual(box.removeCount, 1)
        XCTAssertEqual(box.stopCount, 1)
        XCTAssertEqual(box.resetCount, 1)
    }
}
