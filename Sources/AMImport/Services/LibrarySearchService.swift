import Foundation

protocol LibrarySearching {
    func searchLibrary(query: String, limit: Int) async throws -> [LibraryTrack]
}

protocol LibrarySearchProviding {
    func fetchAllTracks() async throws -> [LibraryTrack]
}

struct LibrarySearchService: LibrarySearching {
    private let provider: LibrarySearchProviding

    init(provider: LibrarySearchProviding) {
        self.provider = provider
    }

    func searchLibrary(query: String, limit: Int) async throws -> [LibraryTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalizedQuery = TrackNormalizer.normalize(trimmed)
        let terms = normalizedQuery.split(separator: " ").map(String.init)

        let allTracks = try await provider.fetchAllTracks()

        let ranked = allTracks.compactMap { track -> (LibraryTrack, Int)? in
            let haystack = [track.title, track.artist, track.album ?? ""]
                .map(TrackNormalizer.normalize)
                .joined(separator: " ")

            let score = terms.reduce(0) { partial, term in
                partial + (haystack.contains(term) ? 1 : 0)
            }

            guard score > 0 else { return nil }
            return (track, score)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.id < $1.0.id
            }
            return $0.1 > $1.1
        }

        return ranked.prefix(limit).map(\.0)
    }
}
