import Foundation

/// Кандидат совпадения из любого источника — для автопоиска и ручного выбора.
struct MetadataCandidate: Sendable, Identifiable, Hashable {
    enum Source: String, Sendable {
        case genius = "Genius"
    }

    let id = UUID()
    let source: Source
    let title: String
    let artist: String
    let album: String?
    let artworkURL: URL?
    let duration: TimeInterval?
}

/// Варианты поисковых запросов и сравнение названий.
enum SearchQuery {
    /// "Song (feat. X) [Remastered 2011]" → ["Song (feat. X) [Remastered 2011]", "Song (feat. X)", "Song"]
    static func titleVariants(_ title: String) -> [String] {
        var variants = [title]
        let noBrackets = strip(title, pattern: "\\s*\\[[^\\]]*\\]")
        variants.append(noBrackets)
        let noSuffix = strip(noBrackets, pattern: "\\s+-\\s+.*(remaster|live|version|edit|mix|mono|stereo|deluxe).*$")
        variants.append(noSuffix)
        let noParens = strip(noSuffix, pattern: "\\s*\\([^\\)]*\\)")
        variants.append(noParens)
        let noFeat = strip(noParens, pattern: "\\s+(feat\\.?|ft\\.?|featuring)\\s+.*$")
        variants.append(noFeat)

        var seen = Set<String>()
        return variants
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// "Artist feat. Other" → "Artist"
    static func primaryArtist(_ artist: String) -> String {
        let cleaned = strip(artist, pattern: "\\s*[\\(\\[]?\\s*\\b(feat\\.?|ft\\.?|featuring)\\s+.*$")
        let result = cleaned.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? artist : result
    }

    /// Ключ настройки: считать «&» разделителем исполнителей (по умолчанию — да).
    static let splitAmpersandKey = "splitArtistsOnAmpersand"

    static var splitsAmpersand: Bool {
        UserDefaults.standard.object(forKey: splitAmpersandKey) as? Bool ?? true
    }

    /// "rocket, lildrughill" → ["rocket", "lildrughill"];
    /// "A feat. B & C" → ["A", "B", "C"]; "Macan x Jakone" → ["Macan", "Jakone"].
    static func splitArtists(_ artist: String, splitAmpersand: Bool = SearchQuery.splitsAmpersand) -> [String] {
        var text = artist
        // feat./ft./featuring (в т.ч. в скобках) → запятая
        text = replace(text, pattern: "\\s*[\\(\\[]\\s*(feat\\.?|ft\\.?|featuring)\\s+", with: ", ")
        text = replace(text, pattern: "\\s+(feat\\.?|ft\\.?|featuring)\\s+", with: ", ")
        text = replace(text, pattern: "[\\)\\]]", with: "")
        var separators = "\\s*[,;]\\s*|\\s+[x×]\\s+"
        if splitAmpersand { separators += "|\\s+&\\s+" }
        text = replace(text, pattern: separators, with: "\u{1F}")

        var seen = Set<String>()
        return text.split(separator: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Совпадает ли кандидат с искомым треком: название (с учётом очищенных вариантов) и артист, если известен.
    static func matches(title candidateTitle: String, artist candidateArtist: String, wantedTitle: String, wantedArtist: String?) -> Bool {
        let candidateTitles = titleVariants(candidateTitle).map(normalize).filter { !$0.isEmpty }
        let wantedTitles = titleVariants(wantedTitle).map(normalize).filter { !$0.isEmpty }
        let titleOK = candidateTitles.contains { c in wantedTitles.contains { w in c == w || c.contains(w) || w.contains(c) } }
        guard titleOK else { return false }
        guard let wantedArtist, !wantedArtist.isEmpty else { return true }
        let a = normalize(candidateArtist), b = normalize(primaryArtist(wantedArtist))
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.contains(b) || b.contains(a)
    }

    private static func strip(_ text: String, pattern: String) -> String {
        replace(text, pattern: pattern, with: "")
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

/// Общий HTTP-клиент для открытых API.
enum HTTP {
    static let userAgent = "MonoPlayer/1.1 (https://github.com/Alisher17427/MonoPlayer)"

    static func get(_ url: URL, timeout: TimeInterval = 15, accept: String? = "application/json") async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Картинки и страницы: 200 или ошибка.
    static func download(_ url: URL, accept: String? = nil) async throws -> Data {
        let (data, status) = try await get(url, accept: accept)
        guard status == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    static func url(_ base: String, _ items: [(String, String?)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        return components?.url
    }
}

// MARK: - Deezer (фото исполнителей, без ключа)

enum DeezerService {
    private struct ArtistResponse: Decodable {
        struct Item: Decodable { let name: String; let picture_xl: String? }
        let data: [Item]?
    }

    /// Фото артиста для страницы исполнителя.
    static func artistPictureURL(name: String) async throws -> URL? {
        guard let url = HTTP.url("https://api.deezer.com/search/artist", [("q", name), ("limit", "3")]) else { return nil }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let items = try JSONDecoder().decode(ArtistResponse.self, from: data).data ?? []
        let wanted = SearchQuery.normalize(name)
        let match = items.first { SearchQuery.normalize($0.name) == wanted } ?? items.first
        return match?.picture_xl.flatMap(URL.init(string:))
    }
}
