import Foundation

protocol ImportParsing {
    func parse(_ raw: String) throws -> [ImportTrackRow]
}

enum CSVImportError: Error, Equatable {
    case missingRequiredColumns([String])
    case emptyFile
}

extension CSVImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingRequiredColumns(columns):
            return "Missing required column(s): \(columns.joined(separator: ", ")). Expected at least title and artist."
        case .emptyFile:
            return "The selected file is empty."
        }
    }
}

struct CSVImporter: ImportParsing {
    private static let headerAliases: [String: [String]] = [
        "title": ["title", "song", "track", "track name", "song title", "name"],
        "artist": ["artist", "artist name", "album artist"],
        "album": ["album", "album title", "release"],
        "duration": ["duration", "length", "time"],
        "isrc": ["isrc", "isrc code"]
    ]

    func parse(_ raw: String) throws -> [ImportTrackRow] {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noBOM = cleaned.replacingOccurrences(of: "\u{feff}", with: "")
        let lines = noBOM
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else {
            throw CSVImportError.emptyFile
        }

        let delimiter = detectDelimiter(in: headerLine)
        let headers = parseDelimitedLine(headerLine, delimiter: delimiter)
            .map(normalizeHeader)

        let titleIndex = firstIndex(forCanonical: "title", in: headers)
        let artistIndex = firstIndex(forCanonical: "artist", in: headers)
        let albumIndex = firstIndex(forCanonical: "album", in: headers)
        let durationIndex = firstIndex(forCanonical: "duration", in: headers)
        let isrcIndex = firstIndex(forCanonical: "isrc", in: headers)

        let missing = [
            titleIndex == nil ? "title" : nil,
            artistIndex == nil ? "artist" : nil
        ].compactMap { $0 }
        if !missing.isEmpty {
            throw CSVImportError.missingRequiredColumns(missing)
        }

        let requiredTitleIndex = titleIndex!
        let requiredArtistIndex = artistIndex!

        var rows: [ImportTrackRow] = []

        for (rowOffset, line) in lines.dropFirst().enumerated() {
            let values = parseDelimitedLine(line, delimiter: delimiter)
            let title = value(at: requiredTitleIndex, in: values).trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = value(at: requiredArtistIndex, in: values).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, !artist.isEmpty else { continue }

            let album = optionalValue(at: albumIndex, in: values)
            let duration = parseDuration(optionalValue(at: durationIndex, in: values))
            let isrc = optionalValue(at: isrcIndex, in: values)

            rows.append(
                ImportTrackRow(
                    sourceLine: rowOffset + 2,
                    title: title,
                    artist: artist,
                    album: album,
                    durationSeconds: duration,
                    isrc: isrc
                )
            )
        }

        return rows
    }

    private func detectDelimiter(in headerLine: String) -> Character {
        let candidates: [Character] = [",", ";", "\t"]
        let best = candidates.max { lhs, rhs in
            parseDelimitedLine(headerLine, delimiter: lhs).count < parseDelimitedLine(headerLine, delimiter: rhs).count
        }
        return best ?? ","
    }

    private func firstIndex(forCanonical canonical: String, in headers: [String]) -> Int? {
        let aliases = Set(Self.headerAliases[canonical] ?? [canonical])
        return headers.firstIndex { aliases.contains($0) }
    }

    private func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func value(at index: Int, in values: [String]) -> String {
        guard index < values.count else { return "" }
        return values[index]
    }

    private func optionalValue(at index: Int?, in values: [String]) -> String? {
        guard let index else { return nil }
        let trimmed = value(at: index, in: values).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDuration(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        if let seconds = Int(raw) {
            return seconds
        }

        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]) else {
            return nil
        }

        return minutes * 60 + seconds
    }

    private func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var output: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]

            if char == "\"" {
                let nextIndex = line.index(after: index)
                if inQuotes, nextIndex < line.endIndex, line[nextIndex] == "\"" {
                    current.append("\"")
                    index = nextIndex
                } else {
                    inQuotes.toggle()
                }
            } else if char == delimiter && !inQuotes {
                output.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(char)
            }

            index = line.index(after: index)
        }

        output.append(current)
        return output
    }
}
