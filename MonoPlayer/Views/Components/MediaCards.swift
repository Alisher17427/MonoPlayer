import SwiftUI

/// Карточка альбома: квадратная обложка, название, артист.
struct AlbumCard: View {
    let album: AlbumSummary
    let side: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(fileName: album.artworkFileName, size: side, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.key.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.labelPrimary)
                    .lineLimit(1)
                Text(album.key.artist)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.labelSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: side, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Альбом \(album.key.title), \(album.key.artist)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Круглое фото артиста (Deezer), запасной вариант — обложка его трека.
struct ArtistAvatar: View {
    let name: String
    var fallbackArtwork: String?
    let size: CGFloat

    @Environment(ArtistMediaStore.self) private var media
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let fallbackArtwork {
                ArtworkView(fileName: fallbackArtwork, size: size, cornerRadius: 0)
            } else {
                Theme.Colors.bgSecondary
                Image(systemName: "music.mic")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .animation(.easeInOut(duration: 0.3), value: image != nil)
        .task(id: name) {
            await media.loadPicture(for: name)
            if let url = media.picture(for: name) {
                image = await ArtworkLoader.image(at: url, maxPixelSize: size * displayScale)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Карточка клипа: превью 16:9, название, год. Нажатие открывает YouTube.
struct VideoCard: View {
    let video: MusicVideo
    var width: CGFloat = 220

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(video.youTubeURL)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: video.thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.Colors.bgSecondary
                    }
                }
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.labelPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let year = video.releaseYear {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Смотреть на YouTube", systemImage: "play.rectangle") { openURL(video.youTubeURL) }
            if let apple = video.appleURL {
                Button("Открыть в Apple Music", systemImage: "music.note") { openURL(apple) }
            }
        }
        .accessibilityLabel("Клип \(video.title)")
        .accessibilityHint("Откроется на YouTube")
    }
}

/// Горизонтальная лента клипов артиста с загрузкой по требованию.
struct ArtistVideosRow: View {
    let artist: String
    /// Названия его треков в медиатеке — чтобы не спутать с одноимённым артистом
    var knownTitles: [String] = []

    @Environment(ArtistMediaStore.self) private var media

    var body: some View {
        Group {
            if let videos = media.videoList(for: artist) {
                if videos.isEmpty {
                    Text("Клипов не найдено")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(videos) { VideoCard(video: $0) }
                        }
                        .padding(.horizontal, Theme.Spacing.screen)
                    }
                    .scrollIndicators(.hidden)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Ищем клипы…").foregroundStyle(Theme.Colors.labelSecondary)
                }
                .font(.subheadline)
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, 8)
            }
        }
        .task(id: artist) { await media.loadVideos(for: artist, knownTitles: knownTitles) }
    }
}
