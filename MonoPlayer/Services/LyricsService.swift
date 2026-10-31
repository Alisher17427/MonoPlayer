import Foundation

struct LRCLibLyrics: Decodable, Sendable {
    let plainLyrics: String?
    let syncedLyrics: String?
    let instrumental: Bool?

    var hasLyrics: Bool { syncedLyrics?.isEmpty == false || plainLyrics?.isEmpty == false }
}

/// Интеграция с LRCLIB (https://lrclib.net).
enum LyricsService {
    static func fetch(artist: String?, title: String, album: String?, duration: TimeInterval) async throws -> LRCLibLyrics? {
        if let artist {
            var components = URLComponents(string: "https://lrclib.net/api/get")!
            var items = [
                URLQueryItem(name: "artist_name", value: artist),
                URLQueryItem(name: "track_name", value: title),
            ]
            if let album { items.append(URLQueryItem(name: "album_name", value: album)) }
            if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
            components.queryItems = items

            let (data, status) = try await request(components.url!)
            if status == 200, let lyrics = try? JSONDecoder().decode(LRCLibLyrics.self, from: data), lyrics.hasLyrics {
                return lyrics
            }
        }

        // Фоллбэк: полнотекстовый поиск
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "q", value: [artist, title].compactMap { $0 }.joined(separator: " "))]
        let (data, status) = try await request(search.url!)
        guard status == 200 else { return nil }
        let results = (try? JSONDecoder().decode([LRCLibLyrics].self, from: data)) ?? []
        return results.first { $0.syncedLyrics?.isEmpty == false } ?? results.first { $0.hasLyrics }
    }

    private static func request(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.setValue("MonoPlayer/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Парсер LRC: `[01:23.45]Текст строки`, поддерживает несколько таймкодов на строке
/// и пропускает метатеги вида `[ar: ...]`.
enum LRCParser {
    static func parse(_ raw: String?) -> [LyricLine] {
        guard let raw, !raw.isEmpty else { return [] }
        var lines: [LyricLine] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = parseTimestamp(tag) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }

            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                lines.append(LyricLine(time: time, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss:xx"
    private static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let minutes = Double(parts[0]) else { return nil }
        let secondsPart = parts[1].replacingOccurrences(of: ":", with: ".")
        guard let seconds = Double(secondsPart) else { return nil }
        return minutes * 60 + seconds
    }
}
