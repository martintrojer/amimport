import Foundation

protocol ImportParsing {
    func parse(_ raw: String) throws -> [ImportTrackRow]
}

enum CSVImportError: Error, Equatable {
    case missingRequiredColumns([String])
}

struct CSVImporter: ImportParsing {
    func parse(_ raw: String) throws -> [ImportTrackRow] {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noBOM = cleaned.replacingOccurrences(of: "\u{feff}", with: "")
        let lines = noBOM
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else { return [] }

        let headers = parseCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        let required = ["title", "artist"]
        let missing = required.filter { !headers.contains($0) }
        if !missing.isEmpty {
            throw CSVImportError.missingRequiredColumns(missing)
        }

        let titleIndex = headers.firstIndex(of: "title")!
        let artistIndex = headers.firstIndex(of: "artist")!
        let albumIndex = headers.firstIndex(of: "album")
        let durationIndex = headers.firstIndex(of: "duration")
        let isrcIndex = headers.firstIndex(of: "isrc")

        var rows: [ImportTrackRow] = []

        for (rowOffset, line) in lines.dropFirst().enumerated() {
            let values = parseCSVLine(line)
            let title = value(at: titleIndex, in: values).trimmingCharacters(in: .whitespacesAndNewlines)
            let artist = value(at: artistIndex, in: values).trimmingCharacters(in: .whitespacesAndNewlines)

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

    private func parseCSVLine(_ line: String) -> [String] {
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
            } else if char == "," && !inQuotes {
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
