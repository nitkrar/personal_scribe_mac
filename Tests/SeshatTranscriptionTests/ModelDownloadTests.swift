import XCTest
import SeshatCore
@testable import SeshatTranscription

final class ModelDownloadTests: XCTestCase {
    func testDownloaderUsesPinnedRevision() {
        let descriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let urls = descriptor.requiredRelativePaths.map(descriptor.resolveURL(for:))

        XCTAssertFalse(urls.isEmpty)

        for url in urls {
            XCTAssertTrue(url.absoluteString.contains("/resolve/\(descriptor.revision)/"))
            XCTAssertFalse(url.absoluteString.contains("/resolve/main/"))
        }
    }
}
