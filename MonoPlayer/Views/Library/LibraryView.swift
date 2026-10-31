import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySort: String, CaseIterable, Identifiable {
    case dateAdded, title, artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: "По дате добавления"
        case .title: "По названию"
        case .artist: "По артисту"
        }
    }

    func sorted(_ tracks: [Track]) -> [Track] {
        switch self {
        case .dateAdded:
            tracks.sorted { $0.dateAdded > $1.dateAdded }
        case .title:
            tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            tracks.sorted {
                let byArtist = $0.artist.localizedStandardCompare($1.artist)
                return byArtist == .orderedSame
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : byArtist == .orderedAscending
            }
        }
    }
}

extension Array where Element == Track {
    func filtered(by query: String) -> [Track] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return self }
        return filter {
            $0.title.localizedStandardContains(query)
                || $0.artist.localizedStandardContains(query)
                || ($0.album?.localizedStandardContains(query) ?? false)
        }
    }
}

/// Медиатека: large title, поиск, сортировка, импорт и пустое состояние.
struct LibraryView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @Environment(\.modelContext) private var modelContext
    @Environment(EnrichmentCoordinator.self) private var enrichment

    @AppStorage("librarySort") private var sort: LibrarySort = .dateAdded
    @State private var query = ""
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importedCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if tracks.isEmpty {
                    emptyState
                } else {
                    let visible = sort.sorted(tracks).filtered(by: query)
                    if visible.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        TrackList(tracks: visible)
                    }
                }
            }
            .navigationTitle("Медиатека")
            .searchable(text: $query, prompt: "Треки, артисты, альбомы")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Настройки", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu("Сортировка", systemImage: "arrow.up.arrow.down") {
                        Picker("Сортировка", selection: $sort) {
                            ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Button("Импортировать", systemImage: "plus") { showImporter = true }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: AudioImport.contentTypes,
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result else { return }
                let imported = FileImportService.importFiles(urls, into: modelContext, enrichment: enrichment)
                importedCount += imported.count
            }
            .sensoryFeedback(.success, trigger: importedCount)
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Нет музыки", systemImage: "music.note.list")
        } description: {
            Text("Импортируйте аудиофайлы из «Файлов» — обложки и тексты подтянутся автоматически.")
        } actions: {
            Button("Импортировать файлы") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Theme.Colors.bgPrimary)
        }
    }
}

enum AudioImport {
    static var contentTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType("org.xiph.flac") { types.append(flac) }
        return types
    }
}

/// Список треков, общий для медиатеки и поиска: воспроизведение, свайпы, контекстное меню.
struct TrackList: View {
    let tracks: [Track]

    @Environment(AudioPlayerManager.self) private var player
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(\.modelContext) private var modelContext
    @State private var editingTrack: Track?
    @State private var selectionTick = 0

    var body: some View {
        List {
            ForEach(tracks) { track in
                let isCurrent = player.currentTrack?.id == track.id
                Button {
                    if isCurrent {
                        player.togglePlayPause()
                    } else {
                        player.play(track, in: tracks)
                    }
                    selectionTick += 1
                } label: {
                    TrackRowView(track: track, isCurrent: isCurrent, isPlaying: isCurrent && player.isPlaying)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: Theme.Spacing.screen, bottom: 6, trailing: Theme.Spacing.screen))
                .swipeActions(edge: .trailing) {
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        FileImportService.delete(track, context: modelContext, player: player)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Играть следующим", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        player.playNext(track)
                    }
                    .tint(.gray)
                }
                .contextMenu {
                    Button("Играть следующим", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        player.playNext(track)
                    }
                    Button("Изменить сведения", systemImage: "pencil") { editingTrack = track }
                    Button("Обновить обложку и текст", systemImage: "arrow.clockwise") {
                        enrichment.refresh(track, resetArtwork: true)
                    }
                    ShareLink(item: track.audioURL) {
                        Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        FileImportService.delete(track, context: modelContext, player: player)
                    }
                } preview: {
                    TrackPreview(track: track)
                }
            }
        }
        .listStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sheet(item: $editingTrack) { EditTrackView(track: $0) }
    }
}

private struct TrackPreview: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtworkView(fileName: track.artworkFileName, size: 260, cornerRadius: Theme.Radius.playerArtwork)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.headline)
                Text(track.album.map { "\(track.artist) · \($0)" } ?? track.artist)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
        }
        .padding(16)
        .frame(width: 292, alignment: .leading)
    }
}
