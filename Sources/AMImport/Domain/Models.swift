import Foundation

enum ImportFormat: String, CaseIterable, Codable {
    case csv
}

struct ImportTrackRow: Identifiable, Codable, Hashable {
    let id: String
    let sourceLine: Int
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int?
    let isrc: String?

    init(
        sourceLine: Int,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Int? = nil,
        isrc: String? = nil
    ) {
        self.id = "row-\(sourceLine)"
        self.sourceLine = sourceLine
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isrc = isrc
    }
}

struct LibraryTrack: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int?
    let isrc: String?
}

enum MatchStatus: String, Codable {
    case unmatched
    case autoMatched
    case userMatched
    case skipped
}

struct MatchCandidate: Codable, Hashable {
    let track: LibraryTrack
    let score: Double
    let rationale: String
}

struct MatchResult: Codable, Hashable {
    let rowID: String
    let status: MatchStatus
    let selectedTrack: LibraryTrack?
    let candidates: [MatchCandidate]
}

enum ExportMode: String, CaseIterable, Codable {
    case newPlaylist
    case enqueue
}
