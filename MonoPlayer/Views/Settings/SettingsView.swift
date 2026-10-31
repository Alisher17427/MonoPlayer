import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage(SearchQuery.splitAmpersandKey) private var splitAmpersand = true
    @Environment(\.dismiss) private var dismiss
    @Query private var tracks: [Track]

    var body: some View {
        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    LabeledContent("Треков", value: "\(tracks.count)")
                    LabeledContent("С текстом", value: "\(tracks.filter(\.hasLyrics).count)")
                    Toggle("Разделять исполнителей по «&»", isOn: $splitAmpersand)
                } header: {
                    Text("Медиатека")
                } footer: {
                    Text("Исполнители всегда разделяются по запятой, «feat.», «ft.» и «x». Выключите «&», если в медиатеке есть дуэты вроде «Simon & Garfunkel».")
                }
                Section {
                    LabeledContent("Метаданные и обложки", value: "iTunes, Deezer, MusicBrainz")
                    LabeledContent("Тексты песен", value: "LRCLIB, lyrics.ovh")
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
