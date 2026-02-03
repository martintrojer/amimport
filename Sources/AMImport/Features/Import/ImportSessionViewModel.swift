import Foundation
import AppKit
import SwiftUI

enum ImportState: Equatable {
    case idle
    case requestingPermission
    case loadingLibrary
    case matching(progress: Int, total: Int)
    case completed(ImportSummary)
    case failed(String)
}

struct ImportSummary: Codable, Equatable {
    let totalRows: Int
    let autoMatched: Int
    let unmatched: Int
}

struct ImportSession: Codable, Equatable {
    let format: ImportFormat
    let options: MatchingOptions
    let importedRows: [ImportTrackRow]
    let decisions: [MatchDecisionSnapshot]
    let summary: ImportSummary
    let createdAt: Date
}

struct MatchDecisionSnapshot: Codable, Equatable {
    let rowID: String
    let status: MatchStatus
    let selectedTrackID: String?
    let catalogSongID: String?
    let librarySongID: String?
    let candidateTrackIDs: [String]
    let candidates: [MatchCandidateSnapshot]
    let confidence: Double
    let rationale: String

    init(
        rowID: String,
        status: MatchStatus,
        selectedTrackID: String?,
        catalogSongID: String?,
        librarySongID: String?,
        candidateTrackIDs: [String],
        candidates: [MatchCandidateSnapshot],
        confidence: Double,
        rationale: String
    ) {
        self.rowID = rowID
        self.status = status
        self.selectedTrackID = selectedTrackID
        self.catalogSongID = catalogSongID
        self.librarySongID = librarySongID
        self.candidateTrackIDs = candidateTrackIDs
        self.candidates = candidates
        self.confidence = confidence
        self.rationale = rationale
    }

    private enum CodingKeys: String, CodingKey {
        case rowID
        case status
        case selectedTrackID
        case catalogSongID
        case librarySongID
        case candidateTrackIDs
        case candidates
        case confidence
        case rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rowID = try container.decode(String.self, forKey: .rowID)
        status = try container.decode(MatchStatus.self, forKey: .status)
        selectedTrackID = try container.decodeIfPresent(String.self, forKey: .selectedTrackID)
        catalogSongID = try container.decodeIfPresent(String.self, forKey: .catalogSongID)
        librarySongID = try container.decodeIfPresent(String.self, forKey: .librarySongID)
        candidateTrackIDs = try container.decodeIfPresent([String].self, forKey: .candidateTrackIDs) ?? []
        candidates = try container.decodeIfPresent([MatchCandidateSnapshot].self, forKey: .candidates) ?? []
        confidence = try container.decode(Double.self, forKey: .confidence)
        rationale = try container.decode(String.self, forKey: .rationale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowID, forKey: .rowID)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(selectedTrackID, forKey: .selectedTrackID)
        try container.encodeIfPresent(catalogSongID, forKey: .catalogSongID)
        try container.encodeIfPresent(librarySongID, forKey: .librarySongID)
        try container.encode(candidateTrackIDs, forKey: .candidateTrackIDs)
        try container.encode(candidates, forKey: .candidates)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(rationale, forKey: .rationale)
    }
}

struct MatchCandidateSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let catalogSongID: String?
    let librarySongID: String?
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let durationSeconds: Int?
}

@MainActor
final class ImportSessionViewModel: ObservableObject {
    @Published var state: ImportState = .idle
    @Published var session: ImportSession?
    @Published var connectionStatusText: String = "Not checked"
    @Published var isConnectionHealthy: Bool = false
    @Published private(set) var connectionNeedsAutomationPermission: Bool = false
    @Published private(set) var lastAuthorizationStatus: MusicAuthorizationStatus = .notDetermined

    var shouldShowOpenSettingsShortcut: Bool {
        lastAuthorizationStatus == .denied
    }

    private let authorizer: MusicAuthorizing
    private let resolver: TrackResolving
    private let snapshotter: LibrarySnapshotting?

    init(
        authorizer: MusicAuthorizing,
        resolver: TrackResolving,
        snapshotter: LibrarySnapshotting? = nil
    ) {
        self.authorizer = authorizer
        self.resolver = resolver
        self.snapshotter = snapshotter
    }

