import SwiftUI

/// Фон Now Playing из палитры обложки: медленный MeshGradient на iOS 18+,
/// размытая обложка на iOS 17. Всегда затемнён настолько, чтобы белый текст читался.
struct NowPlayingBackground: View {
    let track: Track

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = track.palette.isEmpty ? Theme.Colors.fallbackPalette : track.palette
        ZStack {
            Color.black
            if #available(iOS 18, *) {
                if reduceMotion {
                    MeshBackground(colors: colors, time: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        MeshBackground(colors: colors, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            } else {
                BlurredArtwork(fileName: track.artworkFileName, fallback: colors)
            }
            // Затемнение: базовое + усиленное для светлых обложек (контраст WCAG AA)
            Color.black.opacity(ArtworkPalette.luminance(ofHex: track.paletteHex) > 0.6 ? 0.4 : 0.18)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: track.paletteHex)
    }
}

@available(iOS 18, *)
private struct MeshBackground: View {
    let colors: [Color]
    let time: TimeInterval

    var body: some View {
        let t = time * 0.25
        let wobble: (Double) -> Float = { phase in Float(sin(t + phase) * 0.12) }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + wobble(0), 0], [1, 0],
            [0, 0.5 + wobble(1)], [0.5 + wobble(2), 0.5 + wobble(3)], [1, 0.5 + wobble(4)],
            [0, 1], [0.5 + wobble(5), 1], [1, 1],
        ]
        let c = colors
        let pick: (Int) -> Color = { c[$0 % c.count] }
        MeshGradient(
            width: 3, height: 3,
            points: points,
            colors: [
                pick(0), pick(1), pick(2),
                pick(1), pick(0).opacity(0.85), pick(2),
                pick(2), pick(0), pick(1),
            ]
        )
    }
}

private struct BlurredArtwork: View {
    let fileName: String?
    let fallback: [Color]
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: fallback, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 60)
                    .scaleEffect(1.4)
            }
        }
        .task(id: fileName) {
            guard let fileName else { image = nil; return }
            image = await ArtworkLoader.image(named: fileName, maxPixelSize: 200)
        }
    }
}
