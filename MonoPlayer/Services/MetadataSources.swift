import Foundation

/// Кандидат совпадения из любого источника — для автопоиска и ручного выбора.
struct MetadataCandidate: Sendable, Identifiable, Hashable {
    enum Source: String, Sendable {
        case iTunes = "iTunes"
        case deezer = "Deezer"
        case musicBrainz = "MusicBrainz"
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

    static func get(_ url: URL, timeout: TimeInterval = 15) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func url(_ base: String, _ items: [(String, String?)]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        return components?.url
    }
}

// MARK: - Deezer (обложки 1000×1000, без ключа)

enum DeezerService {
    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable { let title: String?; let cover_xl: String? }
            let title: String
            let duration: Int?
            let artist: Artist
            let album: Album?
        }
        let data: [Item]?
    }

    private struct ArtistResponse: Decodable {
        struct Item: Decodable { let name: String; let picture_xl: String? }
        let data: [Item]?
    }

    static func search(artist: String?, title: String) async throws -> [MetadataCandidate] {
        let query = artist.map { "artist:\"\($0)\" track:\"\(title)\"" } ?? title
        guard let url = HTTP.url("https://api.deezer.com/search", [("q", query), ("limit", "5")]) else { return [] }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let items = try JSONDecoder().decode(SearchResponse.self, from: data).data ?? []
        return items.map {
            MetadataCandidate(
                source: .deezer, title: $0.title, artist: $0.artist.name, album: $0.album?.title,
                artworkURL: $0.album?.cover_xl.flatMap(URL.init(string:)),
                duration: $0.duration.map(TimeInterval.init)
            )
        }
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

// MARK: - MusicBrainz + Cover Art Archive (открытая база, редкие релизы)

enum MusicBrainzService {
    private struct Response: Decodable {
        struct Recording: Decodable {
            struct Credit: Decodable { let name: String }
            struct Release: Decodable { let id: String; let title: String? }
            let title: String
            let length: Int?
            let artistCredit: [Credit]?
            let releases: [Release]?

            enum CodingKeys: String, CodingKey {
                case title, length, releases
                case artistCredit = "artist-credit"
            }
        }
        let recordings: [Recording]?
    }

    static func search(artist: String?, title: String) async throws -> [MetadataCandidate] {
        var query = "recording:\"\(escape(title))\""
        if let artist { query += " AND artist:\"\(escape(artist))\"" }
        guard let url = HTTP.url("https://musicbrainz.org/ws/2/recording", [("query", query), ("fmt", "json"), ("limit", "5")]) else { return [] }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let recordings = try JSONDecoder().decode(Response.self, from: data).recordings ?? []
        return recordings.map { recording in
            let release = recording.releases?.first
            return MetadataCandidate(
                source: .musicBrainz,
                title: recording.title,
                artist: recording.artistCredit?.map(\.name).joined(separator: ", ") ?? "",
                album: release?.title,
                artworkURL: release.flatMap { URL(string: "https://coverartarchive.org/release/\($0.id)/front-1200") },
                duration: recording.length.map { TimeInterval($0) / 1000 }
            )
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "")
    }
}

// MARK: - Оркестратор

enum MetadataSearch {
    /// Автопоиск: iTunes → Deezer → MusicBrainz по нескольким вариантам названия.
    /// Возвращает первое совпадение и, если у него нет обложки, ищет её у следующих источников.
    static func bestMatch(artist: String?, title: String) async -> (match: MetadataCandidate?, artworkURL: URL?, allFailed: Bool) {
        var match: MetadataCandidate?
        var artworkURL: URL?
        var attempts = 0, failures = 0

        let sources: [(String?, String) async throws -> [MetadataCandidate]] = [
            ITunesSearchService.candidates, DeezerService.search, MusicBrainzService.search,
        ]
        let variants = Array(SearchQuery.titleVariants(title).prefix(3))

        sourceLoop: for source in sources {
            for variant in variants {
                attempts += 1
                do {
                    let candidates = try await source(artist, variant)
                    let found = candidates.first { SearchQuery.matches(title: $0.title, artist: $0.artist, wantedTitle: title, wantedArtist: artist) }
                    if let found {
                        if match == nil { match = found }
                        if artworkURL == nil { artworkURL = found.artworkURL }
                        if artworkURL != nil { break sourceLoop }
                        continue sourceLoop
                    }
                } catch {
                    failures += 1
                    continue sourceLoop
                }
            }
        }
        return (match, artworkURL, attempts > 0 && failures == attempts)
    }

    /// Ручной выбор: все кандидаты из всех источников параллельно.
    static func allCandidates(artist: String?, title: String) async -> [MetadataCandidate] {
        async let itunes = (try? ITunesSearchService.candidates(artist: artist, title: title)) ?? []
        async let deezer = (try? DeezerService.search(artist: artist, title: title)) ?? []
        async let brainz = (try? MusicBrainzService.search(artist: artist, title: title)) ?? []
        var result = await itunes + deezer + brainz
        // Без артиста — повторный поиск только по названию у iTunes и Deezer
        if result.isEmpty, artist != nil {
            async let i2 = (try? ITunesSearchService.candidates(artist: nil, title: title)) ?? []
            async let d2 = (try? DeezerService.search(artist: nil, title: title)) ?? []
            result = await i2 + d2
        }
        return result
    }
}
