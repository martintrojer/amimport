import XCTest
@testable import AMImport

final class TrackNormalizerTests: XCTestCase {
    func test_normalize_stripsPunctuationAndLowercases() {
        XCTAssertEqual(TrackNormalizer.normalize("Hello!!!"), "hello")
    }

    func test_normalize_collapsesWhitespace() {
        XCTAssertEqual(TrackNormalizer.normalize("  The   Song   Name  "), "the song name")
    }

    func test_normalize_removesFeatSuffix() {
        XCTAssertEqual(TrackNormalizer.normalize("HELLO (feat. X)"), "hello")
    }
}
