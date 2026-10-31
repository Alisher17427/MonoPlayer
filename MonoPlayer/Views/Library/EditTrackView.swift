import SwiftUI

/// Ручная правка метаданных, если автоматическое распознавание ошиблось.
struct EditTrackView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(AudioPlayerManager.self) private var player

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var refetch = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ArtworkView(fileName: track.artworkFileName, size: 120, cornerRadius: 10, isLoading: track.isEnriching)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Сведения") {
                    TextField("Название", text: $title)
                    TextField("Артист", text: $artist)
                    TextField("Альбом", text: $album)
                }
                Section {
                    Toggle("Заново найти обложку и текст", isOn: $refetch)
                } footer: {
                    Text("Поиск выполняется по новому названию и артисту через iTunes и LRCLIB.")
                }
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

    private func save() {
        track.title = title.trimmingCharacters(in: .whitespaces)
        let trimmedArtist = artist.trimmingCharacters(in: .whitespaces)
        track.artist = trimmedArtist.isEmpty ? Track.unknownArtist : trimmedArtist
        track.album = album.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if refetch {
            track.plainLyrics = nil
            track.syncedLyricsRaw = nil
            enrichment.refresh(track, resetArtwork: true)
        }
        try? modelContext.save()
        if player.currentTrack?.id == track.id { player.updateNowPlayingInfo() }
        dismiss()
    }
}
