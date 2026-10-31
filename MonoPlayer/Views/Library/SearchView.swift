import SwiftData
import SwiftUI

/// Вкладка «Поиск» — поиск по названию, артисту и альбому.
struct SearchView: View {
    @Query(sort: \Track.title) private var tracks: [Track]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView(
                        "Поиск по медиатеке",
                        systemImage: "magnifyingglass",
                        description: Text("Ищите по названию трека, артисту или альбому.")
                    )
                } else {
                    let results = tracks.filtered(by: query)
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        TrackList(tracks: results)
                    }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Треки, артисты, альбомы")
        }
    }
}
