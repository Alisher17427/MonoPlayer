import Foundation

/// Название альбома + исполнитель альбома. Исполнитель служит и для показа, и как подсказка при поиске альбома.
struct AlbumKey: Hashable, Codable, Sendable {
    let title: String
    let artist: String
}

struct AlbumSummary: Identifiable {
    let key: AlbumKey
    let tracks: [Track]
    /// Нормализованные исполнители всех треков альбома
    let artistKeys: Set<String>

    var id: AlbumKey { AlbumKey(title: key.title.lowercased(), artist: key.artist.lowercased()) }
    var artworkFileName: String? { tracks.first { $0.artworkFileName != nil }?.artworkFileName }
    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
    var newestDate: Date { tracks.map(\.dateAdded).max() ?? .distantPast }
}

struct ArtistSummary: Identifiable {
    let name: String
    /// Все треки артиста, включая совместные
    let tracks: [Track]
    /// Альбомы, где он — исполнитель альбома
    let albums: [AlbumSummary]
    /// Чужие альбомы, где есть его треки («Участие»)
    let appearsOn: [AlbumSummary]

    var id: String { ArtistSummary.key(for: name) }
    var artworkFileName: String? { tracks.first { $0.artworkFileName != nil }?.artworkFileName }

    static func key(for name: String) -> String { name.lowercased().trimmingCharacters(in: .whitespaces) }
}

/// Альбомы и артисты, вычисленные из треков (отдельных сущностей в SwiftData нет).
///
/// Альбом = треки с одинаковым названием альбома, связанные общим исполнителем:
/// «rocket» и «rocket, lildrughill» с альбомом «X» — один альбом, а два разных
/// «Greatest Hits» у разных артистов — разные.
enum LibraryIndex {
    static func albums(from tracks: [Track]) -> [AlbumSummary] {
        var byTitle: [String: [Track]] = [:]
        var titleOrder: [String] = []
        for track in tracks {
            guard let title = track.album?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
            let key = title.lowercased()
            if byTitle[key] == nil { titleOrder.append(key) }
            byTitle[key, default: []].append(track)
        }

        var result: [AlbumSummary] = []
        for titleKey in titleOrder {
            for cluster in clusters(byTitle[titleKey] ?? []) {
                let sorted = cluster.sorted { $0.dateAdded < $1.dateAdded }
                let title = sorted.first?.album ?? titleKey
                result.append(AlbumSummary(
                    key: AlbumKey(title: title, artist: albumArtist(of: sorted)),
                    tracks: sorted,
                    artistKeys: sorted.reduce(into: Set<String>()) { $0.formUnion($1.artistKeys) }
                ))
            }
        }
        return result.sorted { $0.key.title.localizedStandardCompare($1.key.title) == .orderedAscending }
    }

    static func artists(from tracks: [Track]) -> [ArtistSummary] {
        let allAlbums = albums(from: tracks)
        var names: [String: String] = [:]      // ключ → имя для показа (первое встреченное написание)
        var grouped: [String: [Track]] = [:]
        for track in tracks {
            for name in track.artists {
                let key = ArtistSummary.key(for: name)
                if names[key] == nil { names[key] = name }
                grouped[key, default: []].append(track)
            }
        }
        return grouped.compactMap { key, group in
            guard let name = names[key] else { return nil }
            return makeArtist(key: key, name: name, tracks: group, allAlbums: allAlbums)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func artist(named name: String, in tracks: [Track]) -> ArtistSummary? {
        let key = ArtistSummary.key(for: name)
        let group = tracks.filter { track in track.artists.contains { ArtistSummary.key(for: $0) == key } }
        guard !group.isEmpty else { return nil }
        let displayName = group.lazy.flatMap(\.artists).first { ArtistSummary.key(for: $0) == key } ?? name
        return makeArtist(key: key, name: displayName, tracks: group, allAlbums: albums(from: tracks))
    }

    /// Альбом по названию; при нескольких одноимённых — тот, где есть исполнитель из ключа.
    static func album(_ key: AlbumKey, in tracks: [Track]) -> AlbumSummary? {
        let title = key.title.lowercased()
        let candidates = albums(from: tracks.filter { $0.album?.trimmingCharacters(in: .whitespaces).lowercased() == title })
        let artistKey = ArtistSummary.key(for: key.artist)
        return candidates.first { ArtistSummary.key(for: $0.key.artist) == artistKey }
            ?? candidates.first { $0.artistKeys.contains(artistKey) }
            ?? candidates.first
    }

    /// Альбомы в порядке добавления (сначала новые).
    static func recentAlbums(from tracks: [Track], limit: Int) -> [AlbumSummary] {
        Array(albums(from: tracks).sorted { $0.newestDate > $1.newestDate }.prefix(limit))
    }

    // MARK: - Внутреннее

    private static func makeArtist(key: String, name: String, tracks: [Track], allAlbums: [AlbumSummary]) -> ArtistSummary {
        let own = allAlbums.filter { ArtistSummary.key(for: $0.key.artist) == key }
        let appears = allAlbums.filter { ArtistSummary.key(for: $0.key.artist) != key && $0.artistKeys.contains(key) }
        return ArtistSummary(
            name: name,
            tracks: tracks.sorted { $0.dateAdded > $1.dateAdded },
            albums: own,
            appearsOn: appears
        )
    }

    /// Разбивает треки одного названия альбома на группы, связанные общими исполнителями.
    private static func clusters(_ tracks: [Track]) -> [[Track]] {
        var groups: [(keys: Set<String>, tracks: [Track])] = []
        var unknown: [Track] = []
        for track in tracks {
            let keys = track.artistKeys
            guard !keys.isEmpty else { unknown.append(track); continue }
            let overlapping = groups.indices.filter { !groups[$0].keys.isDisjoint(with: keys) }
            var merged = (keys: keys, tracks: [track])
            for index in overlapping.reversed() {
                merged.keys.formUnion(groups[index].keys)
                merged.tracks.append(contentsOf: groups[index].tracks)
                groups.remove(at: index)
            }
            groups.append(merged)
        }
        // Треки без исполнителя — к первой группе этого альбома (или отдельной группой)
        if !unknown.isEmpty {
            if groups.isEmpty { groups.append((keys: [], tracks: unknown)) } else { groups[0].tracks.append(contentsOf: unknown) }
        }
        return groups.map(\.tracks)
    }

    /// Исполнитель альбома: явный тег/правка, иначе самый частый исполнитель треков.
    private static func albumArtist(of tracks: [Track]) -> String {
        let explicit = tracks.compactMap { $0.albumArtist?.trimmingCharacters(in: .whitespaces).nilIfEmpty }
        if let value = mostCommon(explicit) { return value }
        let all = tracks.flatMap(\.artists)
        return mostCommon(all) ?? tracks.first?.artist ?? Track.unknownArtist
    }

    /// Самое частое значение (без учёта регистра); при равенстве — встреченное раньше.
    private static func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        var first: [String: String] = [:]
        var order: [String] = []
        for value in values {
            let key = ArtistSummary.key(for: value)
            if first[key] == nil { first[key] = value; order.append(key) }
            counts[key, default: 0] += 1
        }
        let best = order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
        return best.flatMap { first[$0] }
    }
}
