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
    var duration: TimeInterval

    // Относительные пути внутри контейнера приложения
    var audioFileName: String
    var artworkFileName: String?

    // Тексты песен
    var plainLyrics: String?
    var syncedLyricsRaw: String? // Исходный LRC формат
    /// Ручная подстройка синхронизации: > 0 — строки подсвечиваются раньше
    var lyricsOffset: TimeInterval = 0

    // Доминантные цвета обложки ("RRGGBB,RRGGBB,RRGGBB") для фона Now Playing
    var paletteHex: String?

    /// Пользователь правил название/артиста/альбом вручную — автопоиск их больше не перезаписывает
    var metadataLocked: Bool = false

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

    /// Основной артист без «feat. …» — по нему группируются страницы артистов и альбомов.
    var primaryArtist: String { SearchQuery.primaryArtist(artist) }

    var albumKey: AlbumKey? {
        guard let album, !album.isEmpty else { return nil }
        return AlbumKey(title: album, artist: primaryArtist)
    }
}
