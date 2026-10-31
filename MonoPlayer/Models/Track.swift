import Foundation
import SwiftData
import SwiftUI

enum EnrichmentStatus: String, Codable {
    case pending
    case enriching
    case completed
    case partial
    case failed
}

@Model
final class Track {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var album: String?
    /// Исполнитель альбома (тег TPE2/aART или вручную); без него определяется по трекам альбома
    var albumArtist: String?
    var duration: TimeInterval

    // Относительные пути внутри контейнера приложения
    var audioFileName: String
    var artworkFileName: String?

    // Тексты песен
    var plainLyrics: String?
    var syncedLyricsRaw: String? // Исходный LRC формат
    /// Ручная подстройка синхронизации: > 0 — строки подсвечиваются раньше
    var lyricsOffset: TimeInterval = 0
    /// Текст выбран или написан вручную — автопоиск его больше не заменяет
    var lyricsLocked: Bool = false

    // Доминантные цвета обложки ("RRGGBB,RRGGBB,RRGGBB") для фона Now Playing
    var paletteHex: String?

    /// Пользователь правил название/артиста/альбом вручную — автопоиск их больше не перезаписывает
    var metadataLocked: Bool = false

    // Любимые
    var isFavorite: Bool = false
    var favoritedAt: Date?

    // Системные поля
    var dateAdded: Date
    var enrichmentStatus: EnrichmentStatus

    init(title: String, artist: String = Track.unknownArtist, duration: TimeInterval = 0, audioFileName: String) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.duration = duration
        self.audioFileName = audioFileName
        self.dateAdded = Date()
        self.enrichmentStatus = .pending
    }

    static let unknownArtist = "Неизвестный артист"
}

extension Track {
    var audioURL: URL { Storage.trackURL(audioFileName) }

    var artworkURL: URL? { artworkFileName.map(Storage.artworkURL) }

    var hasKnownArtist: Bool { artist != Track.unknownArtist && !artist.isEmpty }

    var palette: [Color] { ArtworkPalette.colors(fromHex: paletteHex) }

    var isEnriching: Bool { enrichmentStatus == .pending || enrichmentStatus == .enriching }

    var hasLyrics: Bool { syncedLyricsRaw != nil || plainLyrics != nil }

    func toggleFavorite() {
        isFavorite.toggle()
        favoritedAt = isFavorite ? Date() : nil
        try? modelContext?.save()
    }

    /// Основной артист без «feat. …» — для поисковых запросов.
    var primaryArtist: String { SearchQuery.primaryArtist(artist) }

    /// Все исполнители трека: "rocket, lildrughill" → ["rocket", "lildrughill"].
    var artists: [String] { hasKnownArtist ? SearchQuery.splitArtists(artist) : [] }

    /// Нормализованные ключи исполнителей (включая исполнителя альбома) — для группировки.
    var artistKeys: Set<String> {
        var keys = Set(artists.map(ArtistSummary.key(for:)))
        if let albumArtist, !albumArtist.isEmpty { keys.insert(ArtistSummary.key(for: albumArtist)) }
        return keys
    }

    /// Подсказка для перехода к альбому; точный альбом находит LibraryIndex по названию и общему исполнителю.
    var albumKey: AlbumKey? {
        guard let album, !album.isEmpty else { return nil }
        return AlbumKey(title: album, artist: albumArtist?.nilIfEmpty ?? artists.first ?? artist)
    }
}
