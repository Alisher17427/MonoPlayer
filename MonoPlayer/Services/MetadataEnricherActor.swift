import Foundation
import Observation
import SwiftData

/// Снимок трека, который безопасно передать в актор.
struct EnrichmentInput: Sendable {
    let id: UUID
    let audioURL: URL
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let hasArtwork: Bool
    let hasSyncedLyrics: Bool
    let metadataLocked: Bool

    @MainActor
    init(_ track: Track) {
        id = track.id
        audioURL = track.audioURL
        title = track.title
        artist = track.hasKnownArtist ? track.artist : nil
        album = track.album
        duration = track.duration
        hasArtwork = track.artworkFileName != nil
        hasSyncedLyrics = track.syncedLyricsRaw != nil
        metadataLocked = track.metadataLocked
    }
}

/// Результат пайплайна. `nil` — поле не меняется.
struct EnrichmentResult: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var duration: TimeInterval?
    var artworkFileName: String?
    var paletteHex: String?
    var plainLyrics: String?
    var syncedLyricsRaw: String?
    var status: EnrichmentStatus = .partial
}

/// Изолированный актор пайплайна обогащения (шаги 2–4).
/// Не трогает SwiftData — только сеть и файлы; результат применяется на главном акторе.
actor MetadataEnricherActor {
    func enrich(_ input: EnrichmentInput) async -> EnrichmentResult {
        var result = EnrichmentResult()
        var title = input.title
        var artist = input.artist
        var album = input.album
        var duration = input.duration
        var artworkData: Data?
        let locked = input.metadataLocked

        // Шаг 2: встроенные теги. Ручные правки пользователя важнее тегов.
        let local = await FileImportService.readLocalMetadata(from: input.audioURL)
        if !locked {
            if let value = local.title { title = value; result.title = value }
            if let value = local.artist { artist = value; result.artist = value }
            if let value = local.album { album = value; result.album = value }
            if let value = local.albumArtist { result.albumArtist = value }
        }
        if let value = local.duration { duration = value; result.duration = value }
        if !input.hasArtwork { artworkData = local.artworkData }

        // В запросах — первый исполнитель: «rocket, lildrughill» ищем как «rocket»
        var queryArtist: String? { artist.flatMap { SearchQuery.splitArtists($0).first } ?? artist }

        // Шаг 3: метаданные и обложка — iTunes → Deezer → MusicBrainz/Cover Art Archive
        let search = await MetadataSearch.bestMatch(artist: queryArtist, title: title)
        if let match = search.match, !locked {
            if local.title == nil { title = match.title; result.title = match.title }
            if artist == nil, !match.artist.isEmpty { artist = match.artist; result.artist = match.artist }
            if album == nil, let value = match.album { album = value; result.album = value }
        }
        if artworkData == nil, !input.hasArtwork, let url = search.artworkURL {
            artworkData = try? await ITunesSearchService.downloadData(from: url)
        }

        if let artworkData {
            result.artworkFileName = Self.saveArtwork(artworkData, id: input.id)
            if result.artworkFileName != nil { result.paletteHex = ArtworkPalette.extractHex(from: artworkData) }
        }

        // Шаг 4: текст песни (синхронный текст уже есть — не трогаем)
        var lyricsFound = input.hasSyncedLyrics
        var lyricsFailed = false
        if !input.hasSyncedLyrics {
            do {
                if let lyrics = try await LyricsService.find(artist: queryArtist, title: title, album: album, duration: duration) {
                    result.plainLyrics = lyrics.plainLyrics
                    result.syncedLyricsRaw = lyrics.syncedLyrics
                    lyricsFound = true
                }
            } catch {
                lyricsFailed = true
            }
        }

        // Шаг 5: статус
        let hasArtwork = input.hasArtwork || result.artworkFileName != nil
        if search.allFailed && lyricsFailed && !hasArtwork {
            result.status = .failed
        } else {
            result.status = (hasArtwork && lyricsFound) ? .completed : .partial
        }
        return result
    }

    static func saveArtwork(_ data: Data, id: UUID) -> String? {
        // Новое имя при каждой замене — чтобы кэш картинок не показывал старую обложку
        let fileName = "\(id.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try data.write(to: Storage.artworkURL(fileName), options: .atomic)
            return fileName
        } catch {
            print("Artwork save failed: \(error)")
            return nil
        }
    }
}

