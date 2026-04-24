import XCTest
@testable import PersonalScribeAudio

final class SystemAudioMuterTests: XCTestCase {
    func testMuteFromUnmutedReadsPriorThenWritesTrue() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { recorder.record(.read); return false },
            write: { recorder.record(.write($0)) }
        )

        muter.muteIfNeeded()

        XCTAssertEqual(recorder.calls, [.read, .write(true)])
    }

    func testMuteFromAlreadyMutedReadsPriorThenWritesTrue() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { recorder.record(.read); return true },
            write: { recorder.record(.write($0)) }
        )

        muter.muteIfNeeded()

        XCTAssertEqual(recorder.calls, [.read, .write(true)])
    }

    func testRestoreAfterMuteFromUnmutedWritesFalse() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { false },
            write: { recorder.record(.write($0)) }
        )

        muter.muteIfNeeded()
        muter.restoreIfNeeded()

        XCTAssertEqual(recorder.calls, [.write(true), .write(false)])
    }

    func testRestoreAfterMuteFromAlreadyMutedWritesTrue() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { true },
            write: { recorder.record(.write($0)) }
        )

        muter.muteIfNeeded()
        muter.restoreIfNeeded()

        XCTAssertEqual(recorder.calls, [.write(true), .write(true)])
    }

    func testRestoreWithoutMuteIsNoOp() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { recorder.record(.read); return false },
            write: { recorder.record(.write($0)) }
        )

        muter.restoreIfNeeded()

        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testMuteReadFailureSkipsWriteAndLeavesLatchEmpty() {
        let recorder = MuterCallRecorder()
        var muter = SystemAudioMuter(
            read: { recorder.record(.read); return nil },
            write: { recorder.record(.write($0)) }
        )

        muter.muteIfNeeded()
        muter.restoreIfNeeded()

        XCTAssertEqual(recorder.calls, [.read])
    }
}

final class MuterCallRecorder: @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case read
        case write(Bool)
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    var calls: [Call] {
        lock.withLock { storage }
    }

    func record(_ call: Call) {
        lock.withLock { storage.append(call) }
    }
}
