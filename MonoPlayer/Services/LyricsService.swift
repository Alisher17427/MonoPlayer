import Foundation

/// Запись LRCLIB (https://lrclib.net).
struct LRCLibRecord: Decodable, Sendable {
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var duration: Double?
    var plainLyrics: String?
    var syncedLyrics: String?
    var instrumental: Bool?

    var hasSynced: Bool { syncedLyrics?.isEmpty == false }
    var hasPlain: Bool { plainLyrics?.isEmpty == false }
}

/// Найденный текст — для автопоиска и ручного выбора.
struct LyricsCandidate: Sendable, Identifiable, Hashable {
    let id = UUID()
    let source: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: TimeInterval?
    let plainLyrics: String?
    let syncedLyrics: String?

    var isSynced: Bool { syncedLyrics?.isEmpty == false }
}

enum LyricsService {
    /// Допустимая разница длительностей, при которой тайминги LRC ещё совпадают с файлом.
    static let durationTolerance: TimeInterval = 3

    /// Автопоиск: LRCLIB get → LRCLIB search по вариантам названия (выбор по длительности) → lyrics.ovh.
    /// Синхронизированный текст важнее обычного; обычный берётся, только если синхронного нет нигде.
    static func find(artist: String?, title: String, album: String?, duration: TimeInterval) async throws -> LyricsCandidate? {
        var plainFallback: LyricsCandidate?
        var anySucceeded = false

        // 1. Точный запрос (LRCLIB сам сверяет длительность ±2 с)
        if let artist, duration > 0 {
            for withAlbum in [true, false] where withAlbum == false || album != nil {
                guard let url = HTTP.url("https://lrclib.net/api/get", [
                    ("artist_name", artist), ("track_name", title),
                    ("album_name", withAlbum ? album : nil),
                    ("duration", String(Int(duration.rounded()))),
                ]) else { continue }
                if let response = try? await HTTP.get(url) {
                    let (data, status) = response
                    anySucceeded = true
                    if status == 200, let record = try? JSONDecoder().decode(LRCLibRecord.self, from: data) {
                        let candidate = makeCandidate(record, fallbackTitle: title, fallbackArtist: artist)
                        if candidate.isSynced { return candidate }
                        if record.hasPlain { plainFallback = plainFallback ?? candidate }
                    }
                }
            }
        }

        // 2. Поиск с выбором по длительности
        do {
            let candidates = try await search(artist: artist, title: title)
            anySucceeded = true
            if let best = pickBest(candidates, duration: duration, wantedTitle: title, wantedArtist: artist) {
                if best.isSynced { return best }
                plainFallback = plainFallback ?? best
            }
        } catch {}

        if let plainFallback { return plainFallback }

        // 3. Запасной источник обычного текста
        if let artist, let plain = try? await lyricsOvh(artist: artist, title: title) {
            return LyricsCandidate(source: "lyrics.ovh", trackName: title, artistName: artist, albumName: nil,
                                   duration: nil, plainLyrics: plain, syncedLyrics: nil)
        }
        if !anySucceeded { throw URLError(.notConnectedToInternet) }
        return nil
    }

    /// Все кандидаты LRCLIB по нескольким вариантам названия — для ручного выбора.
    static func search(artist: String?, title: String) async throws -> [LyricsCandidate] {
        var result: [LyricsCandidate] = []
        var seen = Set<String>()
        var lastError: Error?
        var succeeded = false

        for variant in SearchQuery.titleVariants(title).prefix(3) {
            var queries: [[(String, String?)]] = [[("track_name", variant), ("artist_name", artist)]]
            queries.append([("q", [artist, variant].compactMap { $0 }.joined(separator: " "))])
            for items in queries {
                guard let url = HTTP.url("https://lrclib.net/api/search", items) else { continue }
                do {
                    let (data, status) = try await HTTP.get(url)
                    succeeded = true
                    guard status == 200 else { continue }
                    let records = (try? JSONDecoder().decode([LRCLibRecord].self, from: data)) ?? []
                    for record in records where record.hasSynced || record.hasPlain {
                        let key = "\(record.trackName ?? "")|\(record.artistName ?? "")|\(Int(record.duration ?? 0))|\(record.hasSynced)"
                        if seen.insert(key).inserted {
                            result.append(makeCandidate(record, fallbackTitle: variant, fallbackArtist: artist ?? ""))
                        }
                    }
                } catch {
                    lastError = error
                }
            }
            if result.contains(where: \.isSynced) { break }
        }
        if !succeeded, let lastError { throw lastError }
        return result
    }

