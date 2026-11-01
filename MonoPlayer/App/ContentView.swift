import SwiftData
import SwiftUI

/// Корневой TabView с мини-плеером (bottom accessory на iOS 26 / поверх контента на iOS 17–25).
struct ContentView: View {
    @Environment(AudioPlayerManager.self) private var player
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    @State private var media = ArtistMediaStore()
    @Namespace private var transitionSpace

    var body: some View {
        @Bindable var router = router
        tabs
            .environment(router)
            .environment(media)
            .sheet(isPresented: $router.showPlayer) {
                FullPlayerView()
                    .environment(router)
                    .environment(media)
                    .presentationDragIndicator(.visible)
                    .zoomTransitionDestination(id: "artwork", in: transitionSpace)
            }
            .sheet(item: $router.editingTrack) { track in
                EditTrackView(track: track)
            }
            .task {
                Storage.prepare()
                enrichment.attach(modelContext)
                importInbox()
            }
            // Импорт через «Поделиться» / «Открыть в…»: вместе с присланным — всё, что ждёт в Inbox
            .onOpenURL { url in
                let others = FileImportService.pendingInboxFiles().filter { $0.standardizedFileURL != url.standardizedFileURL }
                FileImportService.importFiles([url] + others, into: modelContext, enrichment: enrichment)
                router.selectedTab = .library
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { importInbox() }
            }
            // Обогащение завершилось для играющего трека — обновляем экран блокировки
            .onChange(of: nowPlayingSignature) {
                player.updateNowPlayingInfo()
            }
    }

    /// Файлы из «Поделиться», до которых не дошёл `onOpenURL`.
    private func importInbox() {
        let pending = FileImportService.pendingInboxFiles()
        guard !pending.isEmpty else { return }
        FileImportService.importFiles(pending, into: modelContext, enrichment: enrichment)
        router.selectedTab = .library
    }

    private var nowPlayingSignature: String {
        guard let track = player.currentTrack else { return "" }
        return "\(track.id)|\(track.title)|\(track.artist)|\(track.album ?? "")|\(track.artworkFileName ?? "")"
    }

    @ViewBuilder
    private var tabs: some View {
        #if compiler(>=6.2) // Xcode 26+: нижний аксессуар таб-бара и сворачивание при скролле
        if #available(iOS 26, *) {
            let tabView = TabView(selection: Bindable(router).selectedTab) {
                Tab("Медиатека", systemImage: "music.note.list", value: AppTab.library) {
                    LibraryView()
                }
                Tab(value: AppTab.search, role: .search) {
                    SearchView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)

            if player.currentTrack != nil {
                tabView.tabViewBottomAccessory {
                    MiniPlayerView(inAccessory: true, namespace: transitionSpace) { router.showPlayer = true }
                }
            } else {
                tabView
            }
        } else {
            legacyTabs
        }
        #else
        legacyTabs
        #endif
    }

    /// iOS 17–25 (и сборки на Xcode 16): мини-плеер поверх контента над таб-баром.
    /// Место под него резервирует каждый экран (`reservesMiniPlayerSpace`): safeAreaInset снаружи
    /// NavigationStack на iOS 17 не доходит до вложенных экранов, и последний трек уходил под плеер.
    private var legacyTabs: some View {
        TabView(selection: Bindable(router).selectedTab) {
            LibraryView()
                .overlay(alignment: .bottom) { legacyMiniPlayer }
                .tabItem { Label("Медиатека", systemImage: "music.note.list") }
                .tag(AppTab.library)
            SearchView()
                .overlay(alignment: .bottom) { legacyMiniPlayer }
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(AppTab.search)
        }
    }

    @ViewBuilder
    private var legacyMiniPlayer: some View {
        if player.currentTrack != nil {
            MiniPlayerView(namespace: transitionSpace) { router.showPlayer = true }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
