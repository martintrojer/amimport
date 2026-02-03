import XCTest
@testable import AMImport

final class CSVParserTests: XCTestCase {
    func test_parse_requiresTitleAndArtistColumns() {
        let csv = "title,album\nTrack,Album"

        XCTAssertThrowsError(try CSVImporter().parse(csv))
    }

    func test_parse_handlesQuotedCommas() throws {
        let csv = "title,artist\n\"One, Two\",Artist"

        let rows = try CSVImporter().parse(csv)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "One, Two")
        XCTAssertEqual(rows.first?.artist, "Artist")
    }

    func test_parse_handlesUTF8BOM() throws {
        let csv = "\u{feff}title,artist\nSong,Artist"

        let rows = try CSVImporter().parse(csv)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Song")
        XCTAssertEqual(rows.first?.artist, "Artist")
    }
}
