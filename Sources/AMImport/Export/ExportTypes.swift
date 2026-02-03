import Foundation

struct ExportRequest: Equatable {
    let mode: ExportMode
    let playlistName: String?
    let trackIDs: [String]
}

struct ExportTrackFailure: Equatable {
    let trackID: String
    let message: String
}

struct ExportResult: Equatable {
    let mode: ExportMode
    let requestedCount: Int
    let exportedCount: Int
    let failures: [ExportTrackFailure]
}
