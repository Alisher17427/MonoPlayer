import SwiftUI

/// Караоке-текст: активная строка на 1/3 высоты, остальные приглушены и слегка размыты.
/// Ручной скролл ставит автоскролл на паузу на 3 секунды, тап по строке — перемотка.
struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let plainLyrics: String?

    var body: some View {
        if !lines.isEmpty {
            SyncedLines(lines: lines)
        } else if let plainLyrics, !plainLyrics.isEmpty {
            ScrollView {
                Text(plainLyrics)
                    .font(.title2.bold())
                    .lineSpacing(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.player)
                    .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        } else {
            ContentUnavailableView(
                "Текст недоступен",
                systemImage: "quote.bubble",
                description: Text("Для этого трека не нашлось текста на LRCLIB.")
            )
        }
    }
}

private struct SyncedLines: View {
    let lines: [LyricLine]

    @Environment(AudioPlayerManager.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var autoScrollPaused = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var tapTick = 0

    private var activeIndex: Int? {
        // Небольшое опережение, чтобы строка подсвечивалась вместе с голосом
        lines.lastIndex { $0.time <= player.currentTime + 0.15 }
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
                                    player.seek(to: line.time)
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
