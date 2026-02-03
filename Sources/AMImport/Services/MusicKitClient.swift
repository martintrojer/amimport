import Foundation

struct ResolvedSong: Equatable {
    let catalogSongID: String?
    let librarySongID: String?
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let durationSeconds: Int?
}

protocol MusicCatalogSearching {
    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong]
    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong]
}
