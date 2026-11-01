import Foundation
import Observation

/// Музыкальный клип из каталога iTunes (без ключей API). Смотрим — на YouTube.
struct MusicVideo: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let title: String
    let artist: String
    let thumbnailURL: URL?
    let releaseYear: String?
    let appleURL: URL?

    var youTubeURL: URL { YouTubeLink.search(artist: artist, title: title) }
}

enum YouTubeLink {
    /// Поиск клипа на YouTube. Ссылка https открывает приложение YouTube, если оно установлено.
    static func search(artist: String, title: String) -> URL {
        let cleanTitle = SearchQuery.titleVariants(title).last ?? title
        // Имя в кавычках — YouTube не подменит артиста похожим («FACE» ≠ «Babyface»)
        let query = "\"\(SearchQuery.primaryArtist(artist))\" \(cleanTitle) official video"
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }
}

/// Клипы ищутся по ID артиста в каталоге, а не по подстроке имени:
/// иначе к «FACE» подмешивались Babyface и «Poker Face». Если одноимённых артистов
/// несколько (рэпер FACE и рок-группа FACE), выбираем того, чьи песни есть в медиатеке.
enum VideoService {
    struct Item: Decodable {
        let wrapperType: String?
        let kind: String?
        let artistId: Int?
        let trackId: Int?
        let trackName: String?
        let artistName: String?
        let artworkUrl100: String?
        let releaseDate: String?
        let trackViewUrl: String?
    }

    private struct Response: Decodable { let results: [Item] }

    static func videos(forArtist artist: String, knownTitles: [String]) async throws -> [MusicVideo] {
        let candidates = try await artistCandidates(named: artist)
        guard !candidates.isEmpty else { return [] }

        var artistID = candidates[0].artistId
        if candidates.count > 1 {
            let ids = candidates.compactMap(\.artistId).map(String.init).joined(separator: ",")
            let songs = try await fetch([("id", ids), ("entity", "song"), ("limit", "50")])
            artistID = bestArtistID(candidates: candidates, songs: songs, knownTitles: knownTitles)
        }
        guard let artistID else { return [] }

        let items = try await fetch([("id", String(artistID)), ("entity", "musicVideo"), ("limit", "50")])
        return musicVideos(from: items)
    }

    /// Артисты каталога с точно таким же именем (без учёта регистра и знаков), в порядке релевантности.
    static func artistCandidates(named artist: String) async throws -> [Item] {
        let wanted = SearchQuery.normalize(artist)
        guard !wanted.isEmpty else { return [] }
        let items = try await fetch([
            ("term", artist), ("entity", "musicArtist"), ("attribute", "artistTerm"), ("limit", "15"),
        ], endpoint: "search")
        return Array(items.filter { $0.artistId != nil && SearchQuery.normalize($0.artistName ?? "") == wanted }.prefix(8))
    }

    /// Выбор среди одноимённых: больше всего совпадений песен с медиатекой; при равенстве — порядок каталога.
    static func bestArtistID(candidates: [Item], songs: [Item], knownTitles: [String]) -> Int? {
        let known = Set(knownTitles.map(cleanKey).filter { !$0.isEmpty })
        var scores: [Int: Int] = [:]
        for song in songs where song.wrapperType == "track" {
            guard let id = song.artistId, let title = song.trackName, known.contains(cleanKey(title)) else { continue }
            scores[id, default: 0] += 1
        }
        let ids = candidates.compactMap(\.artistId)
        let best = ids.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) }
        guard let best, (scores[best] ?? 0) > 0 else { return ids.first }
        // max(by:) при равенстве берёт последний — возвращаем первый с лучшим счётом
        return ids.first { scores[$0] == scores[best] }
    }

    static func musicVideos(from items: [Item]) -> [MusicVideo] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard item.wrapperType == "track", item.kind == "music-video",
                  let id = item.trackId, let title = item.trackName, let name = item.artistName else { return nil }
            // Убираем дубли (одно видео в нескольких регионах/версиях)
            guard seen.insert(cleanKey(title)).inserted else { return nil }
            return MusicVideo(
                id: id, title: title, artist: name,
                thumbnailURL: item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "640x360bb")) },
                releaseYear: item.releaseDate.map { String($0.prefix(4)) },
                appleURL: item.trackViewUrl.flatMap(URL.init(string:))
            )
        }
    }

    private static func cleanKey(_ title: String) -> String {
        SearchQuery.normalize(SearchQuery.titleVariants(title).last ?? title)
    }

    /// Каталог US (по умолчанию): в российском клипов почти нет.
    private static func fetch(_ items: [(String, String?)], endpoint: String = "lookup") async throws -> [Item] {
        guard let url = HTTP.url("https://itunes.apple.com/\(endpoint)", items) else { return [] }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Response.self, from: data).results
    }
}

/// Кэш клипов и фото артистов: в памяти и на диске (Caches), чтобы не упираться в лимиты API.
@MainActor
@Observable
final class ArtistMediaStore {
    private(set) var videos: [String: [MusicVideo]] = [:]
    private(set) var pictures: [String: URL] = [:]
    @ObservationIgnored private var loadingVideos: Set<String> = []
    @ObservationIgnored private var loadingPictures: Set<String> = []
    @ObservationIgnored private var missingPictures: Set<String> = []

    private static let directory = URL.cachesDirectory.appending(path: "ArtistMedia", directoryHint: .isDirectory)
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    func isLoadingVideos(for artist: String) -> Bool { loadingVideos.contains(key(artist)) }

    /// `knownTitles` — песни артиста из медиатеки: по ним выбирается нужный из одноимённых артистов.
    func loadVideos(for artist: String, knownTitles: [String] = []) async {
        let key = key(artist)
        guard videos[key] == nil, !loadingVideos.contains(key) else { return }
        // v2: старый кэш содержал чужие клипы (поиск по подстроке имени)
        let file = Self.directory.appending(path: "videos-v2-\(Self.fileSafe(key)).json")

        if let cached = Self.readFresh(file), let list = try? JSONDecoder().decode([MusicVideo].self, from: cached) {
            videos[key] = list
            return
        }
        loadingVideos.insert(key)
        defer { loadingVideos.remove(key) }
        if let list = try? await VideoService.videos(forArtist: artist, knownTitles: knownTitles) {
            videos[key] = list
            Self.write(try? JSONEncoder().encode(list), to: file)
        } else {
            videos[key] = []
        }
    }

    /// Локальный файл с фото артиста (скачивается один раз).
    func loadPicture(for artist: String) async {
        let key = key(artist)
        guard pictures[key] == nil, !loadingPictures.contains(key), !missingPictures.contains(key) else { return }
        let file = Self.directory.appending(path: "artist-\(Self.fileSafe(key)).jpg")
        if FileManager.default.fileExists(atPath: file.path()) {
            pictures[key] = file
            return
        }
        loadingPictures.insert(key)
        defer { loadingPictures.remove(key) }
        guard let remote = try? await DeezerService.artistPictureURL(name: artist),
              let data = try? await HTTP.download(remote) else {
            missingPictures.insert(key)
            return
        }
        Self.write(data, to: file)
        pictures[key] = file
    }

    func picture(for artist: String) -> URL? { pictures[key(artist)] }
    func videoList(for artist: String) -> [MusicVideo]? { videos[key(artist)] }

    private func key(_ artist: String) -> String { ArtistSummary.key(for: artist) }

    private static func fileSafe(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = text.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return String(mapped.prefix(80))
    }

    private static func readFresh(_ file: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path()),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: file)
    }

    private static func write(_ data: Data?, to file: URL) {
        guard let data else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
