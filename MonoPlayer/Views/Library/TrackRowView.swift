import SwiftUI

/// Строка списка: обложка 48pt, название, «артист · длительность», статус обогащения.
struct TrackRowView: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            ZStack {
                ArtworkView(
                    fileName: track.artworkFileName,
                    size: Theme.Size.rowArtwork,
                    cornerRadius: Theme.Radius.rowArtwork,
                    isLoading: track.isEnriching
                )
                // Волна — только пока трек действительно играет; на паузе исчезает
                if isCurrent && isPlaying {
                    RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork, style: .continuous)
                        .fill(.black.opacity(0.4))
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .transition(.opacity)
                }
            }
            .frame(width: Theme.Size.rowArtwork, height: Theme.Size.rowArtwork)
            .animation(.easeInOut(duration: 0.2), value: isCurrent && isPlaying)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(isCurrent ? .body.weight(.semibold) : .body)
                        .foregroundStyle(Theme.Colors.labelPrimary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                }
                Spacer(minLength: 0)
                statusIcon
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(track.title), \(track.artist), \(track.duration.playbackTime)")
        .accessibilityValue(isCurrent ? (isPlaying ? "Играет" : "На паузе") : "")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        track.duration > 0 ? "\(track.artist) · \(track.duration.playbackTime)" : track.artist
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch track.enrichmentStatus {
        case .pending, .enriching:
            Image(systemName: "sparkles")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.labelSecondary)
                .symbolEffect(.pulse)
                .accessibilityLabel("Ищем обложку и текст")
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.labelTertiary)
                .accessibilityLabel("Не удалось найти данные")
        case .completed, .partial:
            EmptyView()
        }
    }
}

/// Строка трека внутри альбома: номер вместо обложки.
struct AlbumTrackRow: View {
    let index: Int
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if isCurrent && isPlaying {
                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .symbolEffect(.variableColor.iterative, isActive: true)
                } else {
                    Text("\(index)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Theme.Colors.labelSecondary)
                }
            }
            .frame(width: 28)

            Text(track.title)
                .font(isCurrent ? .body.weight(.semibold) : .body)
                .lineLimit(2)
            Spacer(minLength: 8)
            if track.duration > 0 {
                Text(track.duration.playbackTime)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.Colors.labelSecondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index). \(track.title), \(track.duration.playbackTime)")
        .accessibilityAddTraits(.isButton)
    }
}
