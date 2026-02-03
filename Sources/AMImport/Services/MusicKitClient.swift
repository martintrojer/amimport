import Foundation
import MusicKit

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

struct MusicKitClient: MusicCatalogSearching {
    @MainActor
    func searchLibrary(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        let query = buildQuery(title: title, artist: artist, album: album)
        guard !query.isEmpty else { return [] }

        var request = MusicLibrarySearchRequest(term: query, types: [Song.self])
        request.limit = max(1, limit)

        let response = try await request.response()
        let songs = response.songs
        return songs.prefix(limit).map(mapLibrarySong)
    }

    @MainActor
    func searchCatalog(title: String, artist: String, album: String?, limit: Int) async throws -> [ResolvedSong] {
        let query = buildQuery(title: title, artist: artist, album: album)
        guard !query.isEmpty else { return [] }

        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = max(1, limit)

        let response = try await request.response()
        let songs = response.songs
        return songs.prefix(limit).map(mapCatalogSong)
    }

    private func buildQuery(title: String, artist: String, album: String?) -> String {
        let values = [title, artist, album ?? ""]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.joined(separator: " ")
    }

    private func mapLibrarySong(_ song: Song) -> ResolvedSong {
        ResolvedSong(
            catalogSongID: song.id.rawValue,
            librarySongID: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            artworkURL: song.artwork?.url(width: 120, height: 120),
            durationSeconds: song.duration.map(Int.init)
        )
    }

    private func mapCatalogSong(_ song: Song) -> ResolvedSong {
        ResolvedSong(
            catalogSongID: song.id.rawValue,
            librarySongID: nil,
            title: song.title,
            artist: song.artistName,
            album: song.albumTitle,
            artworkURL: song.artwork?.url(width: 120, height: 120),
            durationSeconds: song.duration.map(Int.init)
        )
    }
}
