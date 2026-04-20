import XCTest
@testable import PersonalScribeCore

final class PersonalScribeLoggerTests: XCTestCase {
    func testLoggerFacadeCompilesAndUsesSharedSubsystem() {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.audio)

        XCTAssertEqual(PersonalScribeLogger.subsystem, "com.nitkrar.seshat")
        XCTAssertEqual(PersonalScribeLogCategory.audio, "audio")
        XCTAssertFalse(Mirror(reflecting: logger).children.isEmpty)

        logger.debug("debug")
        logger.info("info")
        logger.error("error", error: PersonalScribeError.audioEngineFailure)
    }
}
