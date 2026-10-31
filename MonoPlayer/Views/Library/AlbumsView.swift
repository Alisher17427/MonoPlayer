import SwiftData
import SwiftUI

/// Сетка альбомов в две колонки.
struct AlbumsView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @State private var query = ""

    var body: some View {
        let albums = LibraryIndex.albums(from: tracks).filter {
            query.isEmpty || $0.key.title.localizedStandardContains(query) || $0.key.artist.localizedStandardContains(query)
        }
        Group {
            if albums.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Нет альбомов",
                        systemImage: "square.stack",
                        description: Text("Альбомы появляются, когда у треков указан альбом — автоматически или через «Изменить сведения».")
                    )
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                GeometryReader { geo in
                    let spacing: CGFloat = 16
                    let side = max(100, (geo.size.width - Theme.Spacing.screen * 2 - spacing) / 2)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(side), spacing: spacing), GridItem(.fixed(side))], spacing: 20) {
                            ForEach(albums) { album in
                                NavigationLink(value: LibraryRoute.album(album.key)) {
                                    AlbumCard(album: album, side: side)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .navigationTitle("Альбомы")
        .searchable(text: $query, prompt: "Альбомы и артисты")
    }
}

/// Страница альбома: обложка, артист (ссылка), «Слушать» / «Перемешать», треки по порядку.
struct AlbumDetailView: View {
    let key: AlbumKey

    @Query(sort: \Track.dateAdded) private var tracks: [Track]
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        if let album = LibraryIndex.album(key, in: tracks) {
            List {
                VStack(spacing: 14) {
                    ArtworkView(fileName: album.artworkFileName, size: 250, cornerRadius: Theme.Radius.playerArtwork)
                        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    VStack(spacing: 4) {
                        Text(album.key.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        NavigationLink(value: LibraryRoute.artist(album.key.artist)) {
                            Text(album.key.artist)
                                .font(.title3)
                                .foregroundStyle(Theme.Colors.labelSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    PlayShuffleButtons(tracks: album.tracks)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)

                Section {
                    TrackRows(tracks: album.tracks, numbered: true)
                } footer: {
                    Text("\(album.tracks.count) \(Self.tracksWord(album.tracks.count)), \(Int((album.duration / 60).rounded())) мин")
                        .padding(.top, 8)
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Альбом не найден", systemImage: "square.stack")
        }
    }

    static func tracksWord(_ count: Int) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if mod10 == 1 && mod100 != 11 { return "трек" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "трека" }
        return "треков"
    }
}

/// «Слушать» и «Перемешать» — для альбома и артиста.
struct PlayShuffleButtons: View {
    let tracks: [Track]
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first { player.play(first, in: tracks) }
            } label: {
                Label("Слушать", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            Button {
                let shuffled = tracks.shuffled()
                if let first = shuffled.first { player.play(first, in: shuffled) }
            } label: {
                Label("Перемешать", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.headline)
        .disabled(tracks.isEmpty)
    }
}
