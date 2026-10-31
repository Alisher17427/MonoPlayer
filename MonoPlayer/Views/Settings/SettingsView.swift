import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
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
                Section("Медиатека") {
                    LabeledContent("Треков", value: "\(tracks.count)")
                    LabeledContent("С текстом", value: "\(tracks.filter(\.hasLyrics).count)")
                }
                Section {
                    LabeledContent("Метаданные и обложки", value: "iTunes Search API")
                    LabeledContent("Тексты песен", value: "LRCLIB")
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
