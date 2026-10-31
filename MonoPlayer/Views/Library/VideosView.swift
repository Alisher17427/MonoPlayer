import SwiftData
import SwiftUI

/// Раздел «Клипы»: клипы артистов из медиатеки (каталог iTunes), просмотр — на YouTube.
struct VideosView: View {
    @Query(sort: \Track.dateAdded, order: .reverse) private var tracks: [Track]
    @State private var query = ""

    var body: some View {
        let artists = LibraryIndex.artists(from: tracks).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
        Group {
            if artists.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Нет клипов", systemImage: "play.rectangle",
                                           description: Text("Клипы подбираются по исполнителям из вашей медиатеки."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                List {
                    ForEach(artists) { artist in
                        Section {
                            ArtistVideosRow(artist: artist.name)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        } header: {
                            NavigationLink(value: LibraryRoute.artist(artist.name)) {
                                HStack(spacing: 10) {
                                    ArtistAvatar(name: artist.name, fallbackArtwork: artist.artworkFileName, size: 32)
                                    SectionHeader(artist.name).padding(.top, 0)
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.Colors.labelTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Клипы")
        .searchable(text: $query, prompt: "Артисты")
    }
}
