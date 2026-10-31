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
        let query = "\(SearchQuery.primaryArtist(artist)) \(cleanTitle) official video"
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return components.url!
    }
}

enum VideoService {
    private struct Response: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let artworkUrl100: String?
            let releaseDate: String?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    static func videos(forArtist artist: String) async throws -> [MusicVideo] {
        guard let url = HTTP.url("https://itunes.apple.com/search", [
            ("term", artist), ("entity", "musicVideo"), ("attribute", "artistTerm"), ("limit", "30"),
        ]) else { return [] }
        let (data, status) = try await HTTP.get(url)
        guard status == 200 else { throw URLError(.badServerResponse) }
        let wanted = SearchQuery.normalize(artist)
        var seen = Set<String>()
        return try JSONDecoder().decode(Response.self, from: data).results.compactMap { item in
            guard let id = item.trackId, let title = item.trackName, let name = item.artistName else { return nil }
            let normalizedArtist = SearchQuery.normalize(name)
            guard normalizedArtist.contains(wanted) || wanted.contains(normalizedArtist) else { return nil }
            // Убираем дубли (одно видео в нескольких регионах/версиях)
            guard seen.insert(SearchQuery.normalize(SearchQuery.titleVariants(title).last ?? title)).inserted else { return nil }
            return MusicVideo(
                id: id, title: title, artist: name,
                thumbnailURL: item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "640x360bb")) },
                releaseYear: item.releaseDate.map { String($0.prefix(4)) },
                appleURL: item.trackViewUrl.flatMap(URL.init(string:))
            )
        }
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

    func loadVideos(for artist: String) async {
        let key = key(artist)
        guard videos[key] == nil, !loadingVideos.contains(key) else { return }
        let file = Self.directory.appending(path: "videos-\(Self.fileSafe(key)).json")

        if let cached = Self.readFresh(file), let list = try? JSONDecoder().decode([MusicVideo].self, from: cached) {
            videos[key] = list
            return
        }
        loadingVideos.insert(key)
        defer { loadingVideos.remove(key) }
        if let list = try? await VideoService.videos(forArtist: artist) {
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
              let data = try? await ITunesSearchService.downloadData(from: remote) else {
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