    func runImport(
        rawInput: String,
        format: ImportFormat = .csv,
        parser: ImportParsing = CSVImporter(),
        options: MatchingOptions = .default
    ) async {
        do {
            let rows = try parser.parse(rawInput)

            state = .requestingPermission
            let authorization = await resolveAuthorization()
            lastAuthorizationStatus = authorization
            guard authorization == .authorized else {
                state = .failed(permissionMessage(for: authorization))
                return
            }

            state = .matching(progress: 0, total: rows.count)

            var snapshots: [MatchDecisionSnapshot] = []
            snapshots.reserveCapacity(rows.count)

            for (index, row) in rows.enumerated() {
                let snapshot = try await resolver.resolve(row: row, options: options)
                snapshots.append(snapshot)
                state = .matching(progress: index + 1, total: rows.count)
            }

            let autoMatched = snapshots.filter { $0.status == .autoMatched }.count
            let unmatched = snapshots.filter { $0.status == .unmatched }.count
            let summary = ImportSummary(totalRows: rows.count, autoMatched: autoMatched, unmatched: unmatched)

            session = ImportSession(
                format: format,
                options: options,
                importedRows: rows,
                decisions: snapshots,
                summary: summary,
                createdAt: Date()
            )
            state = .completed(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshConnectionStatus(requestIfNeeded: Bool = false) async {
        let authorization: MusicAuthorizationStatus
        if requestIfNeeded {
            authorization = await resolveAuthorization()
        } else {
            authorization = authorizer.currentStatus()
        }
        lastAuthorizationStatus = authorization
        guard authorization == .authorized else {
            isConnectionHealthy = false
            connectionNeedsAutomationPermission = false
            connectionStatusText = permissionMessage(for: authorization)
            return
        }

        if let snapshotter {
            do {
                let library = try await snapshotter.fetchAll { _ in }
                if library.isEmpty {
                    isConnectionHealthy = false
                    connectionNeedsAutomationPermission = false
                    connectionStatusText = "Connected, but no library tracks were found."
                } else {
                    isConnectionHealthy = true
                    connectionNeedsAutomationPermission = false
                    connectionStatusText = "Connected (\(library.count) library tracks available)."
                }
            } catch {
                isConnectionHealthy = false
                connectionNeedsAutomationPermission = isAutomationDenied(error)
                connectionStatusText = "Music connection check failed: \(error.localizedDescription)"
            }
            return
        }

        do {
            let probe = ImportTrackRow(sourceLine: 0, title: "Yesterday", artist: "The Beatles")
            _ = try await resolver.resolve(row: probe, options: .default)
            isConnectionHealthy = true
            connectionNeedsAutomationPermission = false
            connectionStatusText = "Connected to Apple Music."
        } catch {
            isConnectionHealthy = false
            connectionNeedsAutomationPermission = isAutomationDenied(error)
            connectionStatusText = "Music connection check failed: \(error.localizedDescription)"
        }
    }

    func openSystemSettingsForMediaAndMusic() {
        if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media"),
           NSWorkspace.shared.open(privacyURL) {
            return
        }
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension") {
            _ = NSWorkspace.shared.open(settingsURL)
        }
    }

    func openSystemSettingsForAutomation() {
        if let automationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
           NSWorkspace.shared.open(automationURL) {
            return
        }
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension") {
            _ = NSWorkspace.shared.open(settingsURL)
        }
    }

    private func resolveAuthorization() async -> MusicAuthorizationStatus {
        let current = authorizer.currentStatus()
        if current == .notDetermined {
            return await authorizer.request()
        }
        return current
    }

    private func permissionMessage(for status: MusicAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return ""
        case .denied:
            return "Apple Music access is denied. Enable access for AMImport in System Settings > Privacy & Security > Media & Apple Music."
        case .restricted:
            return "Apple Music access is restricted for this account or device."
        case .notDetermined:
            return "Apple Music access has not been granted yet. Click Check Connection to request access."
        }
    }

    private func isAutomationDenied(_ error: Error) -> Bool {
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("not authorized to send apple events")
            || lowered.contains("automation")
    }
}