/// Очередь обогащения на главном акторе: берёт треки по одному, отдаёт актору снимок
/// и применяет результат к модели в основном ModelContext.
@MainActor
@Observable
final class EnrichmentCoordinator {
    @ObservationIgnored private let enricher = MetadataEnricherActor()
    @ObservationIgnored private var queue: [Track] = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var context: ModelContext?

    /// Вызывается при старте: подхватывает треки, обогащение которых было прервано.
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        let descriptor = FetchDescriptor<Track>(sortBy: [SortDescriptor(\.dateAdded)])
        let unfinished = ((try? context.fetch(descriptor)) ?? []).filter(\.isEnriching)
        enqueue(unfinished)
    }

    func enqueue(_ tracks: [Track]) {
        for track in tracks where !queue.contains(where: { $0.id == track.id }) {
            track.enrichmentStatus = .enriching
            queue.append(track)
        }
        runIfNeeded()
    }

    /// Повторный автопоиск. `resetArtwork` / `resetLyrics` — искать заново, даже если уже есть.
    func refresh(_ track: Track, resetArtwork: Bool = false, resetLyrics: Bool = false) {
        if resetArtwork { removeArtwork(of: track) }
        if resetLyrics {
            track.plainLyrics = nil
            track.syncedLyricsRaw = nil
            track.lyricsOffset = 0
        }
        enqueue([track])
    }

    /// Ручной выбор обложки из кандидатов.
    func applyArtwork(from url: URL, to track: Track) async -> Bool {
        guard let data = try? await ITunesSearchService.downloadData(from: url),
              let fileName = MetadataEnricherActor.saveArtwork(data, id: track.id) else { return false }
        guard !track.isDeleted else { return false }
        removeArtwork(of: track)
        track.artworkFileName = fileName
        track.paletteHex = ArtworkPalette.extractHex(from: data)
        try? context?.save()
        return true
    }

    /// Ручной выбор текста из кандидатов.
    func applyLyrics(_ candidate: LyricsCandidate, to track: Track) {
        track.syncedLyricsRaw = candidate.syncedLyrics
        track.plainLyrics = candidate.plainLyrics
        track.lyricsOffset = 0
        if track.artworkFileName != nil { track.enrichmentStatus = .completed }
        try? context?.save()
    }

    private func removeArtwork(of track: Track) {
        if let url = track.artworkURL { try? FileManager.default.removeItem(at: url) }
        track.artworkFileName = nil
        track.paletteHex = nil
    }

    private func runIfNeeded() {
        guard !isRunning, !queue.isEmpty else { return }
        isRunning = true
        Task {
            while !queue.isEmpty {
                let track = queue.removeFirst()
                guard !track.isDeleted, track.modelContext != nil else { continue }
                let result = await enricher.enrich(EnrichmentInput(track))
                guard !track.isDeleted, track.modelContext != nil else { continue }
                apply(result, to: track)
                try? context?.save()
            }
            isRunning = false
        }
    }

    private func apply(_ result: EnrichmentResult, to track: Track) {
        if !track.metadataLocked {
            if let value = result.title { track.title = value }
            if let value = result.artist { track.artist = value }
            if let value = result.album { track.album = value }
            if let value = result.albumArtist { track.albumArtist = value }
        }
        if let value = result.duration { track.duration = value }
        if let value = result.artworkFileName, track.artworkFileName == nil { track.artworkFileName = value }
        if let value = result.paletteHex, track.paletteHex == nil { track.paletteHex = value }
        if result.plainLyrics != nil || result.syncedLyricsRaw != nil {
            track.plainLyrics = result.plainLyrics
            track.syncedLyricsRaw = result.syncedLyricsRaw
        }
        track.enrichmentStatus = result.status
    }
}
