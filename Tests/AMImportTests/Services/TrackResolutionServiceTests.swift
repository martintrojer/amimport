import XCTest
@testable import AMImport

final class TrackResolutionServiceTests: XCTestCase {
    @MainActor
    func test_resolver_usesCatalogFallbackWhenLibraryMisses() async throws {
        let resolver = TrackResolutionService(
            searcher: StubSearcher(
                library: [],
                catalog: [
                    ResolvedSong(
                        catalogSongID: "cat-1",
                        librarySongID: nil,
                        title: "Song",
                        artist: "Artist",
                        album: nil,
                        artworkURL: nil,
                        durationSeconds: nil
                    )
                ]
            )
        )

        let row = ImportTrackRow(sourceLine: 1, title: "Song", artist: "Artist")
        let snapshot = try await resolver.resolve(row: row, options: .default)

        XCTAssertEqual(snapshot.status, .autoMatched)
        XCTAssertEqual(snapshot.catalogSongID, "cat-1")
        XCTAssertEqual(snapshot.librarySongID, nil)
    }

    @MainActor
    func test_resolver_prefersLibraryMatchWhenAvailable() async throws {
        let resolver = TrackResolutionService(
            searcher: StubSearcher(
                library: [
                    ResolvedSong(
                        catalogSongID: "cat-lib-1",
                        librarySongID: "lib-1",
                        title: "Song",
                        artist: "Artist",
                        album: nil,
                        artworkURL: nil,
                        durationSeconds: nil
                    )
                ],
                catalog: [
                    ResolvedSong(
                        catalogSongID: "cat-2",
                        librarySongID: nil,
                        title: "Song",
                        artist: "Artist",
                        album: nil,
                        artworkURL: nil,
                        durationSeconds: nil
                    )
                ]
            )
        )

        let row = ImportTrackRow(sourceLine: 1, title: "Song", artist: "Artist")
        let snapshot = try await resolver.resolve(row: row, options: .default)

        XCTAssertEqual(snapshot.status, .autoMatched)
        XCTAssertEqual(snapshot.catalogSongID, "cat-lib-1")
        XCTAssertEqual(snapshot.librarySongID, "lib-1")
    }

    @MainActor
    func test_resolver_enrichesLibraryMatchWithCatalogID() async throws {
        let resolver = TrackResolutionService(
            searcher: StubSearcher(
                library: [
                    ResolvedSong(
                        catalogSongID: nil,
                        librarySongID: "lib-1",
                        title: "Song",
                        artist: "Artist",
                        album: nil,
                        artworkURL: nil,
                        durationSeconds: nil
                    )
                ],
                catalog: [
                    ResolvedSong(
                        catalogSongID: "cat-1",
                        librarySongID: nil,
                        title: "Song",
                        artist: "Artist",
                        album: nil,
                        artworkURL: nil,
                        durationSeconds: nil
                    )
                ]
            )
        )

        let row = ImportTrackRow(sourceLine: 1, title: "Song", artist: "Artist")
        let snapshot = try await resolver.resolve(row: row, options: .default)

        XCTAssertEqual(snapshot.status, .autoMatched)
        XCTAssertEqual(snapshot.librarySongID, "lib-1")
        XCTAssertEqual(snapshot.catalogSongID, "cat-1")
    }
}

private struct StubSearcher: MusicCatalogSearching {
    let library: [ResolvedSong]
    let catalog: [ResolvedSong]

    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        library
    }

    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        catalog
    }
}
