import Foundation

struct ITunesTrack: Decodable, Sendable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?

    /// artworkUrl100 → 1000x1000bb.jpg
    var hdArtworkURL: URL? {
        guard let artworkUrl100 else { return nil }
        return URL(string: artworkUrl100.replacingOccurrences(of: "100x100bb", with: "1000x1000bb"))
    }
}

enum ITunesSearchService {
    private struct Response: Decodable {
        let results: [ITunesTrack]
    }

    static func search(artist: String?, title: String) async throws -> [ITunesTrack] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        let term = [artist, title].compactMap { $0 }.joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data).results
    }

    /// Лучшее совпадение: название должно совпадать (с точностью до регистра/пунктуации),
    /// артист — если он известен.
    static func bestMatch(in results: [ITunesTrack], artist: String?, title: String) -> ITunesTrack? {
        let wantedTitle = normalize(title)
        let wantedArtist = artist.map(normalize)
        return results.first { hit in
            guard let hitTitle = hit.trackName.map(normalize), !hitTitle.isEmpty, !wantedTitle.isEmpty else { return false }
            let titleMatches = hitTitle.contains(wantedTitle) || wantedTitle.contains(hitTitle)
            guard titleMatches else { return false }
            guard let wantedArtist, !wantedArtist.isEmpty else { return true }
            let hitArtist = normalize(hit.artistName ?? "")
            return hitArtist.contains(wantedArtist) || wantedArtist.contains(hitArtist)
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    static func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
