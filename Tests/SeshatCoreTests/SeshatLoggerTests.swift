import XCTest
@testable import SeshatCore

final class SeshatLoggerTests: XCTestCase {
    func testLoggerFacadeCompilesAndUsesSharedSubsystem() {
        let logger = SeshatLogger(category: SeshatLogCategory.audio)

        XCTAssertEqual(SeshatLogger.subsystem, "com.nitkrar.seshat")
        XCTAssertEqual(SeshatLogCategory.audio, "audio")
        XCTAssertFalse(Mirror(reflecting: logger).children.isEmpty)

        logger.debug("debug")
        logger.info("info")
        logger.error("error", error: SeshatError.audioEngineFailure)
    }
}
