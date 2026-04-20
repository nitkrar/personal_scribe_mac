import XCTest
<<<<<<< Updated upstream
@testable import PersonalScribeCore

final class PersonalScribeLoggerTests: XCTestCase {
    func testLoggerFacadeCompilesAndUsesSharedSubsystem() {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.audio)

        XCTAssertEqual(PersonalScribeLogger.subsystem, "com.nitkrar.seshat")
        XCTAssertEqual(PersonalScribeLogCategory.audio, "audio")
=======
@testable import PersonalScribeCore

final class PersonalScribeLoggerTests: XCTestCase {
    func testLoggerFacadeCompilesAndUsesSharedSubsystem() {
        let logger = PersonalScribeLogger(category: PersonalScribeLogCategory.audio)

        XCTAssertEqual(PersonalScribeLogger.subsystem, "com.nitkrar.seshat")
        XCTAssertEqual(PersonalScribeLogCategory.audio, "audio")
>>>>>>> Stashed changes
        XCTAssertFalse(Mirror(reflecting: logger).children.isEmpty)

        logger.debug("debug")
        logger.info("info")
<<<<<<< Updated upstream
        logger.error("error", error: PersonalScribeError.audioEngineFailure)
=======
        logger.error("error", error: PersonalScribeError.audioEngineFailure)
>>>>>>> Stashed changes
    }
}
