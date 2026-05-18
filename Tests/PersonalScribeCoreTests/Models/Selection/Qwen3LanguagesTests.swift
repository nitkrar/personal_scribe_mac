import XCTest
@testable import PersonalScribeCore

final class Qwen3LanguagesTests: XCTestCase {
    func testCodesAreSortedUniqueAndLookLikeLanguageTags() {
        let codes = Qwen3Languages.codes

        XCTAssertFalse(codes.isEmpty)
        XCTAssertEqual(codes, codes.sorted())
        XCTAssertEqual(Set(codes).count, codes.count)

        let pattern = "^[a-z]{2,3}(?:-[A-Z]{2,4})?$"
        for code in codes {
            XCTAssertNotNil(
                code.range(of: pattern, options: .regularExpression),
                "\(code) should look like a BCP-47 language tag"
            )
        }
    }

    func testCodesContainExpectedMultilingualBasics() {
        XCTAssertTrue(
            Set(Qwen3Languages.codes).isSuperset(of: ["en", "ja", "zh", "yue"])
        )
    }
}
