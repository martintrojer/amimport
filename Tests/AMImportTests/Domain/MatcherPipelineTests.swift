import XCTest
@testable import AMImport

final class MatcherPipelineTests: XCTestCase {
    func test_exactMatchIsPrioritizedOverFuzzyCandidate() {
        let row = ImportTrackRow(sourceLine: 1, title: "Hello", artist: "Artist")
        let exact = LibraryTrack(id: "exact", title: "Hello", artist: "Artist", album: nil, durationSeconds: nil, isrc: nil)
        let fuzzy = LibraryTrack(id: "fuzzy", title: "Hello!", artist: "Artist", album: nil, durationSeconds: nil, isrc: nil)

        let decision = MatcherPipeline().match(row: row, in: [fuzzy, exact], options: .default)

        XCTAssertEqual(decision.result.status, .autoMatched)
        XCTAssertEqual(decision.result.selectedTrack?.id, "exact")
    }

    func test_fuzzyStrategyReturnsUnresolvedWithCandidatesWhenNoConfidentMatch() {
        let row = ImportTrackRow(sourceLine: 1, title: "Heloo", artist: "Artst")
        let candidate = LibraryTrack(id: "cand1", title: "Hello", artist: "Artist", album: nil, durationSeconds: nil, isrc: nil)

        let options = MatchingOptions(strategies: [.fuzzy], minimumScore: 0.95, candidateLimit: 3)
        let decision = MatcherPipeline().match(row: row, in: [candidate], options: options)

        XCTAssertEqual(decision.result.status, .unmatched)
        XCTAssertGreaterThan(decision.result.candidates.count, 0)
    }

    func test_tieBreakIsDeterministicByTrackID() {
        let row = ImportTrackRow(sourceLine: 1, title: "Same", artist: "Artist")
        let a = LibraryTrack(id: "b-id", title: "Same", artist: "Artist", album: nil, durationSeconds: nil, isrc: nil)
        let b = LibraryTrack(id: "a-id", title: "Same", artist: "Artist", album: nil, durationSeconds: nil, isrc: nil)

        let decision = MatcherPipeline().match(row: row, in: [a, b], options: .default)

        XCTAssertEqual(decision.result.selectedTrack?.id, "a-id")
    }
}
