import SwiftUI

/// Плавающая капсула над таб-баром. На iOS 26 живёт в `tabViewBottomAccessory`
/// (стекло рисует система), на iOS 17–25 — в `safeAreaInset` со своим материалом.
struct MiniPlayerView: View {
    var inAccessory = false
    let namespace: Namespace.ID
    let onOpen: () -> Void

    @Environment(AudioPlayerManager.self) private var player
    @State private var skipTick = 0

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                ArtworkView(
                    fileName: track.artworkFileName,
                    size: inAccessory ? 32 : Theme.Size.miniArtwork,
                    cornerRadius: Theme.Radius.miniArtwork,
                    isLoading: track.isEnriching
                )
                .zoomTransitionSource(id: "artwork", in: namespace)

                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.labelSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                }
                .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")

                Button {
                    skipTick += 1
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .symbolEffect(.bounce, value: skipTick)
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                }
                .accessibilityLabel("Следующий трек")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.labelPrimary)
            .padding(.leading, inAccessory ? 10 : 8)
            .padding(.trailing, 4)
            .frame(height: inAccessory ? nil : Theme.Size.miniPlayerHeight)
            .background(alignment: .bottom) {
                if !inAccessory { progressLine(tint: track.palette.first) }
            }
            .modifier(MiniPlayerChrome(enabled: !inAccessory))
            .contentShape(Capsule())
            .onTapGesture(perform: onOpen)
            .gesture(swipeGesture)
            .sensoryFeedback(.selection, trigger: track.id)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Мини-плеер: \(track.title), \(track.artist)")
            .accessibilityAction(named: "Открыть плеер", onOpen)
        }
    }

    /// Свайп влево/вправо — переключение трека, вверх — открыть плеер.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if abs(dx) > abs(dy) {
                    if dx < -50 { player.next() } else if dx > 50 { player.previous() }
                } else if dy < -30 {
                    onOpen()
                }
            }
    }

    private func progressLine(tint: Color?) -> some View {
        MiniProgress(tint: tint ?? Theme.Colors.tint)
            .padding(.horizontal, 20)
            .padding(.bottom, 1)
    }
}

/// Отдельная вьюха, чтобы тик прогресса (5 раз в секунду) не перерисовывал всю капсулу.
private struct MiniProgress: View {
    let tint: Color
    @Environment(AudioPlayerManager.self) private var player

    var body: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
            Capsule()
                .fill(tint)
                .frame(width: geo.size.width * progress, height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

private struct MiniPlayerChrome: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .glassCapsule()
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        } else {
            content
        }
    }
}
