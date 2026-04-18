import XCTest
@testable import SeshatTranscription

final class ModelDownloadTests: XCTestCase {
    func testDownloaderUsesPinnedRevision() {
        let urls = ParakeetArtifact.requiredRelativePaths.map(ParakeetArtifact.resolveURL(for:))

        XCTAssertFalse(urls.isEmpty)

        for url in urls {
            XCTAssertTrue(url.absoluteString.contains("/resolve/\(ParakeetArtifact.modelRevision)/"))
            XCTAssertFalse(url.absoluteString.contains("/resolve/main/"))
        }
    }
}
