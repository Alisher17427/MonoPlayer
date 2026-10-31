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
                if isCurrent {
                    RoundedRectangle(cornerRadius: Theme.Radius.rowArtwork, style: .continuous)
                        .fill(.black.opacity(0.4))
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }
            .frame(width: Theme.Size.rowArtwork, height: Theme.Size.rowArtwork)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body)
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
