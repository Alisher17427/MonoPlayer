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
    let hasLyrics: Bool
    let lyricsLocked: Bool
    let metadataLocked: Bool
    let artworkLocked: Bool
    /// Искать обложку / текст заново, даже если они уже есть (старые заменяются, только если найдены новые)
    let forceArtwork: Bool
    let forceLyrics: Bool

    @MainActor
    init(_ track: Track, forceArtwork: Bool = false, forceLyrics: Bool = false) {
        id = track.id
        audioURL = track.audioURL
        title = track.title
        artist = track.hasKnownArtist ? track.artist : nil
        album = track.album
        duration = track.duration
        hasArtwork = track.artworkFileName != nil
        hasSyncedLyrics = track.syncedLyricsRaw != nil
        hasLyrics = track.hasLyrics
        lyricsLocked = track.lyricsLocked
        metadataLocked = track.metadataLocked
        artworkLocked = track.artworkLocked
        self.forceArtwork = forceArtwork
        self.forceLyrics = forceLyrics
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
    /// Нашёлся только обычный текст — прежний синхронный остаётся
    var keepsSyncedLyrics = false
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
        // Своя обложка пользователя не заменяется; при обновлении старая остаётся, пока не найдена новая
        let wantsArtwork = !input.artworkLocked && (!input.hasArtwork || input.forceArtwork)
        if wantsArtwork { artworkData = local.artworkData }

        // В запросах — первый исполнитель: «rocket, lildrughill» ищем как «rocket»
        var queryArtist: String? { artist.flatMap { SearchQuery.splitArtists($0).first } ?? artist }

        // Шаг 3: метаданные и обложка — Genius
        let search = await GeniusService.bestMatch(artist: queryArtist, title: title)
        if let song = search.song {
            let needsAlbum = album == nil && !locked
            let needsArtwork = artworkData == nil && wantsArtwork
            var details: (album: String?, artworkURL: URL?)?
            if needsAlbum || needsArtwork { details = try? await GeniusService.details(of: song) }
            if !locked {
                // Название с Genius чище тегового: в тегах бывают «(Official Video)», «[Free DL]» и т.п.
                let cleanTitle = GeniusService.preferredTitle(genius: song.title, tagged: title)
                if cleanTitle != title { title = cleanTitle; result.title = cleanTitle }
                if artist == nil, !song.artist.isEmpty { artist = song.artist; result.artist = song.artist }
                if album == nil, let value = details?.album { album = value; result.album = value }
            }
            if needsArtwork, let url = details?.artworkURL ?? song.songArtURL {
                artworkData = try? await HTTP.download(url)
            }
        }

        if let artworkData {
            result.artworkFileName = Self.saveArtwork(artworkData, id: input.id)
            if result.artworkFileName != nil { result.paletteHex = ArtworkPalette.extractHex(from: artworkData) }
        }

        // Шаг 4: текст песни (выбранный вручную не трогаем; синхронный — только при обновлении)
        let keepsLyrics = input.lyricsLocked || (input.hasSyncedLyrics && !input.forceLyrics)
        var lyricsFound = keepsLyrics || (input.forceLyrics && input.hasLyrics)
        var lyricsFailed = false
        if !keepsLyrics {
            do {
                if let lyrics = try await LyricsService.find(artist: queryArtist, title: title, album: album, duration: duration, genius: search.song) {
                    result.plainLyrics = lyrics.plainLyrics
                    result.syncedLyricsRaw = lyrics.syncedLyrics
                    result.keepsSyncedLyrics = lyrics.syncedLyrics == nil && input.hasSyncedLyrics
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
    private struct QueueItem {
        let track: Track
        var forceArtwork: Bool
        var forceLyrics: Bool
    }

    @ObservationIgnored private let enricher = MetadataEnricherActor()
    @ObservationIgnored private var queue: [QueueItem] = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var context: ModelContext?

    /// Прогресс текущей очереди: сколько треков осталось и сколько было всего.
    private(set) var remaining = 0
    private(set) var batchTotal = 0

    /// Вызывается при старте: подхватывает треки, обогащение которых было прервано.
    func attach(_ context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        let descriptor = FetchDescriptor<Track>(sortBy: [SortDescriptor(\.dateAdded)])
        let unfinished = ((try? context.fetch(descriptor)) ?? []).filter(\.isEnriching)
        enqueue(unfinished)
    }

    func enqueue(_ tracks: [Track], forceArtwork: Bool = false, forceLyrics: Bool = false) {
        for track in tracks {
            if let index = queue.firstIndex(where: { $0.track.id == track.id }) {
                queue[index].forceArtwork = queue[index].forceArtwork || forceArtwork
                queue[index].forceLyrics = queue[index].forceLyrics || forceLyrics
                continue
            }
            track.enrichmentStatus = .enriching
            queue.append(QueueItem(track: track, forceArtwork: forceArtwork, forceLyrics: forceLyrics))
            batchTotal += 1
        }
        updateProgress()
        runIfNeeded()
    }

    /// Вся медиатека: найти заново обложки и/или тексты. Старые заменяются, только если найдены новые;
    /// поставленные вручную обложки и тексты не трогаются. Метаданные из тегов и Genius обновляются всегда.
    func refreshLibrary(_ tracks: [Track], artwork: Bool, lyrics: Bool) {
        enqueue(tracks.sorted { $0.dateAdded < $1.dateAdded }, forceArtwork: artwork, forceLyrics: lyrics)
    }

    /// Только треки без обложки или без текста. Возвращает, сколько треков поставлено в очередь.
    @discardableResult
    func fillMissing(_ tracks: [Track]) -> Int {
        let missing = tracks
            .filter { ($0.artworkFileName == nil && !$0.artworkLocked) || (!$0.hasLyrics && !$0.lyricsLocked) }
            .sorted { $0.dateAdded < $1.dateAdded }
        enqueue(missing)
        return missing.count
    }

    /// Остановить очередь: трек, который уже обрабатывается, будет доведён до конца.
    func cancelQueue() {
        for item in queue where !item.track.isDeleted {
            let track = item.track
            track.enrichmentStatus = track.artworkFileName != nil && track.hasLyrics ? .completed : .partial
        }
        queue.removeAll()
        try? context?.save()
        updateProgress()
    }

    /// Повторный автопоиск. `resetArtwork` / `resetLyrics` — искать заново, даже если уже есть.
    func refresh(_ track: Track, resetArtwork: Bool = false, resetLyrics: Bool = false) {
        if resetArtwork {
            removeArtwork(of: track)
            track.artworkLocked = false
        }
        if resetLyrics {
            track.plainLyrics = nil
            track.syncedLyricsRaw = nil
            track.lyricsOffset = 0
            track.lyricsLocked = false
        }
        enqueue([track])
    }

    /// Ручной выбор обложки из кандидатов.
    func applyArtwork(from url: URL, to track: Track) async -> Bool {
        guard let data = try? await HTTP.download(url) else { return false }
        return applyArtwork(data: data, to: track)
    }

    /// Своя обложка (из Фото или Файлов) или скачанная.
    @discardableResult
    func applyArtwork(data: Data, to track: Track) -> Bool {
        guard !track.isDeleted, let fileName = MetadataEnricherActor.saveArtwork(data, id: track.id) else { return false }
        removeArtwork(of: track)
        track.artworkFileName = fileName
        track.paletteHex = ArtworkPalette.extractHex(from: data)
        track.artworkLocked = true
        try? context?.save()
        return true
    }

    /// Ручной выбор текста из кандидатов.
    func applyLyrics(_ candidate: LyricsCandidate, to track: Track) {
        track.syncedLyricsRaw = candidate.syncedLyrics
        track.plainLyrics = candidate.plainLyrics
        track.lyricsOffset = 0
        track.lyricsLocked = true
        if track.artworkFileName != nil { track.enrichmentStatus = .completed }
        try? context?.save()
    }

    /// Свой текст: LRC с таймкодами становится синхронным, иначе — обычный текст. Пустой — убирает текст.
    func applyCustomLyrics(_ text: String, to track: Track) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = LRCParser.parse(trimmed)
        if trimmed.isEmpty {
            track.syncedLyricsRaw = nil
            track.plainLyrics = nil
        } else if lines.isEmpty {
            track.syncedLyricsRaw = nil
            track.plainLyrics = trimmed
        } else {
            track.syncedLyricsRaw = trimmed
            track.plainLyrics = lines.map(\.text).joined(separator: "\n")
        }
        track.lyricsOffset = 0
        track.lyricsLocked = true
        if track.artworkFileName != nil && track.hasLyrics { track.enrichmentStatus = .completed }
        try? context?.save()
    }

    func clearArtwork(of track: Track) {
        removeArtwork(of: track)
        track.artworkLocked = true
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
                let item = queue.removeFirst()
                let track = item.track
                inFlight = true
                defer {
                    inFlight = false
                    updateProgress()
                }
                guard !track.isDeleted, track.modelContext != nil else { continue }
                let input = EnrichmentInput(track, forceArtwork: item.forceArtwork, forceLyrics: item.forceLyrics)
                let result = await enricher.enrich(input)
                guard !track.isDeleted, track.modelContext != nil else {
                    discardArtworkFile(result.artworkFileName)
                    continue
                }
                apply(result, to: track)
                try? context?.save()
            }
            isRunning = false
        }
    }

    private func updateProgress() {
        remaining = queue.count + (inFlight ? 1 : 0)
        if remaining == 0 { batchTotal = 0 }
    }

    private func discardArtworkFile(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: Storage.artworkURL(fileName))
    }

    private func apply(_ result: EnrichmentResult, to track: Track) {
        if !track.metadataLocked {
            if let value = result.title { track.title = value }
            if let value = result.artist { track.artist = value }
            if let value = result.album { track.album = value }
            if let value = result.albumArtist { track.albumArtist = value }
        }
        if let value = result.duration { track.duration = value }
        if let value = result.artworkFileName {
            // Пока шёл поиск, пользователь мог поставить свою обложку — тогда найденная не нужна
            if track.artworkLocked {
                discardArtworkFile(value)
            } else {
                removeArtwork(of: track)
                track.artworkFileName = value
                track.paletteHex = result.paletteHex
            }
        }
        if !track.lyricsLocked, result.plainLyrics != nil || result.syncedLyricsRaw != nil {
            track.plainLyrics = result.plainLyrics
            if !result.keepsSyncedLyrics, track.syncedLyricsRaw != result.syncedLyricsRaw {
                track.syncedLyricsRaw = result.syncedLyricsRaw
                track.lyricsOffset = 0
            }
        }
        track.enrichmentStatus = result.status
    }
}
