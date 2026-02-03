import Foundation

struct MatchDecision {
    let result: MatchResult
    let confidence: Double
    let rationale: String
}

struct MatcherPipeline {
    func match(
        row: ImportTrackRow,
        in libraryTracks: [LibraryTrack],
        options: MatchingOptions
    ) -> MatchDecision {
        let evaluated = libraryTracks.compactMap { track -> MatchCandidate? in
            let score = score(row: row, track: track, strategies: options.strategies)
            guard score.value > 0 else { return nil }
            return MatchCandidate(track: track, score: score.value, rationale: score.rationale)
        }

        let sorted = evaluated.sorted {
            if $0.score == $1.score {
                return $0.track.id < $1.track.id
            }
            return $0.score > $1.score
        }

        let limited = Array(sorted.prefix(options.candidateLimit))

        guard let best = limited.first else {
            return MatchDecision(
                result: MatchResult(rowID: row.id, status: .unmatched, selectedTrack: nil, candidates: []),
                confidence: 0,
                rationale: "No candidates"
            )
        }

        if best.score >= options.minimumScore {
            return MatchDecision(
                result: MatchResult(rowID: row.id, status: .autoMatched, selectedTrack: best.track, candidates: limited),
                confidence: best.score,
                rationale: best.rationale
            )
        }

        return MatchDecision(
            result: MatchResult(rowID: row.id, status: .unmatched, selectedTrack: nil, candidates: limited),
            confidence: best.score,
            rationale: "Below minimum score \(options.minimumScore)"
        )
    }

    private func score(
        row: ImportTrackRow,
        track: LibraryTrack,
        strategies: [MatchingStrategy]
    ) -> (value: Double, rationale: String) {
        var best: (Double, String) = (0, "No strategy matched")

        for strategy in strategies {
            switch strategy {
            case .exact:
                if row.title == track.title && row.artist == track.artist {
                    best = maxScore(best, candidate: (1.0, "Exact title+artist"))
                }
            case .normalizedExact:
                if TrackNormalizer.normalize(row.title) == TrackNormalizer.normalize(track.title)
                    && TrackNormalizer.normalize(row.artist) == TrackNormalizer.normalize(track.artist) {
                    best = maxScore(best, candidate: (0.99, "Normalized exact title+artist"))
                }
            case .fuzzy:
                let title = similarity(TrackNormalizer.normalize(row.title), TrackNormalizer.normalize(track.title))
                let artist = similarity(TrackNormalizer.normalize(row.artist), TrackNormalizer.normalize(track.artist))
                let fuzzy = (title * 0.7) + (artist * 0.3)
                best = maxScore(best, candidate: (fuzzy, "Fuzzy title=\(title), artist=\(artist)"))
            }
        }

        return (best.0, best.1)
    }

    private func maxScore(_ current: (Double, String), candidate: (Double, String)) -> (Double, String) {
        if candidate.0 > current.0 {
            return candidate
        }
        return current
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 1 }

        let distance = levenshtein(lhs, rhs)
        let maxLen = max(lhs.count, rhs.count)
        return max(0, 1 - (Double(distance) / Double(maxLen)))
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)

        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)

        for (i, ca) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, cb) in b.enumerated() {
                let cost = ca == cb ? 0 : 1
                current[j + 1] = min(
                    current[j] + 1,
                    previous[j + 1] + 1,
                    previous[j] + cost
                )
            }
            previous = current
        }

        return previous[b.count]
    }
}
