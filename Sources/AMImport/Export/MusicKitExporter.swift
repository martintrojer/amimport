import Foundation
import MusicKit

struct ExportExecutionSummary: Equatable {
    let requested: Int
    let succeeded: Int
    let skipped: Int
}

protocol MusicKitExporting {
    @MainActor
    func createPlaylist(name: String, catalogSongIDs: [String]) async throws -> ExportExecutionSummary
    @MainActor
    func enqueueAndPlay(catalogSongIDs: [String]) async throws -> ExportExecutionSummary
}

enum MusicKitExporterError: LocalizedError {
    case noPlayableTracks
    case playlistCreationUnavailable

    var errorDescription: String? {
        switch self {
        case .noPlayableTracks:
            return "No playable catalog tracks were available."
        case .playlistCreationUnavailable:
            return "Playlist creation via MusicKit isn't available on macOS."
        }
    }
}

protocol CatalogSongResolving {
    @MainActor
    func song(for catalogSongID: String) async throws -> Song?
}

struct MusicKitCatalogSongResolver: CatalogSongResolving {
    @MainActor
    func song(for catalogSongID: String) async throws -> Song? {
        let normalized = catalogSongID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(rawValue: normalized))
        request.limit = 1

        let response = try await request.response()
        return response.items.first
    }
}

protocol PlaylistCreating {
    @MainActor
    func createPlaylist(name: String, items: [Song]) async throws -> Playlist
}

struct MusicLibraryPlaylistCreator: PlaylistCreating {
    @MainActor
    func createPlaylist(name: String, items: [Song]) async throws -> Playlist {
        #if os(macOS)
        throw MusicKitExporterError.playlistCreationUnavailable
        #else
        return try await MusicLibrary.shared.createPlaylist(name: name, items: items)
        #endif
    }
}

protocol MusicQueuePlaying {
    @MainActor
    func replaceQueue(with songs: [Song])
    @MainActor
    func play() async throws
}

struct ApplicationMusicPlayerAdapter: MusicQueuePlaying {
    @MainActor
    func replaceQueue(with songs: [Song]) {
        ApplicationMusicPlayer.shared.queue = ApplicationMusicPlayer.Queue(for: songs)
    }

    @MainActor
    func play() async throws {
        try await ApplicationMusicPlayer.shared.play()
    }
}

struct MusicKitExporter: MusicKitExporting {
    private let resolver: CatalogSongResolving
    private let playlistCreator: PlaylistCreating
    private let player: MusicQueuePlaying

    init(
        resolver: CatalogSongResolving = MusicKitCatalogSongResolver(),
        playlistCreator: PlaylistCreating = MusicLibraryPlaylistCreator(),
        player: MusicQueuePlaying = ApplicationMusicPlayerAdapter()
    ) {
        self.resolver = resolver
        self.playlistCreator = playlistCreator
        self.player = player
    }

    @MainActor
    func createPlaylist(name: String, catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        let resolution = try await resolveSongs(catalogSongIDs: catalogSongIDs)
        guard !resolution.songs.isEmpty else {
            throw MusicKitExporterError.noPlayableTracks
        }

        _ = try await playlistCreator.createPlaylist(name: name, items: resolution.songs)
        return resolution.summary
    }

    @MainActor
    func enqueueAndPlay(catalogSongIDs: [String]) async throws -> ExportExecutionSummary {
        let resolution = try await resolveSongs(catalogSongIDs: catalogSongIDs)
        guard !resolution.songs.isEmpty else {
            throw MusicKitExporterError.noPlayableTracks
        }

        player.replaceQueue(with: resolution.songs)
        try await player.play()
        return resolution.summary
    }

    @MainActor
    private func resolveSongs(catalogSongIDs: [String]) async throws -> (songs: [Song], summary: ExportExecutionSummary) {
        var songs: [Song] = []
        songs.reserveCapacity(catalogSongIDs.count)

        for catalogSongID in catalogSongIDs {
            if let song = try await resolver.song(for: catalogSongID) {
                songs.append(song)
            }
        }

        let requested = catalogSongIDs.count
        let succeeded = songs.count
        let skipped = max(0, requested - succeeded)

        return (
            songs,
            ExportExecutionSummary(requested: requested, succeeded: succeeded, skipped: skipped)
        )
    }
}
