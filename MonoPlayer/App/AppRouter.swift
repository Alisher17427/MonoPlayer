import Observation
import SwiftUI

enum AppTab: Hashable {
    case library, search
}

/// Экраны внутри медиатеки.
enum LibraryRoute: Hashable {
    case songs
    case albums
    case artists
    case videos
    case artist(String)
    case album(AlbumKey)
}

/// Навигация уровня приложения: вкладка, стек медиатеки, плеер и общие листы.
/// Нужна, чтобы из Now Playing можно было перейти на страницу артиста или альбома.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .library
    var libraryPath: [LibraryRoute] = []
    var showPlayer = false
    var editingTrack: Track?

    /// Открывает страницу конкретного исполнителя (одного из участников трека).
    func openArtist(_ name: String) {
        open(.artist(name))
    }

    func openAlbum(_ key: AlbumKey) {
        open(.album(key))
    }

    private func open(_ route: LibraryRoute) {
        showPlayer = false
        selectedTab = .library
        if libraryPath.last != route {
            libraryPath.append(route)
        }
    }
}

extension View {
    /// Общие экраны для стеков медиатеки и поиска.
    func libraryDestinations() -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .songs: SongsView()
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .videos: VideosView()
            case .artist(let name): ArtistDetailView(name: name)
            case .album(let key): AlbumDetailView(key: key)
            }
        }
    }
}
