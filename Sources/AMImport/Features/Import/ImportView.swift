import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @StateObject private var viewModel: ImportSessionViewModel

    @State private var showImporter = false
    @State private var minimumScore = MatchingOptions.default.minimumScore
    @State private var candidateLimit = MatchingOptions.default.candidateLimit
    @State private var useExact = true
    @State private var useNormalized = true
    @State private var useFuzzy = true

    init(viewModel: @autoclosure @escaping () -> ImportSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AMImport")
                .font(.largeTitle)
            Text("CSV-first import pipeline with configurable matching")
                .foregroundStyle(.secondary)

            GroupBox("Import") {
                HStack {
                    Button("Choose CSV") {
                        showImporter = true
                    }
                    Text(stateLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            GroupBox("Matching") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Exact", isOn: $useExact)
                    Toggle("Normalized Exact", isOn: $useNormalized)
                    Toggle("Fuzzy", isOn: $useFuzzy)
                    HStack {
                        Text("Minimum Score")
                        Slider(value: $minimumScore, in: 0.5 ... 1.0, step: 0.01)
                        Text(String(format: "%.2f", minimumScore))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    Stepper("Candidate Limit: \(candidateLimit)", value: $candidateLimit, in: 1 ... 20)
                }
            }

            GroupBox("Summary") {
                if case let .completed(summary) = viewModel.state {
                    VStack(alignment: .leading) {
                        Text("Total rows: \(summary.totalRows)")
                        Text("Auto-matched: \(summary.autoMatched)")
                        Text("Unmatched: \(summary.unmatched)")
                    }
                } else {
                    Text("No completed import yet")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .text]
        ) { result in
            switch result {
            case let .success(url):
                guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                    return
                }
                let options = matchingOptions()
                Task { @MainActor in
                    await viewModel.runImport(rawInput: raw, format: .csv, options: options)
                }
            case .failure:
                break
            }
        }
    }

    private var stateLabel: String {
        switch viewModel.state {
        case .idle:
            return "Idle"
        case .requestingPermission:
            return "Requesting Apple Music permission"
        case .loadingLibrary:
            return "Loading library"
        case let .matching(progress, total):
            return "Matching \(progress)/\(total)"
        case .completed:
            return "Completed"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }

    private func matchingOptions() -> MatchingOptions {
        var strategies: [MatchingStrategy] = []
        if useExact { strategies.append(.exact) }
        if useNormalized { strategies.append(.normalizedExact) }
        if useFuzzy { strategies.append(.fuzzy) }
        if strategies.isEmpty {
            strategies = [.exact]
        }

        return MatchingOptions(
            strategies: strategies,
            minimumScore: minimumScore,
            candidateLimit: candidateLimit
        )
    }
}
