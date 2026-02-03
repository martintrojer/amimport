import XCTest
@testable import AMImport

final class MusicKitClientTests: XCTestCase {
    func test_searchLibrary_emptyTitle_returnsEmpty() async throws {
        let client = FakeMusicCatalogSearcher()
        let songs = try await client.searchLibrary(title: "", artist: "", album: nil, limit: 5)
        XCTAssertTrue(songs.isEmpty)
    }

    func test_searchCatalog_emptyTitle_returnsEmpty() async throws {
        let client = FakeMusicCatalogSearcher()
        let songs = try await client.searchCatalog(title: "", artist: "", album: nil, limit: 5)
        XCTAssertTrue(songs.isEmpty)
    }
}

private struct FakeMusicCatalogSearcher: MusicCatalogSearching {
    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return [] }
        return [
            ResolvedSong(
                catalogSongID: nil,
                librarySongID: "lib-1",
                title: normalizedTitle,
                artist: artist,
                album: album,
                artworkURL: nil,
                durationSeconds: nil
            )
        ]
    }

    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return [] }
        return [
            ResolvedSong(
                catalogSongID: "cat-1",
                librarySongID: nil,
                title: normalizedTitle,
                artist: artist,
                album: album,
                artworkURL: nil,
                durationSeconds: nil
            )
        ]
    }
}
