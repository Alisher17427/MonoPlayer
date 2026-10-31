import SwiftData
import SwiftUI

@main
struct MonoPlayerApp: App {
    @State private var player = AudioPlayerManager()
    @State private var enrichment = EnrichmentCoordinator()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: Track.self)
        } catch {
            fatalError("Не удалось открыть хранилище SwiftData: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(enrichment)
                .tint(Theme.Colors.tint)
                // Приложение всегда в тёмной теме
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
