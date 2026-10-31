import SwiftUI

/// Интерактивный прогресс-бар: капсула 6pt, при касании расширяется до 12pt.
struct ScrubberView: View {
    @Environment(AudioPlayerManager.self) private var player
    @State private var dragProgress: Double?
    @State private var edgeTick = 0

    private var isDragging: Bool { dragProgress != nil }

    var body: some View {
        let duration = player.duration
        let progress = dragProgress ?? (duration > 0 ? min(1, player.currentTime / duration) : 0)
        let elapsed = progress * duration

        VStack(spacing: isDragging ? 8 : 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.22))
                    Capsule().fill(Color.primary).frame(width: max(0, geo.size.width * progress))
                }
                .frame(height: isDragging ? 12 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let newValue = Double(min(1, max(0, value.location.x / geo.size.width)))
                            if (newValue == 0 || newValue == 1), newValue != dragProgress { edgeTick += 1 }
                            dragProgress = newValue
                        }
                        .onEnded { _ in
                            if let dragProgress { player.seek(to: dragProgress * duration) }
                            dragProgress = nil
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text(elapsed.playbackTime)
                Spacer()
                Text("-" + max(0, duration - elapsed).playbackTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(isDragging ? Color.primary : Color.secondary)
            .scaleEffect(isDragging ? 1.08 : 1)
        }
        .animation(Theme.Motion.controls, value: isDragging)
        .sensoryFeedback(.impact(weight: .light), trigger: edgeTick)
        .accessibilityElement()
        .accessibilityLabel("Позиция воспроизведения")
        .accessibilityValue("\(elapsed.playbackTime) из \(duration.playbackTime)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: player.seek(to: player.currentTime + 10)
            case .decrement: player.seek(to: player.currentTime - 10)
            @unknown default: break
            }
        }
    }
}
