import Foundation

enum MusicAppBridgeError: Error {
    case scriptCompilationFailed
    case scriptExecutionFailed(String)
}

protocol MusicAppControlling {
    @MainActor
    func createPlaylist(name: String, trackIDs: [String]) async throws
    @MainActor
    func enqueue(trackIDs: [String]) async throws
}

struct MusicAppBridge: MusicAppControlling {
    @MainActor
    func createPlaylist(name: String, trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }

        let idList = appleScriptArray(trackIDs)
        let escapedName = escape(name)
        let script = """
        tell application \"Music\"
            if not (exists user playlist \"\(escapedName)\") then
                make new user playlist with properties {name:\"\(escapedName)\"}
            end if
            set targetPlaylist to user playlist \"\(escapedName)\"
            set wantedIDs to \(idList)
            repeat with trackID in wantedIDs
                set matchedTracks to (every track of library playlist 1 whose persistent ID is trackID)
                if (count of matchedTracks) > 0 then
                    duplicate item 1 of matchedTracks to targetPlaylist
                end if
            end repeat
        end tell
        """

        try runAppleScript(script)
    }

    @MainActor
    func enqueue(trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }

        let idList = appleScriptArray(trackIDs)
        let script = """
        tell application \"Music\"
            set wantedIDs to \(idList)
            repeat with trackID in wantedIDs
                set matchedTracks to (every track of library playlist 1 whose persistent ID is trackID)
                if (count of matchedTracks) > 0 then
                    play (item 1 of matchedTracks) once
                end if
            end repeat
        end tell
        """

        try runAppleScript(script)
    }

    private func runAppleScript(_ source: String) throws {
        guard let appleScript = NSAppleScript(source: source) else {
            throw MusicAppBridgeError.scriptCompilationFailed
        }

        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo,
           let message = errorInfo[NSAppleScript.errorMessage] as? String {
            throw MusicAppBridgeError.scriptExecutionFailed(message)
        }
    }

    private func appleScriptArray(_ values: [String]) -> String {
        let escaped = values.map { "\"\(escape($0))\"" }
        return "{\(escaped.joined(separator: ", "))}"
    }

    private func escape(_ input: String) -> String {
        input.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
