import Foundation

/// Песня из поиска Genius.
struct GeniusSong: Sendable, Hashable {
    let id: Int
    let title: String
    /// Основной исполнитель — для записи в трек.
    let artist: String
    /// Все исполнители вместе с feat. — для сравнения с искомым артистом.
    let artistNames: String
    let url: URL
    let songArtURL: URL?
    let instrumental: Bool
}

/// Genius (https://genius.com): метаданные, обложка и текст песни.
/// Используются открытые эндпоинты сайта — ключ не нужен. Текста в API нет, он берётся со страницы песни.
enum GeniusService {
    private struct SearchResponse: Decodable {
        struct Section: Decodable { let hits: [Hit]? }
        struct Hit: Decodable { let result: Song }
        struct Song: Decodable {
            struct Artist: Decodable { let name: String }
            let id: Int
            let title: String
            let url: String
            let artist_names: String?
            let primary_artist_names: String?
            let primary_artist: Artist?
            let song_art_image_url: String?
            let instrumental: Bool?
        }
        struct Body: Decodable { let sections: [Section]? }
        let response: Body
    }

    private struct SongResponse: Decodable {
        struct Album: Decodable { let name: String?; let cover_art_url: String? }
        struct Song: Decodable { let album: Album?; let song_art_image_url: String? }
        struct Body: Decodable { let song: Song }
        let response: Body
    }

    // MARK: - Поиск

    static func search(artist: String?, title: String) async throws -> [GeniusSong] {
        let query = [artist, title].compactMap { $0 }.joined(separator: " ")
        guard let url = HTTP.url("https://genius.com/api/search/song", [("q", query), ("per_page", "5")]) else { return [] }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let sections = try JSONDecoder().decode(SearchResponse.self, from: data).response.sections ?? []
        return sections.flatMap { $0.hits ?? [] }.compactMap { hit in
            let song = hit.result
            let artist = song.primary_artist_names ?? song.primary_artist?.name ?? ""
            // Страницы-переводы («Genius Russian Translations» и т.п.) — не оригинал
            guard let url = URL(string: song.url), !artist.hasPrefix("Genius ") else { return nil }
            return GeniusSong(
                id: song.id,
                title: cleanName(song.title),
                artist: cleanName(artist),
                artistNames: song.artist_names ?? artist,
                url: url,
                songArtURL: artworkURL(song.song_art_image_url),
                instrumental: song.instrumental ?? false
            )
        }
    }

    /// Автопоиск: первое совпадение по нескольким вариантам названия.
    /// `allFailed` — ни один запрос не дошёл до Genius (нет сети).
    static func bestMatch(artist: String?, title: String) async -> (song: GeniusSong?, allFailed: Bool) {
        var attempts = 0, failures = 0
        for variant in SearchQuery.titleVariants(title).prefix(3) {
            attempts += 1
            do {
                let songs = try await search(artist: artist, title: variant)
                if let found = songs.first(where: { matches($0, artist: artist, title: title) }) {
                    return (found, false)
                }
            } catch {
                failures += 1
            }
        }
        return (nil, attempts > 0 && failures == attempts)
    }

    static func matches(_ song: GeniusSong, artist: String?, title: String) -> Bool {
        SearchQuery.matches(title: song.title, artist: song.artistNames, wantedTitle: title, wantedArtist: artist)
    }

    /// Альбом и обложка альбома (её нет в поиске — нужен отдельный запрос).
    static func details(of song: GeniusSong) async throws -> (album: String?, artworkURL: URL?) {
        guard let url = URL(string: "https://genius.com/api/songs/\(song.id)") else { return (nil, song.songArtURL) }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let details = try JSONDecoder().decode(SongResponse.self, from: data).response.song
        let artwork = artworkURL(details.album?.cover_art_url) ?? artworkURL(details.song_art_image_url) ?? song.songArtURL
        let album = details.album?.name.map { cleanName($0) } ?? ""
        return (album.isEmpty ? nil : album, artwork)
    }

