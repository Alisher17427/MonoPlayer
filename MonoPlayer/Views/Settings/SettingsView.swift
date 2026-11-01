import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(SearchQuery.splitAmpersandKey) private var splitAmpersand = true
    @Environment(\.dismiss) private var dismiss
    @Query private var tracks: [Track]

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
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
