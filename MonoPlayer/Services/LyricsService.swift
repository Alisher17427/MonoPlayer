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

    /// Автопоиск: текст — с Genius (песня `genius` уже найдена при поиске метаданных),
    /// таймкоды — из LRCLIB, только если там есть та же версия трека (по длительности).
    /// Без Genius-текста берётся текст из найденного синхронного LRC.
    static func find(artist: String?, title: String, album: String?, duration: TimeInterval, genius: GeniusSong?) async throws -> LyricsCandidate? {
        async let synced = syncedLyrics(artist: artist, title: title, album: album, duration: duration)

        var geniusText: String?
        var geniusFailed = genius == nil
        if let genius {
            do {
                geniusText = try await GeniusService.lyrics(of: genius)
            } catch {
                geniusFailed = true
            }
        }
        let (record, lrclibReachable) = await synced

        guard geniusText != nil || record != nil else {
            if geniusFailed && !lrclibReachable { throw URLError(.notConnectedToInternet) }
            return nil
        }
        return LyricsCandidate(
            source: geniusText != nil ? "Genius" : "LRCLIB",
            trackName: genius?.title ?? record?.trackName ?? title,
            artistName: genius?.artist ?? record?.artistName ?? artist ?? "",
            albumName: record?.albumName,
            duration: record?.duration,
            plainLyrics: geniusText ?? record?.plainLyrics,
            syncedLyrics: record?.syncedLyrics
        )
    }

    /// Синхронный текст LRCLIB: точный запрос (LRCLIB сам сверяет длительность ±2 с), затем поиск с выбором по длительности.
    /// `reachable` — LRCLIB ответил хотя бы на один запрос.
    private static func syncedLyrics(artist: String?, title: String, album: String?, duration: TimeInterval) async -> (LyricsCandidate?, reachable: Bool) {
        var reachable = false
        if let artist, duration > 0 {
            for withAlbum in [true, false] where withAlbum == false || album != nil {
                guard let url = HTTP.url("https://lrclib.net/api/get", [
                    ("artist_name", artist), ("track_name", title),
                    ("album_name", withAlbum ? album : nil),
                    ("duration", String(Int(duration.rounded()))),
                ]) else { continue }
                guard let response = try? await HTTP.get(url) else { continue }
                let (data, status) = response
                reachable = true
                if status == 200, let record = try? JSONDecoder().decode(LRCLibRecord.self, from: data), record.hasSynced {
                    return (makeCandidate(record, fallbackTitle: title, fallbackArtist: artist), true)
                }
            }
        }
        if let candidates = try? await search(artist: artist, title: title) {
            reachable = true
            if let best = pickSynced(candidates, duration: duration, wantedTitle: title, wantedArtist: artist) {
                return (best, true)
            }
        }
        return (nil, reachable)
    }

    /// Ручной выбор: тексты Genius и синхронные версии LRCLIB.
    static func candidates(artist: String?, title: String) async -> [LyricsCandidate] {
        async let synced = (try? search(artist: artist, title: title)) ?? []
        let songs = Array(((try? await GeniusService.search(artist: artist, title: title)) ?? []).prefix(3))
        let genius = await withTaskGroup(of: (Int, LyricsCandidate?).self) { group in
            for (index, song) in songs.enumerated() {
                group.addTask {
                    guard let text = try? await GeniusService.lyrics(of: song) else { return (index, nil) }
                    return (index, LyricsCandidate(source: "Genius", trackName: song.title, artistName: song.artist, albumName: nil,
                                                   duration: nil, plainLyrics: text, syncedLyrics: nil))
                }
            }
            var result: [(Int, LyricsCandidate?)] = []
            for await item in group { result.append(item) }
            return result.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }
        return genius + (await synced)
    }

    /// Синхронные тексты LRCLIB по нескольким вариантам названия.
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
                    for record in records where record.hasSynced {
                        let key = "\(record.trackName ?? "")|\(record.artistName ?? "")|\(Int(record.duration ?? 0))"
                        if seen.insert(key).inserted {
                            result.append(makeCandidate(record, fallbackTitle: variant, fallbackArtist: artist ?? ""))
                        }
                    }
                } catch {
                    lastError = error
                }
            }
            if !result.isEmpty { break }
        }
        if !succeeded, let lastError { throw lastError }
        return result
    }

    /// Синхронный текст той же версии: совпадает название/артист, длительность — в пределах допуска.
    /// Текст другой длительности (live, ремикс) не берётся — тайминги разъедутся.
    static func pickSynced(_ candidates: [LyricsCandidate], duration: TimeInterval, wantedTitle: String, wantedArtist: String?) -> LyricsCandidate? {
        func distance(_ c: LyricsCandidate) -> TimeInterval {
            guard duration > 0, let d = c.duration else { return .greatestFiniteMagnitude / 2 }
            return abs(d - duration)
        }
        let best = candidates
            .filter { $0.isSynced && SearchQuery.matches(title: $0.trackName, artist: $0.artistName, wantedTitle: wantedTitle, wantedArtist: wantedArtist) }
            .min { distance($0) < distance($1) }
        guard let best else { return nil }
        return duration <= 0 || best.duration == nil || distance(best) <= durationTolerance ? best : nil
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
