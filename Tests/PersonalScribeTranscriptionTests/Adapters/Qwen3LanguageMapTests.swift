import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class Qwen3LanguageMapTests: XCTestCase {
    func testAllMapKeysAreAdvertisedQwen3Languages() {
        XCTAssertTrue(
            Set(Qwen3LanguageMap.bcp47ToQwen.keys).isSubset(of: Set(Qwen3Languages.codes))
        )
    }

    func testEveryAdvertisedQwen3LanguageHasMatchingMapEntry() throws {
        XCTAssertEqual(Set(Qwen3LanguageMap.bcp47ToQwen.keys), Set(Qwen3Languages.codes))

        for code in Qwen3Languages.codes {
            let mapped = try XCTUnwrap(Qwen3LanguageMap.bcp47ToQwen[code])
            XCTAssertEqual(mapped.rawValue, code)
        }
    }
}
