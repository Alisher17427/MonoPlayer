import SwiftUI

/// Токены дизайн-системы Graphite. Только семантические системные цвета —
/// приложение всегда в тёмной теме, а цвета подстраиваются под режим повышенной контрастности.
enum Theme {
    enum Colors {
        static let bgPrimary = Color(.systemBackground)
        static let bgSecondary = Color(.secondarySystemBackground)
        static let bgTertiary = Color(.tertiarySystemBackground)
        static let labelPrimary = Color.primary
        static let labelSecondary = Color.secondary
        static let labelTertiary = Color(.tertiaryLabel)
        static let separator = Color(.separator)
        static let tint = Color.primary
        static let destructive = Color.red

        /// Запасная палитра Now Playing, если у трека нет обложки.
        static let fallbackPalette: [Color] = [Color(white: 0.22), Color(white: 0.12), Color(white: 0.30)]
    }

    enum Radius {
        static let rowArtwork: CGFloat = 6
        static let miniArtwork: CGFloat = 6
        static let playerArtwork: CGFloat = 14
    }

    enum Spacing {
        static let screen: CGFloat = 16
        static let player: CGFloat = 24
    }

    enum Size {
        static let rowArtwork: CGFloat = 48
        static let miniArtwork: CGFloat = 40
        static let miniPlayerHeight: CGFloat = 56
        static let minTapTarget: CGFloat = 44
    }

    enum Motion {
        static let artwork = Animation.spring(duration: 0.5, bounce: 0.2)
        static let lyrics = Animation.spring(duration: 0.5)
        static let controls = Animation.snappy
        static let screen = Animation.smooth
    }
}
