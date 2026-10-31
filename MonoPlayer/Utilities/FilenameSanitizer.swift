import Foundation

/// Превращает «мусорное» имя файла вроде
/// `01_Artist_-_Song_(Official_Video)_320kbps.mp3` в пару «артист / название».
enum FilenameSanitizer {
    struct Result: Equatable, Sendable {
        let artist: String?
        let title: String
    }

    static func parse(_ fileName: String) -> Result {
        var name = (fileName as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")

        let junk = "official|video|audio|lyric|lyrics|visuali[sz]er|hd|hq|4k|prod\\.?|kbps|download|mp3|clip|клип|премьера|текст"
        let rules: [(pattern: String, template: String)] = [
            // (Official Video), [Lyrics], {prod. by X}
            ("\\s*[\\(\\[\\{][^\\)\\]\\}]*\\b(\(junk))\\b[^\\)\\]\\}]*[\\)\\]\\}]", ""),
            // 320kbps, 320 kbps
            ("\\b\\d{2,3}\\s?kbps\\b", ""),
            // одиночные мусорные слова
            ("\\b(free download|download|lyrics|hq|hd)\\b", ""),
            // адреса сайтов
            ("\\b(www\\.)?[a-z0-9-]+\\.(com|net|org|ru|io|me|cc|fm)\\b", ""),
            // номер трека в начале: "01. ", "01 - ", "1) "
            ("^\\s*\\d{1,3}\\s*[\\.\\-\\)]\\s+", ""),
            // "01 Song" — только номера с ведущим нулём, чтобы не съесть "50 Cent"
            ("^\\s*0\\d\\s+", ""),
            // любые тире, окружённые пробелами -> единый разделитель
            ("\\s+[-–—]+\\s+", " - "),
            // пустые скобки, оставшиеся после чистки
            ("[\\(\\[\\{]\\s*[\\)\\]\\}]", ""),
            ("\\s{2,}", " "),
        ]
        for rule in rules {
            name = replace(rule.pattern, in: name, with: rule.template)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -–—.").union(.whitespacesAndNewlines))

        let parts = name.components(separatedBy: " - ")
        if parts.count >= 2 {
            let artist = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if !artist.isEmpty, !title.isEmpty {
                return Result(artist: artist, title: title)
            }
        }
        return Result(artist: nil, title: name.isEmpty ? fileName : name)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
