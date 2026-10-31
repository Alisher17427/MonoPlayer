import AVKit
import MediaPlayer
import SwiftUI

/// Полноэкранный плеер (Now Playing). Всегда тёмный поверх цветного фона из обложки.
struct FullPlayerView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var editingTrack: Track?
    @State private var lyricLines: [LyricLine] = []
    @Namespace private var artworkSpace

    var body: some View {
        Group {
            if let track = player.currentTrack {
                content(for: track)
                    .task(id: "\(track.id)-\(track.syncedLyricsRaw?.count ?? 0)") {
                        lyricLines = LRCParser.parse(track.syncedLyricsRaw)
                    }
            } else {
                Color.black.ignoresSafeArea()
                    .onAppear { dismiss() }
            }
        }
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showQueue) { QueueView() }
        .sheet(item: $editingTrack) { EditTrackView(track: $0) }
    }

    private func content(for track: Track) -> some View {
        GeometryReader { geo in
            let artworkSide = max(120, min(geo.size.width - Theme.Spacing.player * 2, geo.size.height * 0.42))

            VStack(spacing: 0) {
                if showLyrics {
                    compactHeader(track)
                        .padding(.top, 28)
                    SyncedLyricsView(lines: lyricLines, plainLyrics: track.plainLyrics)
                        .frame(maxHeight: .infinity)
                        .mask(
                            LinearGradient(
                                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                        .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .transition(.opacity)
                } else {
                    Spacer(minLength: 28)
                    ArtworkView(
                        fileName: track.artworkFileName,
                        size: artworkSide,
                        cornerRadius: Theme.Radius.playerArtwork,
                        isLoading: track.isEnriching
                    )
                    .matchedGeometryEffect(id: "artwork", in: artworkSpace)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .scaleEffect(player.isPlaying ? 1 : 0.85)
                    .animation(Theme.Motion.artwork, value: player.isPlaying)
                    Spacer(minLength: 24)
                    titleRow(track)
                        .padding(.horizontal, Theme.Spacing.player)
                }

                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 20) {
                    ScrubberView()
                    TransportControls()
                    VolumeSlider()
                        .frame(height: 34)
                    bottomRow(track)
                }
                .padding(.horizontal, Theme.Spacing.player)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .foregroundStyle(.white)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { NowPlayingBackground(track: track) }
        .animation(Theme.Motion.screen, value: showLyrics)
    }

    // MARK: - Части экрана

    private func compactHeader(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(fileName: track.artworkFileName, size: 52, cornerRadius: 8)
                .matchedGeometryEffect(id: "artwork", in: artworkSpace)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.headline).lineLimit(1)
                Text(track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            trackMenu(track)
        }
        .padding(.horizontal, Theme.Spacing.player)
        .padding(.bottom, 8)
    }

    private func titleRow(_ track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: track.title, font: .title3.weight(.semibold))
                MarqueeText(text: track.artist, font: .title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            trackMenu(track)
        }
    }

    private func trackMenu(_ track: Track) -> some View {
        Menu {
            Button("Изменить сведения", systemImage: "pencil") { editingTrack = track }
            Button("Обновить обложку и текст", systemImage: "arrow.clockwise") {
                enrichment.refresh(track, resetArtwork: true)
            }
            ShareLink(item: track.audioURL) {
                Label("Поделиться файлом", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title2)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
        }
        .accessibilityLabel("Действия с треком")
    }

    private func bottomRow(_ track: Track) -> some View {
        HStack {
            Button {
                showLyrics.toggle()
            } label: {
                Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.title3)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
            }
            .accessibilityLabel(showLyrics ? "Скрыть текст" : "Показать текст")
            .sensoryFeedback(.selection, trigger: showLyrics)

            Spacer()
            AirPlayButton()
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .accessibilityLabel("AirPlay")
            Spacer()

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
            }
            .accessibilityLabel("Очередь")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
    }
}

// MARK: - Кнопки транспорта

private struct TransportControls: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var backTick = 0
    @State private var forwardTick = 0

    var body: some View {
        HStack {
            Spacer()
            Button {
                backTick += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .symbolEffect(.bounce, value: backTick)
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel("Предыдущий трек")
            Spacer()
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
            }
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
            .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
            Spacer()
            Button {
                forwardTick += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .symbolEffect(.bounce, value: forwardTick)
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel("Следующий трек")
            Spacer()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

// MARK: - Бегущая строка

/// Длинное название плавно прокручивается с паузой 2 с у края; при Reduce Motion — обрезка.
struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let gap: CGFloat = 40
    private var overflows: Bool { textWidth > containerWidth + 1 && containerWidth > 0 }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            .overlay(alignment: .leading) {
                if overflows && !reduceMotion {
                    HStack(spacing: gap) {
                        Text(text).font(font).fixedSize()
                        Text(text).font(font).fixedSize()
                    }
                    .offset(x: offset)
                    .frame(width: containerWidth, alignment: .leading)
                    .clipped()
                    .mask(
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                               .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                } else {
                    Text(text).font(font).lineLimit(1).truncationMode(.tail)
                }
            }
            .background(
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            )
            .task(id: "\(text)-\(overflows)-\(reduceMotion)") {
                offset = 0
                guard overflows, !reduceMotion else { return }
                let distance = textWidth + gap
                let duration = Double(distance) / 30
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: duration)) { offset = -distance }
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    offset = 0
                }
            }
            .accessibilityLabel(text)
    }
}

// MARK: - Системные контролы

/// Системный ползунок громкости (на симуляторе не отображается — это нормально).
private struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white.withAlphaComponent(0.75)
        view.activeTintColor = .white
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Очередь

private struct QueueView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.currentTrack {
                    Section("Сейчас играет") {
                        TrackRowView(track: current, isCurrent: true, isPlaying: player.isPlaying)
                    }
                }
                Section("Далее") {
                    if player.upNext.isEmpty {
                        Text("Очередь пуста").foregroundStyle(Theme.Colors.labelSecondary)
                    }
                    ForEach(player.upNext) { track in
                        Button {
                            player.play(track, in: player.queue)
                        } label: {
                            TrackRowView(track: track, isCurrent: false, isPlaying: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Очередь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
