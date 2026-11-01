import AVFoundation
import Foundation
import SwiftData

/// Пути внутри песочницы приложения.
enum Storage {
    static let tracksDirectory = URL.documentsDirectory.appending(path: "Tracks", directoryHint: .isDirectory)
    static let artworkDirectory = URL.documentsDirectory.appending(path: "Artwork", directoryHint: .isDirectory)

    static func prepare() {
        for directory in [tracksDirectory, artworkDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func trackURL(_ fileName: String) -> URL { tracksDirectory.appending(path: fileName) }
    static func artworkURL(_ fileName: String) -> URL { artworkDirectory.appending(path: fileName) }
}

/// Метаданные, встроенные в аудиофайл (ID3 / iTunes atoms).
struct LocalMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var duration: TimeInterval?
    var artworkData: Data?
}

enum FileImportService {
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "alac"]

    /// Шаг 1 пайплайна: копирование в Sandbox и мгновенная регистрация в SwiftData.
    @MainActor
    @discardableResult
    static func importFiles(_ urls: [URL], into context: ModelContext, enrichment: EnrichmentCoordinator) -> [Track] {
        Storage.prepare()
        var imported: [Track] = []
        for url in urls {
            do {
                imported.append(try importFile(url, into: context))
            } catch {
                print("Import failed for \(url.lastPathComponent): \(error)")
            }
        }
        try? context.save()
        enrichment.enqueue(imported)
        return imported
    }

    /// Файлы, которые система положила в Inbox через «Поделиться», но не передала в `onOpenURL`:
    /// при отправке нескольких файлов сразу приложение получает ссылку только на один.
    static func pendingInboxFiles() -> [URL] {
        let inbox = URL.documentsDirectory.appending(path: "Inbox", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    @MainActor
    private static func importFile(_ url: URL, into context: ModelContext) throws -> Track {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let fileName = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: url, to: Storage.trackURL(fileName))

        // Файлы, пришедшие через «Поделиться», система кладёт во временный Inbox — убираем за собой.
        if url.path().contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }

        let parsed = FilenameSanitizer.parse(url.lastPathComponent)
        let track = Track(title: parsed.title, artist: parsed.artist ?? Track.unknownArtist, audioFileName: fileName)
        context.insert(track)
        return track
    }

    /// Шаг 2 пайплайна: чтение встроенных тегов через AVURLAsset.
    static func readLocalMetadata(from url: URL) async -> LocalMetadata {
        var result = LocalMetadata()
        let asset = AVURLAsset(url: url)
        guard let loaded = try? await asset.load(.commonMetadata, .duration) else { return result }
        let (items, duration) = loaded

        let seconds = duration.seconds
        if seconds.isFinite, seconds > 0 { result.duration = seconds }

        for item in items {
            switch item.commonKey {
            case .commonKeyTitle:
                result.title = try? await item.load(.stringValue)
            case .commonKeyArtist:
                result.artist = try? await item.load(.stringValue)
            case .commonKeyAlbumName:
                result.album = try? await item.load(.stringValue)
            case .commonKeyArtwork:
                if result.artworkData == nil {
                    result.artworkData = try? await item.load(.dataValue)
                }
            default:
                break
            }
        }
        // Исполнитель альбома нет среди common-ключей — ищем в ID3 (TPE2) и iTunes (aART)
        if let all = try? await asset.load(.metadata) {
            let albumArtistIDs: Set<AVMetadataIdentifier> = [.id3MetadataBand, .iTunesMetadataAlbumArtist]
            for item in all where item.identifier.map({ albumArtistIDs.contains($0) }) == true {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    result.albumArtist = value
                    break
                }
            }
        }
        result.albumArtist = result.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        result.title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        result.artist = result.artist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        result.album = result.album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return result
    }

    /// Удаляет трек вместе с его файлами.
    @MainActor
    static func delete(_ track: Track, context: ModelContext, player: AudioPlayerManager) {
        player.remove(track)
        try? FileManager.default.removeItem(at: track.audioURL)
        if let artworkURL = track.artworkURL {
            try? FileManager.default.removeItem(at: artworkURL)
        }
        context.delete(track)
        try? context.save()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
