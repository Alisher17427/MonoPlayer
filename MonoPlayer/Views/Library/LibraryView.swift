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

enum AudioImport {
    static var contentTypes: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        if let flac = UTType("org.xiph.flac") { types.append(flac) }
        return types
    }
}

/// Медиатека: разделы, недавно добавленные альбомы и треки, импорт.
struct LibraryView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @Environment(\.modelContext) private var modelContext
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(AppRouter.self) private var router

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importedCount = 0

    var body: some View {
        NavigationStack(path: Bindable(router).libraryPath) {
            Group {
                if tracks.isEmpty {
                    emptyState
                } else {
                    home
                }
            }
            .navigationTitle("Медиатека")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Настройки", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            .libraryDestinations()
        }
    }

    private var home: some View {
        List {
            Section {
                category("Артисты", systemImage: "music.mic", route: .artists)
                category("Альбомы", systemImage: "square.stack", route: .albums)
                category("Песни", systemImage: "music.note", route: .songs)
                category("Клипы", systemImage: "play.rectangle", route: .videos)
            }

            let recentAlbums = LibraryIndex.recentAlbums(from: tracks, limit: 10)
            if !recentAlbums.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(recentAlbums) { album in
                                NavigationLink(value: LibraryRoute.album(album.key)) {
                                    AlbumCard(album: album, side: 150)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screen)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                } header: {
                    SectionHeader("Недавно добавленные альбомы")
                }
            }

            Section {
                TrackRows(tracks: Array(tracks.prefix(12)), queue: tracks)
            } header: {
                SectionHeader("Недавно добавленные треки")
            }
        }
        .listStyle(.plain)
    }

    private func category(_ title: String, systemImage: String, route: LibraryRoute) -> some View {
        NavigationLink(value: route) {
            Label {
                Text(title).font(.title3)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.labelPrimary)
            }
            .padding(.vertical, 4)
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

/// Все песни: сортировка и поиск.
struct SongsView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @AppStorage("librarySort") private var sort: LibrarySort = .dateAdded
    @State private var query = ""

    var body: some View {
        let visible = sort.sorted(tracks).filtered(by: query)
        Group {
            if visible.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Нет песен", systemImage: "music.note")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                TrackList(tracks: visible)
            }
        }
        .navigationTitle("Песни")
        .searchable(text: $query, prompt: "Треки, артисты, альбомы")
        .toolbar {
            Menu("Сортировка", systemImage: "arrow.up.arrow.down") {
                Picker("Сортировка", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(Theme.Colors.labelPrimary)
            .textCase(nil)
            .padding(.top, 8)
    }
}

/// Список треков целиком (отдельный экран).
struct TrackList: View {
    let tracks: [Track]

    var body: some View {
        List { TrackRows(tracks: tracks) }
            .listStyle(.plain)
    }
}

/// Строки треков для любого List: воспроизведение, свайпы, контекстное меню, переходы.
struct TrackRows: View {
    let tracks: [Track]
    var queue: [Track]? = nil
    var numbered = false

    @Environment(AudioPlayerManager.self) private var player
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
            let isCurrent = player.currentTrack?.id == track.id
            Button {
                if isCurrent {
                    player.togglePlayPause()
                } else {
                    player.play(track, in: queue ?? tracks)
                }
            } label: {
                if numbered {
                    AlbumTrackRow(index: index + 1, track: track, isCurrent: isCurrent, isPlaying: isCurrent && player.isPlaying)
                } else {
                    TrackRowView(track: track, isCurrent: isCurrent, isPlaying: isCurrent && player.isPlaying)
                }
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
                TrackMenuItems(track: track, showsDelete: true)
            } preview: {
                TrackPreview(track: track)
            }
        }
    }
}

/// Пункты меню трека — общие для списков и Now Playing.
struct TrackMenuItems: View {
    let track: Track
    var showsDelete = false
    var showsPlayNext = true
    var onEdit: (() -> Void)? = nil

    @Environment(AudioPlayerManager.self) private var player
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        if showsPlayNext {
            Button("Играть следующим", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext(track)
            }
        }
        let artists = track.artists
        if artists.count == 1 {
            Button("Перейти к артисту", systemImage: "music.mic") { router.openArtist(artists[0]) }
        } else if artists.count > 1 {
            Menu("Перейти к артисту", systemImage: "music.mic") {
                ForEach(artists, id: \.self) { name in
                    Button(name) { router.openArtist(name) }
                }
            }
        }
        if let key = track.albumKey {
            Button("Перейти к альбому", systemImage: "square.stack") { router.openAlbum(key) }
        }
        Button("Клип на YouTube", systemImage: "play.rectangle") {
            openURL(YouTubeLink.search(artist: track.artist, title: track.title))
        }
        Divider()
        Button("Изменить сведения", systemImage: "pencil") {
            if let onEdit { onEdit() } else { router.editingTrack = track }
        }
        Menu("Искать заново", systemImage: "arrow.clockwise") {
            Button("Обложку и текст") { enrichment.refresh(track, resetArtwork: true, resetLyrics: true) }
            Button("Только обложку") { enrichment.refresh(track, resetArtwork: true) }
            Button("Только текст") { enrichment.refresh(track, resetLyrics: true) }
        }
        ShareLink(item: track.audioURL) {
            Label("Поделиться файлом", systemImage: "square.and.arrow.up")
        }
        if showsDelete {
            Divider()
            Button("Удалить", systemImage: "trash", role: .destructive) {
                FileImportService.delete(track, context: modelContext, player: player)
            }
        }
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
