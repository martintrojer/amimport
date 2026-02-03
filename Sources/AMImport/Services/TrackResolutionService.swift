import Foundation

protocol TrackResolving {
    @MainActor
    func resolve(row: ImportTrackRow, options: MatchingOptions) async throws -> MatchDecisionSnapshot
}

struct TrackResolutionService: TrackResolving {
    private let searcher: MusicCatalogSearching
    private let matcher: MatcherPipeline

    init(searcher: MusicCatalogSearching, matcher: MatcherPipeline = MatcherPipeline()) {
        self.searcher = searcher
        self.matcher = matcher
    }

    @MainActor
    func resolve(row: ImportTrackRow, options: MatchingOptions) async throws -> MatchDecisionSnapshot {
        let libraryResults = try await searcher.searchLibrary(
            title: row.title,
            artist: row.artist,
            album: row.album,
            limit: options.candidateLimit
        )

        let libraryDecision = evaluate(row: row, options: options, songs: libraryResults)
        if libraryDecision.status != .unmatched || !libraryResults.isEmpty {
            return libraryDecision
        }

        let catalogResults = try await searcher.searchCatalog(
            title: row.title,
            artist: row.artist,
            album: row.album,
            limit: options.candidateLimit
        )

        return evaluate(row: row, options: options, songs: catalogResults)
    }

    private func evaluate(row: ImportTrackRow, options: MatchingOptions, songs: [ResolvedSong]) -> MatchDecisionSnapshot {
        let mapped: [(track: LibraryTrack, resolved: ResolvedSong)] = songs.map { song in
            (
                track: LibraryTrack(
                    id: song.librarySongID ?? song.catalogSongID ?? UUID().uuidString,
                    title: song.title,
                    artist: song.artist,
                    album: song.album,
                    durationSeconds: song.durationSeconds,
                    isrc: nil
                ),
                resolved: song
            )
        }

        let tracks = mapped.map(\.track)
        let byTrackID = Dictionary(uniqueKeysWithValues: mapped.map { ($0.track.id, $0.resolved) })

        let decision = matcher.match(row: row, in: tracks, options: options)
        let selected = decision.result.selectedTrack.flatMap { byTrackID[$0.id] }
        let candidates = decision.result.candidates.compactMap { candidate -> MatchCandidateSnapshot? in
            guard let resolved = byTrackID[candidate.track.id] else { return nil }
            return MatchCandidateSnapshot(
                id: candidate.track.id,
                catalogSongID: resolved.catalogSongID,
                librarySongID: resolved.librarySongID,
                title: resolved.title,
                artist: resolved.artist,
                album: resolved.album,
                artworkURL: resolved.artworkURL,
                durationSeconds: resolved.durationSeconds
            )
        }

        return MatchDecisionSnapshot(
            rowID: row.id,
            status: decision.result.status,
            selectedTrackID: decision.result.selectedTrack?.id,
            catalogSongID: selected?.catalogSongID,
            librarySongID: selected?.librarySongID,
            candidateTrackIDs: decision.result.candidates.map(\.track.id),
            candidates: candidates,
            confidence: decision.confidence,
            rationale: decision.rationale
        )
    }
}
