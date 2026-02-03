import Foundation

struct ScoreWeights {
    let title: Double
    let artist: Double
    let album: Double
    let duration: Double

    static let `default` = ScoreWeights(title: 0.5, artist: 0.3, album: 0.15, duration: 0.05)
}

enum TrackNormalizer {
    static func normalize(_ input: String) -> String {
        var value = input.lowercased()

        // Remove common featuring patterns to improve equivalence checks.
        value = value.replacingOccurrences(
            of: #"\s*\((feat\.?|featuring)\s+[^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s*(feat\.?|featuring)\s+.+$"#,
            with: "",
            options: .regularExpression
        )

        value = value.replacingOccurrences(
            of: #"[^a-z0-9\s]"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MatchScore {
    let value: Double
    let rationale: String
}

enum MatchScorer {
    static func score(
        row: ImportTrackRow,
        candidate: LibraryTrack,
        weights: ScoreWeights = .default
    ) -> MatchScore {
        let titleMatch = TrackNormalizer.normalize(row.title) == TrackNormalizer.normalize(candidate.title) ? 1.0 : 0.0
        let artistMatch = TrackNormalizer.normalize(row.artist) == TrackNormalizer.normalize(candidate.artist) ? 1.0 : 0.0

        let albumMatch: Double
        if let rowAlbum = row.album, let candidateAlbum = candidate.album {
            albumMatch = TrackNormalizer.normalize(rowAlbum) == TrackNormalizer.normalize(candidateAlbum) ? 1.0 : 0.0
        } else {
            albumMatch = 0.0
        }

        let durationMatch: Double
        if let rowDuration = row.durationSeconds, let candidateDuration = candidate.durationSeconds {
            durationMatch = abs(rowDuration - candidateDuration) <= 2 ? 1.0 : 0.0
        } else {
            durationMatch = 0.0
        }

        let score =
            (titleMatch * weights.title) +
            (artistMatch * weights.artist) +
            (albumMatch * weights.album) +
            (durationMatch * weights.duration)

        let rationale = "title=\(titleMatch), artist=\(artistMatch), album=\(albumMatch), duration=\(durationMatch)"

        return MatchScore(value: score, rationale: rationale)
    }
}