    /// Лучший кандидат: совпадает название/артист; среди синхронизированных — ближайший по длительности
    /// в пределах допуска. Синхронный текст другой длительности (live, ремикс) не берётся — тайминги разъедутся.
    static func pickBest(_ candidates: [LyricsCandidate], duration: TimeInterval, wantedTitle: String, wantedArtist: String?) -> LyricsCandidate? {
        let relevant = candidates.filter {
            SearchQuery.matches(title: $0.trackName, artist: $0.artistName, wantedTitle: wantedTitle, wantedArtist: wantedArtist)
        }
        func distance(_ c: LyricsCandidate) -> TimeInterval {
            guard duration > 0, let d = c.duration else { return .greatestFiniteMagnitude / 2 }
            return abs(d - duration)
        }
        let synced = relevant.filter(\.isSynced).sorted { distance($0) < distance($1) }
        if let best = synced.first {
            if duration <= 0 || best.duration == nil || distance(best) <= durationTolerance { return best }
        }
        return relevant.first { $0.plainLyrics?.isEmpty == false }
    }

    private static func lyricsOvh(artist: String, title: String) async throws -> String? {
        struct Response: Decodable { let lyrics: String? }
        let path = "https://api.lyrics.ovh/v1/"
            + (artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? artist) + "/"
            + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)
        guard let url = URL(string: path) else { return nil }
        let (data, status) = try await HTTP.get(url, timeout: 10)
        guard status == 200 else { return nil }
        let lyrics = try JSONDecoder().decode(Response.self, from: data).lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
        return lyrics?.isEmpty == false ? lyrics : nil
    }

    private static func makeCandidate(_ record: LRCLibRecord, fallbackTitle: String, fallbackArtist: String) -> LyricsCandidate {
        LyricsCandidate(
            source: "LRCLIB",
            trackName: record.trackName ?? fallbackTitle,
            artistName: record.artistName ?? fallbackArtist,
            albumName: record.albumName,
            duration: record.duration,
            plainLyrics: record.plainLyrics?.nilIfEmpty,
            syncedLyrics: record.syncedLyrics?.nilIfEmpty
        )
    }
}

/// Парсер LRC: `[01:23.45]Текст строки`, поддерживает несколько таймкодов на строке,
/// тег `[offset:±мс]` и пропускает метатеги вида `[ar: ...]`.
enum LRCParser {
    static func parse(_ raw: String?) -> [LyricLine] {
        guard let raw, !raw.isEmpty else { return [] }
        var lines: [LyricLine] = []
        var offset: TimeInterval = 0

        for rawLine in raw.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))

            if rest.lowercased().hasPrefix("[offset:"), let close = rest.firstIndex(of: "]") {
                let value = rest[rest.index(rest.startIndex, offsetBy: 8)..<close].trimmingCharacters(in: .whitespaces)
                offset = (Double(value) ?? 0) / 1000
                continue
            }

            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = parseTimestamp(tag) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }

            // Расширенный LRC: убираем пословные метки <00:12.34>
            let text = stripWordTimestamps(String(rest)).trimmingCharacters(in: .whitespaces)
            for time in times {
                lines.append(LyricLine(time: max(0, time - offset), text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss:xx" (сотые через двоеточие), "h:mm:ss.xx"
    private static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.count {
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let a = Double(parts[0]), let b = Double(parts[1]), let c = Double(parts[2]) else { return nil }
            if parts[2].contains(".") { return a * 3600 + b * 60 + c }
            return a * 60 + b + c / pow(10, Double(parts[2].count))
        default:
            return nil
        }
    }

    private static func stripWordTimestamps(_ text: String) -> String {
        guard text.contains("<") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "<\\d{1,2}:\\d{2}(?:[.:]\\d{1,3})?>") else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
}
