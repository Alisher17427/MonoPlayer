import Foundation

struct AlbumKey: Hashable, Codable, Sendable {
    let title: String
    let artist: String
}

struct AlbumSummary: Identifiable {
    let key: AlbumKey
    let tracks: [Track]

    var id: AlbumKey { key }
    var artworkFileName: String? { tracks.first { $0.artworkFileName != nil }?.artworkFileName }
    var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }
}

struct ArtistSummary: Identifiable {
    let name: String
    let tracks: [Track]
    let albums: [AlbumSummary]

    var id: String { ArtistSummary.key(for: name) }
    var artworkFileName: String? { tracks.first { $0.artworkFileName != nil }?.artworkFileName }

    static func key(for name: String) -> String { name.lowercased().trimmingCharacters(in: .whitespaces) }
}

/// Альбомы и артисты, вычисленные из списка треков (отдельных сущностей в SwiftData нет).
enum LibraryIndex {
    static func albums(from tracks: [Track]) -> [AlbumSummary] {
        var groups: [AlbumKey: [Track]] = [:]
        var order: [AlbumKey] = []
        for track in tracks {
            guard let key = track.albumKey else { continue }
            let normalized = AlbumKey(title: key.title.lowercased(), artist: key.artist.lowercased())
            if groups[normalized] == nil { order.append(normalized) }
            groups[normalized, default: []].append(track)
        }
        return order.compactMap { normalized in
            guard let group = groups[normalized], let first = group.first, let key = first.albumKey else { return nil }
            return AlbumSummary(key: key, tracks: group.sorted { $0.dateAdded < $1.dateAdded })
        }
        .sorted { $0.key.title.localizedStandardCompare($1.key.title) == .orderedAscending }
    }

    static func artists(from tracks: [Track]) -> [ArtistSummary] {
        var groups: [String: [Track]] = [:]
        for track in tracks where track.hasKnownArtist {
            groups[ArtistSummary.key(for: track.primaryArtist), default: []].append(track)
        }
        return groups.values.compactMap { group in
            guard let name = group.first?.primaryArtist else { return nil }
            return ArtistSummary(name: name, tracks: group.sorted { $0.dateAdded > $1.dateAdded }, albums: albums(from: group))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func artist(named name: String, in tracks: [Track]) -> ArtistSummary? {
        let key = ArtistSummary.key(for: name)
        let group = tracks.filter { ArtistSummary.key(for: $0.primaryArtist) == key }
        guard !group.isEmpty else { return nil }
        return ArtistSummary(name: group[0].primaryArtist, tracks: group.sorted { $0.dateAdded > $1.dateAdded }, albums: albums(from: group))
    }

    static func album(_ key: AlbumKey, in tracks: [Track]) -> AlbumSummary? {
        let title = key.title.lowercased(), artist = key.artist.lowercased()
        let group = tracks.filter { $0.albumKey.map { $0.title.lowercased() == title && $0.artist.lowercased() == artist } ?? false }
        guard !group.isEmpty else { return nil }
        return AlbumSummary(key: key, tracks: group.sorted { $0.dateAdded < $1.dateAdded })
    }
}
