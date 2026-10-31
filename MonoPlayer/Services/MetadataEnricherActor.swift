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

    @MainActor
    init(_ track: Track) {
        id = track.id
        audioURL = track.audioURL
        title = track.title
        artist = track.hasKnownArtist ? track.artist : nil
        album = track.album
        duration = track.duration
        hasArtwork = track.artworkFileName != nil
    }
}

/// Результат пайплайна. `nil` — поле не меняется.
struct EnrichmentResult: Sendable {
    var title: String?
    var artist: String?
    var album: String?
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
        var networkFailures = 0

        // Шаг 2: встроенные теги
        let local = await FileImportService.readLocalMetadata(from: input.audioURL)
        if let value = local.title { title = value; result.title = value }
        if let value = local.artist { artist = value; result.artist = value }
        if let value = local.album { album = value; result.album = value }
        if let value = local.duration { duration = value; result.duration = value }
        if !input.hasArtwork { artworkData = local.artworkData }

        // Шаг 3: канонические метаданные и HD-обложка из iTunes
        do {
            let results = try await ITunesSearchService.search(artist: artist, title: title)
            if let hit = ITunesSearchService.bestMatch(in: results, artist: artist, title: title) {
                if local.title == nil, let value = hit.trackName { title = value; result.title = value }
                if artist == nil, let value = hit.artistName { artist = value; result.artist = value }
                if album == nil, let value = hit.collectionName { album = value; result.album = value }
                if artworkData == nil, !input.hasArtwork, let url = hit.hdArtworkURL {
                    artworkData = try? await ITunesSearchService.downloadData(from: url)
                }
            }
        } catch {
            networkFailures += 1
        }

        if let artworkData {
            let fileName = "\(input.id.uuidString).jpg"
            do {
                try artworkData.write(to: Storage.artworkURL(fileName), options: .atomic)
                result.artworkFileName = fileName
                result.paletteHex = ArtworkPalette.extractHex(from: artworkData)
            } catch {
                print("Artwork save failed: \(error)")
            }
        }

        // Шаг 4: текст песни
        var lyricsFound = false
        do {
            if let lyrics = try await LyricsService.fetch(artist: artist, title: title, album: album, duration: duration) {
                result.plainLyrics = lyrics.plainLyrics?.nilIfEmpty
                result.syncedLyricsRaw = lyrics.syncedLyrics?.nilIfEmpty
                lyricsFound = lyrics.hasLyrics
            }
        } catch {
            networkFailures += 1
        }

        // Шаг 5: статус
        let hasArtwork = input.hasArtwork || result.artworkFileName != nil
        if networkFailures == 2 && !hasArtwork {
            result.status = .failed
        } else {
            result.status = (hasArtwork && lyricsFound) ? .completed : .partial
        }
        return result
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

    /// Повторное обогащение (например, после ручного изменения названия).
    func refresh(_ track: Track, resetArtwork: Bool = false) {
        if resetArtwork, let url = track.artworkURL {
            try? FileManager.default.removeItem(at: url)
            track.artworkFileName = nil
            track.paletteHex = nil
        }
        enqueue([track])
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
        if let value = result.title { track.title = value }
        if let value = result.artist { track.artist = value }
        if let value = result.album { track.album = value }
        if let value = result.duration { track.duration = value }
        if let value = result.artworkFileName { track.artworkFileName = value }
        if let value = result.paletteHex { track.paletteHex = value }
        if let value = result.plainLyrics { track.plainLyrics = value }
        if let value = result.syncedLyricsRaw { track.syncedLyricsRaw = value }
        track.enrichmentStatus = result.status
    }
}