    /// Ручной выбор: найденные песни с альбомом и обложкой.
    static func candidates(artist: String?, title: String) async -> [MetadataCandidate] {
        var songs = (try? await search(artist: artist, title: title)) ?? []
        if songs.isEmpty, artist != nil {
            songs = (try? await search(artist: nil, title: title)) ?? []
        }
        return await withTaskGroup(of: (Int, MetadataCandidate).self) { group in
            for (index, song) in songs.enumerated() {
                group.addTask {
                    let info = try? await GeniusService.details(of: song)
                    return (index, MetadataCandidate(
                        source: .genius, title: song.title, artist: song.artist,
                        album: info?.album, artworkURL: info?.artworkURL ?? song.songArtURL, duration: nil
                    ))
                }
            }
            var result: [(Int, MetadataCandidate)] = []
            for await item in group { result.append(item) }
            return result.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Текст

    /// Обычный текст со страницы песни. `nil` — у песни нет текста.
    static func lyrics(of song: GeniusSong) async throws -> String? {
        guard !song.instrumental else { return nil }
        let data = try await HTTP.download(song.url, accept: "text/html")
        return extractLyrics(fromHTML: String(decoding: data, as: UTF8.self))
    }

    /// Текст из блоков `data-lyrics-container`: без служебных вставок, разметки секций «[Припев]» и HTML.
    static func extractLyrics(fromHTML html: String) -> String? {
        let page = html as NSString
        var blocks: [String] = []
        var position = 0
        while position < page.length {
            let marker = page.range(of: "data-lyrics-container=\"true\"", range: NSRange(location: position, length: page.length - position))
            guard marker.location != NSNotFound,
                  let element = element(containing: marker.location, in: page) else { break }
            blocks.append(removingExcluded(from: element.content))
            position = element.end
        }

        var text = blocks.joined(separator: "\n")
        text = replace(text, pattern: "<br\\s*/?>", with: "\n")
        text = replace(text, pattern: "<[^>]+>", with: "")
        text = decodeEntities(text)

        let lines = text.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]") ? "" : trimmed
        }
        let result = replace(lines.joined(separator: "\n"), pattern: "\\n{3,}", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Элемент, в открывающем теге которого стоит `index`: его содержимое и позиция сразу после закрывающего тега.
    private static func element(containing index: Int, in text: NSString) -> (content: String, start: Int, end: Int)? {
        let open = text.range(of: "<", options: .backwards, range: NSRange(location: 0, length: index))
        let openEnd = text.range(of: ">", range: NSRange(location: index, length: text.length - index))
        guard open.location != NSNotFound, openEnd.location != NSNotFound else { return nil }

        let nameStart = open.location + 1
        var nameEnd = nameStart
        while nameEnd < text.length, let scalar = UnicodeScalar(text.character(at: nameEnd)),
              CharacterSet.alphanumerics.contains(scalar) {
            nameEnd += 1
        }
        let name = text.substring(with: NSRange(location: nameStart, length: nameEnd - nameStart))
        guard !name.isEmpty,
              let tag = try? NSRegularExpression(pattern: "<(/?)\(name)\\b[^>]*?(/?)>", options: [.caseInsensitive]) else { return nil }

        // Ищем парный закрывающий тег с учётом вложенных элементов того же типа
        var depth = 0
        var close: NSRange?
        tag.enumerateMatches(in: text as String, range: NSRange(location: open.location, length: text.length - open.location)) { match, _, stop in
            guard let match else { return }
            if match.range(at: 1).length > 0 {
                depth -= 1
            } else if match.range(at: 2).length == 0 {
                depth += 1
            }
            if depth == 0 {
                close = match.range
                stop.pointee = true
            }
        }
        let contentStart = openEnd.location + 1
        let closeStart = close?.location ?? text.length
        let end = close.map { $0.location + $0.length } ?? text.length
        guard closeStart >= contentStart else { return nil }
        return (text.substring(with: NSRange(location: contentStart, length: closeStart - contentStart)), open.location, end)
    }

    /// Убирает вложенные элементы с `data-exclude-from-selection` (шапка, реклама, кнопки).
    private static func removingExcluded(from html: String) -> String {
        var text = html as NSString
        while true {
            let marker = text.range(of: "data-exclude-from-selection=\"true\"")
            guard marker.location != NSNotFound,
                  let element = element(containing: marker.location, in: text) else { break }
            text = text.replacingCharacters(in: NSRange(location: element.start, length: element.end - element.start), with: "") as NSString
        }
        return text as String
    }

    // MARK: - Название

    /// Пометки версии трека, которые нельзя терять при замене названия.
    private static let versionKeywords = [
        "remix", "rmx", "mix", "live", "acoustic", "unplugged", "slowed", "sped up", "speed up", "reverb",
        "nightcore", "instrumental", "karaoke", "acapella", "a cappella", "cover", "demo", "edit", "version",
        "extended", "bass boosted", "ремикс", "лайв", "акустика", "версия", "кавер", "инструментал",
    ]

    /// Название трека для записи: с Genius, без мусора из тегов («(Official Video)», «[Free DL]», «prod. by …»).
    /// Пометки версии из тегов («(Slowed + Reverb)», «- Remix») сохраняются, если у Genius их нет.
    /// Если Genius-название длиннее и не входит в теговое («Love» → «Love Story») — остаётся теговое.
    static func preferredTitle(genius: String, tagged: String) -> String {
        let geniusBase = SearchQuery.normalize(SearchQuery.titleVariants(genius).last ?? genius)
        guard !geniusBase.isEmpty, SearchQuery.normalize(tagged).contains(geniusBase) else { return tagged }

        let geniusNormalized = SearchQuery.normalize(genius)
        var result = genius
        for marker in versionMarkers(in: tagged) where !geniusNormalized.contains(SearchQuery.normalize(marker)) {
            result += " (\(marker))"
        }
        return result
    }

    /// "Song (Slowed + Reverb) [Free DL] - Live" → ["Slowed + Reverb", "Live"]
    private static func versionMarkers(in title: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\(([^)]*)\\)|\\[([^\\]]*)\\]|\\s[-–—]\\s+([^()\\[\\]]+)$") else { return [] }
        let source = title as NSString
        return regex.matches(in: title, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let group = (1...3).map { match.range(at: $0) }.first { $0.location != NSNotFound }
            guard let group else { return nil }
            let text = source.substring(with: group).trimmingCharacters(in: .whitespaces)
            let lower = text.lowercased()
            return versionKeywords.contains { lower.contains($0) } ? text : nil
        }
    }

