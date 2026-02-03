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
    let candidateTrackIDs: [String]
    let confidence: Double
    let rationale: String
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
    private let snapshotter: LibrarySnapshotting
    private let matcher: MatcherPipeline

    init(
        authorizer: MusicAuthorizing,
        snapshotter: LibrarySnapshotting,
        matcher: MatcherPipeline = MatcherPipeline()
    ) {
        self.authorizer = authorizer
        self.snapshotter = snapshotter
        self.matcher = matcher
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

            state = .loadingLibrary
            let library = try await snapshotter.fetchAll { _ in }
            guard !library.isEmpty else {
                state = .failed("Connected to Music, but no library tracks were found. Open the Music app and confirm your library is populated and sync is enabled.")
                return
            }

            var snapshots: [MatchDecisionSnapshot] = []
            snapshots.reserveCapacity(rows.count)

            for (index, row) in rows.enumerated() {
                let decision = matcher.match(row: row, in: library, options: options)
                snapshots.append(
                    MatchDecisionSnapshot(
                        rowID: row.id,
                        status: decision.result.status,
                        selectedTrackID: decision.result.selectedTrack?.id,
                        candidateTrackIDs: decision.result.candidates.map(\.track.id),
                        confidence: decision.confidence,
                        rationale: decision.rationale
                    )
                )
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
