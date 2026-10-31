import SwiftData
import SwiftUI

/// Вкладка «Поиск»: артисты, альбомы и треки медиатеки.
struct SearchView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    ContentUnavailableView(
                        "Поиск по медиатеке",
                        systemImage: "magnifyingglass",
                        description: Text("Ищите по названию трека, артисту или альбому.")
                    )
                } else {
                    let songs = tracks.filtered(by: trimmed)
                    let artists = LibraryIndex.artists(from: tracks).filter { $0.name.localizedStandardContains(trimmed) }
                    let albums = LibraryIndex.albums(from: tracks).filter {
                        $0.key.title.localizedStandardContains(trimmed) || $0.key.artist.localizedStandardContains(trimmed)
                    }
                    if songs.isEmpty && artists.isEmpty && albums.isEmpty {
                        ContentUnavailableView.search(text: trimmed)
                    } else {
                        List {
                            if !artists.isEmpty {
                                Section {
                                    ForEach(artists.prefix(5)) { artist in
                                        NavigationLink(value: LibraryRoute.artist(artist.name)) {
                                            HStack(spacing: 12) {
                                                ArtistAvatar(name: artist.name, fallbackArtwork: artist.artworkFileName, size: 44)
                                                Text(artist.name)
                                            }
                                        }
                                    }
                                } header: { SectionHeader("Артисты") }
                            }
                            if !albums.isEmpty {
                                Section {
                                    ForEach(albums.prefix(5)) { album in
                                        NavigationLink(value: LibraryRoute.album(album.key)) {
                                            HStack(spacing: 12) {
                                                ArtworkView(fileName: album.artworkFileName, size: 44, cornerRadius: 6)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(album.key.title).lineLimit(1)
                                                    Text(album.key.artist)
                                                        .font(.subheadline)
                                                        .foregroundStyle(Theme.Colors.labelSecondary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                    }
                                } header: { SectionHeader("Альбомы") }
                            }
                            if !songs.isEmpty {
                                Section {
                                    TrackRows(tracks: songs)
                                } header: { SectionHeader("Песни") }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Артисты, альбомы, треки")
            .libraryDestinations()
        }
    }
}
