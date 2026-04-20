import XCTest
@testable import PersonalScribeAppKit

final class PersonalScribeAppKitPermissionsCompileTests: XCTestCase {
    func testPermissionsModuleCompiles() {
        _ = PersonalScribeAppKitPermissionsModule.self
        XCTAssertTrue(true)
    }
}
