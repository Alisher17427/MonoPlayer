import Foundation

struct LyricLine: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let time: TimeInterval
    let text: String
}
