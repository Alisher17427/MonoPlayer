import Foundation

struct ITunesTrack: Decodable, Sendable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
    var trackTimeMillis: Int? = nil

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

    static func candidates(artist: String?, title: String) async throws -> [MetadataCandidate] {
        try await search(artist: artist, title: title).compactMap { hit in
            guard let name = hit.trackName else { return nil }
            return MetadataCandidate(
                source: .iTunes, title: name, artist: hit.artistName ?? "", album: hit.collectionName,
                artworkURL: hit.hdArtworkURL, duration: hit.trackTimeMillis.map { TimeInterval($0) / 1000 }
            )
        }
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

    static func normalize(_ text: String) -> String { SearchQuery.normalize(text) }

    static func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
