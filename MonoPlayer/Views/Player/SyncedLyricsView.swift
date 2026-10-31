import SwiftUI

/// Караоке-текст: активная строка на 1/3 высоты, остальные приглушены и слегка размыты.
/// Ручной скролл ставит автоскролл на паузу на 3 секунды, тап по строке — перемотка.
/// Если синхронизированного текста нет — показывается обычный с подсказкой найти другой.
struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let plainLyrics: String?
    var offset: TimeInterval = 0
    var isSearching = false
    var onFindLyrics: () -> Void = {}

    var body: some View {
        if !lines.isEmpty {
            SyncedLines(lines: lines, offset: offset)
        } else if let plainLyrics, !plainLyrics.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    notice
                    Text(plainLyrics)
                        .font(.title2.bold())
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Theme.Spacing.player)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        } else if isSearching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Ищем текст…").foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Текст недоступен", systemImage: "quote.bubble")
            } description: {
                Text("Автопоиск не нашёл текст этого трека.")
            } actions: {
                Button("Найти вручную", action: onFindLyrics)
                    .buttonStyle(.bordered)
            }
        }
    }

    /// Найден только обычный текст — синхронизировать его не с чем.
    private var notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.alignleft")
            VStack(alignment: .leading, spacing: 6) {
                Text("Синхронизированный текст не найден — показан обычный.")
                    .font(.subheadline)
                Button("Найти синхронизированный", action: onFindLyrics)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SyncedLines: View {
    let lines: [LyricLine]
    let offset: TimeInterval

    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var autoScrollPaused = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var tapTick = 0

    /// Небольшое опережение, чтобы строка подсвечивалась вместе с голосом, плюс ручная подстройка.
    private var lyricsTime: TimeInterval { player.currentTime + 0.15 + offset }

    private var activeIndex: Int? {
        lines.lastIndex { $0.time <= lyricsTime }
    }

    var body: some View {
        let active = activeIndex
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lineView(line, index: index, active: active)
                                .id(index)
                                .onTapGesture {
                                    tapTick += 1
                                    player.seek(to: max(0, line.time - offset))
                                    if !player.isPlaying { player.play() }
                                    resumeAutoScroll(proxy: proxy, immediately: true)
                                }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.player)
                    .padding(.top, geo.size.height * 0.33)
                    .padding(.bottom, geo.size.height * 0.6)
                }
                .scrollIndicators(.hidden)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { _ in
                        autoScrollPaused = true
                        resumeAutoScroll(proxy: proxy, immediately: false)
                    }
                )
                .onChange(of: active) { _, newValue in
                    guard !autoScrollPaused, let newValue else { return }
                    scroll(proxy, to: newValue)
                }
                .onAppear {
                    if let active { proxy.scrollTo(active, anchor: UnitPoint(x: 0, y: 0.33)) }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapTick)
        .onDisappear { resumeTask?.cancel() }
    }

    private func lineView(_ line: LyricLine, index: Int, active: Int?) -> some View {
        let isActive = index == active
        let distance = active.map { abs(index - $0) } ?? 0
        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.title.bold())
            .foregroundStyle(.white)
            .opacity(isActive ? 1 : (index < (active ?? 0) ? 0.45 : 0.35))
            .scaleEffect(isActive ? 1 : 0.97, anchor: .leading)
            .blur(radius: (!reduceMotion && distance > 2 && !autoScrollPaused) ? 1.5 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(Theme.Motion.lyrics, value: isActive)
            .accessibilityLabel(line.text.isEmpty ? "Проигрыш" : line.text)
            .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint("Перемотать к этой строке")
    }

    private func scroll(_ proxy: ScrollViewProxy, to index: Int) {
        let anchor = UnitPoint(x: 0, y: 0.33)
        if reduceMotion {
            proxy.scrollTo(index, anchor: anchor)
        } else {
            withAnimation(Theme.Motion.lyrics) { proxy.scrollTo(index, anchor: anchor) }
        }
    }

    private func resumeAutoScroll(proxy: ScrollViewProxy, immediately: Bool) {
        resumeTask?.cancel()
        resumeTask = Task {
            if !immediately {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
            }
            autoScrollPaused = false
            if let activeIndex { scroll(proxy, to: activeIndex) }
        }
    }
}
