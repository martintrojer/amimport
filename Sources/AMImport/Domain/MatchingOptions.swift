import Foundation

enum MatchingStrategy: String, CaseIterable, Codable {
    case exact
    case normalizedExact
    case fuzzy
}

struct MatchingOptions: Codable, Equatable {
    var strategies: [MatchingStrategy]
    var minimumScore: Double
    var candidateLimit: Int

    static let `default` = MatchingOptions(
        strategies: [.exact, .normalizedExact, .fuzzy],
        minimumScore: 0.75,
        candidateLimit: 5
    )
}
