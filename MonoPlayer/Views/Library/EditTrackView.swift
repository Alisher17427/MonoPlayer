import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Ручная правка сведений: поля, своя обложка, выбор совпадения (метаданные + обложка), поиск или свой текст песни.
/// Изменённые вручную поля блокируются от автопоиска — теги файла их больше не перезапишут.
struct EditTrackView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(AudioPlayerManager.self) private var player

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var albumArtist = ""

    @State private var metadataCandidates: [MetadataCandidate] = []
    @State private var lyricsCandidates: [LyricsCandidate] = []
    @State private var searchingMetadata = false
    @State private var searchingLyrics = false
    @State private var searchedMetadata = false
    @State private var searchedLyrics = false
    @State private var chosenArtwork: MetadataCandidate?
    @State private var chosenLyrics: LyricsCandidate?

    // Своя обложка: готовый JPEG и картинка для превью; или запрос удалить обложку
    @State private var customArtwork: Data?
    @State private var customArtworkImage: UIImage?
    @State private var removesArtwork = false
    @State private var photoItem: PhotosPickerItem?
    @State private var preparingArtwork = false

    // Свой текст (обычный или LRC)
    @State private var lyricsText = ""
    @State private var originalLyricsText = ""

    @State private var importTarget: ImportTarget?
    @State private var importError: String?

    private enum ImportTarget {
        case artwork, lyrics

        var contentTypes: [UTType] {
            switch self {
            case .artwork: [.image]
            case .lyrics: [.plainText, .text] + [UTType(filenameExtension: "lrc")].compactMap { $0 }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        artworkPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                artworkSection

                Section {
                    LabeledField(label: "Название", text: $title)
                    LabeledField(label: "Артист", text: $artist)
                    LabeledField(label: "Альбом", text: $album)
                    LabeledField(label: "Исп. альбома", text: $albumArtist)
                } header: {
                    Text("Сведения")
                } footer: {
                    Text("Несколько исполнителей пишите через запятую, «feat.» или «x» — у каждого будет своя страница. «Исполнитель альбома» объединяет треки с разными исполнителями в один альбом; если пусто — определяется автоматически.")
                }

                metadataSection
                lyricsSection
                customLyricsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Сведения о треке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || preparingArtwork)
                }
            }
            .onAppear {
                title = track.title
                artist = track.hasKnownArtist ? track.artist : ""
                album = track.album ?? ""
                albumArtist = track.albumArtist ?? ""
                lyricsText = track.syncedLyricsRaw ?? track.plainLyrics ?? ""
                originalLyricsText = lyricsText
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    preparingArtwork = true
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await setCustomArtwork(data)
                    } else {
                        importError = "Не удалось загрузить фото."
                    }
                    preparingArtwork = false
                    photoItem = nil
                }
            }
            .fileImporter(
                isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
                allowedContentTypes: importTarget?.contentTypes ?? [.item]
            ) { result in
                let target = importTarget
                importTarget = nil
                guard case let .success(url) = result, let target else { return }
                Task { await importFile(url, as: target) }
            }
            .alert("Ошибка", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
    }

    @ViewBuilder
    private var artworkPreview: some View {
        if let customArtworkImage {
            Image(uiImage: customArtworkImage)
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if removesArtwork {
            ArtworkView(fileName: nil, size: 120, cornerRadius: 10)
        } else if let url = chosenArtwork?.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.Colors.bgSecondary }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ArtworkView(fileName: track.artworkFileName, size: 120, cornerRadius: 10, isLoading: track.isEnriching)
        }
    }

    // MARK: - Своя обложка

    private var hasArtworkAfterEdits: Bool {
        customArtwork != nil || (!removesArtwork && (chosenArtwork != nil || track.artworkFileName != nil))
    }

    private var artworkSection: some View {
        Section {
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack {
                    Label("Выбрать из Фото", systemImage: "photo.on.rectangle")
                    Spacer()
                    if preparingArtwork { ProgressView() }
                }
            }
            .disabled(preparingArtwork)
            Button {
                importTarget = .artwork
            } label: {
                Label("Выбрать из Файлов", systemImage: "folder")
            }
            .disabled(preparingArtwork)
            if hasArtworkAfterEdits {
                Button(role: .destructive) {
                    customArtwork = nil
                    customArtworkImage = nil
                    chosenArtwork = nil
                    removesArtwork = true
                } label: {
                    Label("Удалить обложку", systemImage: "trash")
                }
            }
        } header: {
            Text("Обложка")
        } footer: {
            Text("Картинка обрезается до квадрата по центру.")
        }
    }

    private func setCustomArtwork(_ data: Data) async {
        let prepared = await Task.detached(priority: .userInitiated) { ArtworkLoader.squareJPEG(from: data) }.value
        guard let prepared, let image = UIImage(data: prepared) else {
            importError = "Не удалось открыть изображение."
            return
        }
        customArtwork = prepared
        customArtworkImage = image
        chosenArtwork = nil
        removesArtwork = false
    }

    private func importFile(_ url: URL, as target: ImportTarget) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importError = "Не удалось прочитать файл."
            return
        }
        switch target {
        case .artwork:
            preparingArtwork = true
            await setCustomArtwork(data)
            preparingArtwork = false
        case .lyrics:
            // Старые LRC часто в Windows-1251
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else {
                importError = "Не удалось прочитать текст: неизвестная кодировка."
                return
            }
            lyricsText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            chosenLyrics = nil
        }
    }

    // MARK: - Совпадения: метаданные и обложки

    private var metadataSection: some View {
        Section {
            Button {
                Task { await searchMetadata() }
            } label: {
                HStack {
                    Label("Найти совпадения", systemImage: "magnifyingglass")
                    Spacer()
                    if searchingMetadata { ProgressView() }
                }
            }
            .disabled(searchingMetadata || title.trimmingCharacters(in: .whitespaces).isEmpty)

            if searchedMetadata && metadataCandidates.isEmpty && !searchingMetadata {
                Text("Ничего не найдено. Попробуйте изменить название или артиста.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }

            ForEach(metadataCandidates) { candidate in
                Button {
                    choose(candidate)
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: candidate.artworkURL) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { Theme.Colors.bgTertiary }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title).lineLimit(1)
                            Text([candidate.artist, candidate.album].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.labelSecondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                SourceBadge(text: candidate.source.rawValue)
                                if let duration = candidate.duration {
                                    Text(duration.playbackTime)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.Colors.labelSecondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        if chosenArtwork?.id == candidate.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Метаданные и обложка")
        } footer: {
            Text("Источники: iTunes, Deezer, MusicBrainz. Выбор заполнит поля и заменит обложку.")
        }
    }

    // MARK: - Текст песни

    private var lyricsSection: some View {
        Section {
            Button {
                Task { await searchLyrics() }
            } label: {
                HStack {
                    Label("Найти текст", systemImage: "quote.bubble")
                    Spacer()
                    if searchingLyrics { ProgressView() }
                }
            }
            .disabled(searchingLyrics || title.trimmingCharacters(in: .whitespaces).isEmpty)

            if searchedLyrics && lyricsCandidates.isEmpty && !searchingLyrics {
                Text("Текст не найден.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }

            ForEach(lyricsCandidates) { candidate in
                Button {
                    chooseLyrics(candidate)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.trackName).lineLimit(1)
                            Text([candidate.artistName, candidate.albumName].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.labelSecondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                SourceBadge(text: candidate.isSynced ? "Синхронный" : "Обычный")
                                if let duration = candidate.duration {
                                    Text(durationNote(duration))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(durationMatches(duration) ? Theme.Colors.labelSecondary : Color.orange)
                                }
                            }
                            if let preview = preview(of: candidate) {
                                Text(preview)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.labelTertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if chosenLyrics?.id == candidate.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Текст песни")
        } footer: {
            Text("Для караоке выбирайте синхронный текст с длительностью как у файла (\(track.duration.playbackTime)). Оранжевым отмечены версии другой длины — тайминги могут не совпасть.")
        }
    }

    // MARK: - Свой текст

    private var customLyricsSection: some View {
        let syncedLines = LRCParser.parse(lyricsText).count
        return Section {
            TextEditor(text: $lyricsText)
                .frame(minHeight: 180)
                .overlay(alignment: .topLeading) {
                    if lyricsText.isEmpty {
                        Text("Вставьте или напишите текст песни")
                            .foregroundStyle(Theme.Colors.labelTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            Button {
                importTarget = .lyrics
            } label: {
                Label("Загрузить из файла (.lrc, .txt)", systemImage: "doc.text")
            }
            if !lyricsText.isEmpty {
                Button(role: .destructive) {
                    lyricsText = ""
                    chosenLyrics = nil
                } label: {
                    Label("Очистить текст", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Свой текст")
        } footer: {
            if syncedLines > 0 {
                Text("Синхронный текст: строк с таймкодами — \(syncedLines). Они будут подсвечиваться под музыку.")
            } else {
                Text("Обычный текст или LRC с таймкодами вида [01:23.45] — тогда строки будут подсвечиваться под музыку. Свой текст автопоиск не заменит.")
            }
        }
    }

    private func candidateText(_ candidate: LyricsCandidate) -> String {
        candidate.syncedLyrics?.nilIfEmpty ?? candidate.plainLyrics ?? ""
    }

    /// Выбор найденного текста заполняет «Свой текст» — его можно подправить перед сохранением.
    private func chooseLyrics(_ candidate: LyricsCandidate) {
        if chosenLyrics?.id == candidate.id {
            chosenLyrics = nil
            lyricsText = originalLyricsText
        } else {
            chosenLyrics = candidate
            lyricsText = candidateText(candidate)
        }
    }

    private func durationNote(_ duration: TimeInterval) -> String {
        guard track.duration > 0 else { return duration.playbackTime }
        let delta = Int((duration - track.duration).rounded())
        return delta == 0 ? duration.playbackTime : "\(duration.playbackTime) (\(delta > 0 ? "+" : "")\(delta) с)"
    }

    private func durationMatches(_ duration: TimeInterval) -> Bool {
        track.duration <= 0 || abs(duration - track.duration) <= LyricsService.durationTolerance
    }

    private func preview(of candidate: LyricsCandidate) -> String? {
        if let synced = candidate.syncedLyrics {
            let lines = LRCParser.parse(synced).map(\.text).filter { !$0.isEmpty }
            return lines.prefix(2).joined(separator: " / ")
        }
        return candidate.plainLyrics?.split(separator: "\n").prefix(2).joined(separator: " / ")
    }

    // MARK: - Действия

    private var searchArtist: String? {
        let value = artist.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func searchMetadata() async {
        searchingMetadata = true
        metadataCandidates = await MetadataSearch.allCandidates(artist: searchArtist, title: title.trimmingCharacters(in: .whitespaces))
        searchingMetadata = false
        searchedMetadata = true
    }

    private func searchLyrics() async {
        searchingLyrics = true
        let found = (try? await LyricsService.search(artist: searchArtist, title: title.trimmingCharacters(in: .whitespaces))) ?? []
        // Синхронные и подходящие по длительности — наверх
        lyricsCandidates = found.sorted { a, b in
            func score(_ c: LyricsCandidate) -> Double {
                let sync = c.isSynced ? 0 : 1000.0
                guard track.duration > 0, let d = c.duration else { return sync + 500 }
                return sync + abs(d - track.duration)
            }
            return score(a) < score(b)
        }
        searchingLyrics = false
        searchedLyrics = true
    }

    private func choose(_ candidate: MetadataCandidate) {
        if chosenArtwork?.id == candidate.id {
            chosenArtwork = nil
            return
        }
        chosenArtwork = candidate
        customArtwork = nil
        customArtworkImage = nil
        removesArtwork = false
        title = candidate.title
        if !candidate.artist.isEmpty { artist = candidate.artist }
        if let value = candidate.album { album = value }
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        let newArtist = artist.trimmingCharacters(in: .whitespaces)
        let newAlbum = album.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let newAlbumArtist = albumArtist.trimmingCharacters(in: .whitespaces).nilIfEmpty

        let changed = newTitle != track.title
            || (newArtist.isEmpty ? Track.unknownArtist : newArtist) != track.artist
            || newAlbum != track.album
            || newAlbumArtist != track.albumArtist
        track.title = newTitle
        track.artist = newArtist.isEmpty ? Track.unknownArtist : newArtist
        track.album = newAlbum
        track.albumArtist = newAlbumArtist
        if changed || chosenArtwork != nil { track.metadataLocked = true }

        if let chosenLyrics, lyricsText == candidateText(chosenLyrics) {
            enrichment.applyLyrics(chosenLyrics, to: track)
        } else if lyricsText != originalLyricsText {
            enrichment.applyCustomLyrics(lyricsText, to: track)
        }
        try? modelContext.save()

        if let customArtwork {
            enrichment.applyArtwork(data: customArtwork, to: track)
        } else if removesArtwork {
            enrichment.clearArtwork(of: track)
        } else if let url = chosenArtwork?.artworkURL {
            let track = track
            Task {
                _ = await enrichment.applyArtwork(from: url, to: track)
                if player.currentTrack?.id == track.id { player.updateNowPlayingInfo() }
            }
        }
        if player.currentTrack?.id == track.id { player.updateNowPlayingInfo() }
        dismiss()
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .frame(width: 110, alignment: .leading)
            TextField(label, text: $text)
        }
    }
}

private struct SourceBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Colors.bgTertiary, in: Capsule())
            .foregroundStyle(Theme.Colors.labelSecondary)
    }
}