    // MARK: - Вспомогательное

    /// "Группа крови (Blood Type)" → "Группа крови", "Кино (KINO)" → "Кино":
    /// Genius дописывает латинскую транслитерацию к нелатинским названиям.
    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.range(of: " (", options: .backwards) else { return trimmed }
        let main = trimmed[..<open.lowerBound]
        let suffix = trimmed[open.upperBound...].dropLast()
        let mainIsNonLatin = main.unicodeScalars.contains { $0.properties.isAlphabetic && !$0.isASCII }
        let suffixIsLatin = !suffix.isEmpty && suffix.unicodeScalars.allSatisfy(\.isASCII)
        let isFeaturing = suffix.lowercased().hasPrefix("ft.") || suffix.lowercased().hasPrefix("feat")
        return mainIsNonLatin && suffixIsLatin && !isFeaturing ? String(main) : trimmed
    }

    /// Ссылка на картинку, кроме заглушки Genius «нет обложки».
    private static func artworkURL(_ string: String?) -> URL? {
        guard let string, !string.contains("default_cover_image") else { return nil }
        return URL(string: string)
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    ]

    /// `&amp;`, `&#39;`, `&#x27;` → символы.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"),
              let regex = try? NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);") else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let entity = source.substring(with: match.range(at: 1))
            var replacement: String?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                replacement = UInt32(entity.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else if entity.hasPrefix("#") {
                replacement = UInt32(entity.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
            } else {
                replacement = namedEntities[entity]
            }
            result += replacement ?? source.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result += source.substring(from: last)
        return result
    }
}
