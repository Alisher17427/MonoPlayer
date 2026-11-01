import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SearchQuery.splitAmpersandKey) private var splitAmpersand = true
    @Environment(\.dismiss) private var dismiss
    @Environment(EnrichmentCoordinator.self) private var enrichment
    @Query private var tracks: [Track]
    @State private var showsRefreshOptions = false
    @State private var nothingMissing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Треков", value: "\(tracks.count)")
                    LabeledContent("С текстом", value: "\(tracks.filter(\.hasLyrics).count)")
                    LabeledContent("Любимых", value: "\(tracks.filter(\.isFavorite).count)")
                    Toggle("Разделять исполнителей по «&»", isOn: $splitAmpersand)
                } header: {
                    Text("Медиатека")
                } footer: {
                    Text("Исполнители всегда разделяются по запятой, «feat.», «ft.» и «x». Выключите «&», если в медиатеке есть дуэты вроде «Simon & Garfunkel».")
                }
                refreshSection
                Section {
                    LabeledContent("Метаданные и обложки", value: "Genius")
                    LabeledContent("Тексты песен", value: "Genius")
                    LabeledContent("Таймкоды текста", value: "LRCLIB")
                    LabeledContent("Фото исполнителей", value: "Deezer")
                } header: {
                    Text("Источники данных")
                } footer: {
                    Text("Все файлы, обложки и тексты хранятся только на этом iPhone.")
                }
            }
            .alert("Всё уже найдено", isPresented: $nothingMissing) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("У всех треков есть обложка и текст. Чтобы найти их заново, выберите «Обложки и текст заново».")
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    // MARK: - Обновление медиатеки

    private var refreshSection: some View {
        Section {
            if enrichment.remaining > 0 {
                let total = max(enrichment.batchTotal, enrichment.remaining)
                let done = total - enrichment.remaining
                VStack(alignment: .leading, spacing: 8) {
                    Text("Обновление: \(done) из \(total)")
                    ProgressView(value: Double(done), total: Double(total))
                        .tint(Theme.Colors.tint)
                }
                .padding(.vertical, 4)
                Button("Остановить", systemImage: "stop.circle", role: .destructive) {
                    enrichment.cancelQueue()
                }
            } else {
                Button {
                    showsRefreshOptions = true
                } label: {
                    Label("Обновить всю медиатеку", systemImage: "arrow.clockwise")
                }
                .disabled(tracks.isEmpty)
                .confirmationDialog("Обновить медиатеку", isPresented: $showsRefreshOptions, titleVisibility: .visible) {
                    Button("Найти недостающее") {
                        if enrichment.fillMissing(tracks) == 0 { nothingMissing = true }
                    }
                    Button("Обложки и текст заново") { enrichment.refreshLibrary(tracks, artwork: true, lyrics: true) }
                    Button("Только обложки заново") { enrichment.refreshLibrary(tracks, artwork: true, lyrics: false) }
                    Button("Только текст заново") { enrichment.refreshLibrary(tracks, artwork: false, lyrics: true) }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("«Найти недостающее» — только треки без обложки или текста. Остальные варианты ищут заново для всех \(tracks.count) треков.")
                }
            }
        } header: {
            Text("Обновление")
        } footer: {
            Text("Если новое не нашлось, старая обложка и текст остаются. Поставленные вручную обложки и тексты, как и исправленные вручную названия, не заменяются. Обновление идёт в фоне — настройки можно закрыть.")
        }
    }
}
