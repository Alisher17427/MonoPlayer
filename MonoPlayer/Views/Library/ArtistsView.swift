import SwiftData
import SwiftUI

/// Список артистов медиатеки.
struct ArtistsView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @State private var query = ""

    var body: some View {
        let artists = LibraryIndex.artists(from: tracks).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        Group {
            if artists.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Нет артистов", systemImage: "music.mic",
                                           description: Text("Артисты появятся, когда у треков будет известен исполнитель."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                List(artists) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist.name)) {
                        HStack(spacing: 14) {
                            ArtistAvatar(name: artist.name, fallbackArtwork: artist.artworkFileName, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist.name).font(.body.weight(.medium))
                                Text(subtitle(for: artist))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.labelSecondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Артисты")
        .searchable(text: $query, prompt: "Артисты")
    }

    private func subtitle(for artist: ArtistSummary) -> String {
        var parts = ["\(artist.tracks.count) \(AlbumDetailView.tracksWord(artist.tracks.count))"]
        if !artist.albums.isEmpty { parts.append("альбомов: \(artist.albums.count)") }
        if !artist.appearsOn.isEmpty { parts.append("участие: \(artist.appearsOn.count)") }
        return parts.joined(separator: " · ")
    }
}

/// Страница артиста: фото, «Слушать» / «Перемешать», треки, альбомы, клипы.
struct ArtistDetailView: View {
    let name: String

    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @Environment(ArtistMediaStore.self) private var media
    @State private var showAllTracks = false

    var body: some View {
        if let artist = LibraryIndex.artist(named: name, in: tracks) {
            List {
                header(artist)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                PlayShuffleButtons(tracks: artist.tracks)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)

                Section {
                    let visible = showAllTracks ? artist.tracks : Array(artist.tracks.prefix(5))
                    TrackRows(tracks: visible, queue: artist.tracks)
                    if artist.tracks.count > 5 {
                        Button(showAllTracks ? "Свернуть" : "Все треки (\(artist.tracks.count))") {
                            withAnimation(Theme.Motion.screen) { showAllTracks.toggle() }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colors.labelSecondary)
                    }
                } header: {
                    SectionHeader("Треки")
                }

                if !artist.albums.isEmpty {
                    Section {
                        albumsRow(artist.albums)
                    } header: {
                        SectionHeader("Альбомы")
                    }
                }

                if !artist.appearsOn.isEmpty {
                    Section {
                        albumsRow(artist.appearsOn)
                    } header: {
                        SectionHeader("Участие")
                    }
                }

                Section {
                    ArtistVideosRow(artist: artist.name)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } header: {
                    SectionHeader("Клипы")
                }
            }
            .listStyle(.plain)
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Артист не найден", systemImage: "music.mic",
                                   description: Text("В медиатеке нет треков исполнителя «\(name)»."))
        }
    }

    private func albumsRow(_ albums: [AlbumSummary]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(albums) { album in
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
    }

    private func header(_ artist: ArtistSummary) -> some View {
        VStack(spacing: 12) {
            ArtistAvatar(name: artist.name, fallbackArtwork: artist.artworkFileName, size: 180)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
            Text(artist.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.screen)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
