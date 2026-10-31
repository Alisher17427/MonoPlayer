import SwiftUI

/// Ручная правка сведений: поля, выбор совпадения (метаданные + обложка) и выбор текста песни.
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

    @State private var metadataCandidates: [MetadataCandidate] = []
    @State private var lyricsCandidates: [LyricsCandidate] = []
    @State private var searchingMetadata = false
    @State private var searchingLyrics = false
    @State private var searchedMetadata = false
    @State private var searchedLyrics = false
    @State private var chosenArtwork: MetadataCandidate?
    @State private var chosenLyrics: LyricsCandidate?

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

                Section("Сведения") {
                    LabeledField(label: "Название", text: $title)
                    LabeledField(label: "Артист", text: $artist)
                    LabeledField(label: "Альбом", text: $album)
                }

                metadataSection
                lyricsSection
            }
            .navigationTitle("Сведения о треке")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = track.title
                artist = track.hasKnownArtist ? track.artist : ""
                album = track.album ?? ""
            }
        }
    }

    @ViewBuilder
    private var artworkPreview: some View {
        if let url = chosenArtwork?.artworkURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Theme.Colors.bgSecondary }
            }
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ArtworkView(fileName: track.artworkFileName, size: 120, cornerRadius: 10, isLoading: track.isEnriching)
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
                    chosenLyrics = chosenLyrics?.id == candidate.id ? nil : candidate
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
        title = candidate.title
        if !candidate.artist.isEmpty { artist = candidate.artist }
        if let value = candidate.album { album = value }
    }

    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespaces)
        let newArtist = artist.trimmingCharacters(in: .whitespaces)
        let newAlbum = album.trimmingCharacters(in: .whitespaces).nilIfEmpty

        let changed = newTitle != track.title
            || (newArtist.isEmpty ? Track.unknownArtist : newArtist) != track.artist
            || newAlbum != track.album
        track.title = newTitle
        track.artist = newArtist.isEmpty ? Track.unknownArtist : newArtist
        track.album = newAlbum
        if changed || chosenArtwork != nil { track.metadataLocked = true }

        if let chosenLyrics {
            enrichment.applyLyrics(chosenLyrics, to: track)
        }
        try? modelContext.save()

        if let url = chosenArtwork?.artworkURL {
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
                .frame(width: 90, alignment: .leading)
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
