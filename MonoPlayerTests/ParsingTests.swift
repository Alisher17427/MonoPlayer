import Foundation
import SwiftData
import Testing
@testable import MonoPlayer

struct FilenameSanitizerTests {
    @Test func stripsJunkAndSplitsArtist() {
        let result = FilenameSanitizer.parse("01_Artist_-_Song_(Official_Video)_320kbps.mp3")
        #expect(result == .init(artist: "Artist", title: "Song"))
    }

    @Test func normalizesDashes() {
        let result = FilenameSanitizer.parse("Daft Punk – Get Lucky [Lyrics].flac")
        #expect(result == .init(artist: "Daft Punk", title: "Get Lucky"))
    }

    @Test func keepsNumbersThatArePartOfTheName() {
        let result = FilenameSanitizer.parse("50 Cent - In Da Club.mp3")
        #expect(result == .init(artist: "50 Cent", title: "In Da Club"))
    }

    @Test func keepsHyphenatedNames() {
        let result = FilenameSanitizer.parse("Jay-Z - Empire State of Mind (prod. by Al Shux).m4a")
        #expect(result == .init(artist: "Jay-Z", title: "Empire State of Mind"))
    }

    @Test func titleOnly() {
        let result = FilenameSanitizer.parse("some song.wav")
        #expect(result == .init(artist: nil, title: "some song"))
    }
}

struct LRCParserTests {
    @Test func parsesTimestampsAndSkipsMetadata() {
        let raw = """
        [ar:Artist]
        [00:01.50]Hello
        [00:03.00][00:10.00]Chorus
        [00:05.25]
        """
        let lines = LRCParser.parse(raw)
        #expect(lines.map(\.time) == [1.5, 3.0, 5.25, 10.0])
        #expect(lines.map(\.text) == ["Hello", "Chorus", "", "Chorus"])
    }

    @Test func emptyInput() {
        #expect(LRCParser.parse(nil).isEmpty)
        #expect(LRCParser.parse("").isEmpty)
    }
}

struct ITunesMatchTests {
    @Test func matchesIgnoringCaseAndPunctuation() {
        let hit = ITunesTrack(trackName: "Get Lucky (feat. Pharrell Williams)", artistName: "Daft Punk",
                              collectionName: "Random Access Memories", artworkUrl100: nil)
        #expect(ITunesSearchService.bestMatch(in: [hit], artist: "daft punk", title: "Get Lucky") != nil)
        #expect(ITunesSearchService.bestMatch(in: [hit], artist: "Other Artist", title: "Get Lucky") == nil)
    }

    @Test func upgradesArtworkResolution() {
        let hit = ITunesTrack(trackName: nil, artistName: nil, collectionName: nil,
                              artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/x/100x100bb.jpg")
        #expect(hit.hdArtworkURL?.absoluteString.hasSuffix("1000x1000bb.jpg") == true)
    }
}

struct SearchQueryTests {
    @Test func titleVariantsStripDecorations() {
        #expect(SearchQuery.titleVariants("Song (feat. X) [Remastered 2011]") == ["Song (feat. X) [Remastered 2011]", "Song (feat. X)", "Song"])
        #expect(SearchQuery.titleVariants("Song - Remastered 2011") == ["Song - Remastered 2011", "Song"])
        #expect(SearchQuery.titleVariants("Hello") == ["Hello"])
    }

    @Test func primaryArtistDropsFeaturing() {
        #expect(SearchQuery.primaryArtist("Artist feat. Other") == "Artist")
        #expect(SearchQuery.primaryArtist("Artist (feat. Other)") == "Artist")
        #expect(SearchQuery.primaryArtist("Daft Punk ft. Pharrell") == "Daft Punk")
        #expect(SearchQuery.primaryArtist("Simon & Garfunkel") == "Simon & Garfunkel")
        #expect(SearchQuery.primaryArtist("Featherweight") == "Featherweight")
    }

    @Test func matchesIgnoringEditions() {
        #expect(SearchQuery.matches(title: "Get Lucky (feat. Pharrell Williams) - Radio Edit", artist: "Daft Punk",
                                    wantedTitle: "Get Lucky", wantedArtist: "Daft Punk feat. Pharrell"))
        #expect(!SearchQuery.matches(title: "Get Lucky", artist: "Someone Else", wantedTitle: "Get Lucky", wantedArtist: "Daft Punk"))
    }
}

struct LyricsSelectionTests {
    private func candidate(_ duration: TimeInterval, synced: Bool) -> LyricsCandidate {
        LyricsCandidate(source: "LRCLIB", trackName: "Song", artistName: "Artist", albumName: nil, duration: duration,
                        plainLyrics: "text", syncedLyrics: synced ? "[00:01.00]text" : nil)
    }

    @Test func prefersSyncedWithMatchingDuration() {
        let live = candidate(250, synced: true), studio = candidate(201, synced: true), plain = candidate(200, synced: false)
        let best = LyricsService.pickBest([live, plain, studio], duration: 200, wantedTitle: "Song", wantedArtist: "Artist")
        #expect(best?.id == studio.id)
    }

    @Test func rejectsSyncedOfDifferentVersion() {
        let live = candidate(250, synced: true), plain = candidate(200, synced: false)
        let best = LyricsService.pickBest([live, plain], duration: 200, wantedTitle: "Song", wantedArtist: "Artist")
        #expect(best?.id == plain.id)
    }

    @Test func parsesOffsetAndWordTimestamps() {
        let lines = LRCParser.parse("[offset:+500]\n[00:02.00]<00:02.00>Hello <00:02.50>world")
        #expect(lines.count == 1)
        #expect(lines.first?.text == "Hello world")
        #expect(lines.first?.time == 1.5)
    }
}

struct ArtistSplitTests {
    @Test func splitsCollaborations() {
        #expect(SearchQuery.splitArtists("rocket, lildrughill", splitAmpersand: true) == ["rocket", "lildrughill"])
        #expect(SearchQuery.splitArtists("Daft Punk feat. Pharrell Williams", splitAmpersand: true) == ["Daft Punk", "Pharrell Williams"])
        #expect(SearchQuery.splitArtists("A (feat. B & C)", splitAmpersand: true) == ["A", "B", "C"])
        #expect(SearchQuery.splitArtists("Macan x Jakone", splitAmpersand: true) == ["Macan", "Jakone"])
        #expect(SearchQuery.splitArtists("Rocket ft. Lildrughill, Thomas Mraz", splitAmpersand: true) == ["Rocket", "Lildrughill", "Thomas Mraz"])
    }

    @Test func keepsSingleNames() {
        #expect(SearchQuery.splitArtists("XXXTENTACION", splitAmpersand: true) == ["XXXTENTACION"])
        #expect(SearchQuery.splitArtists("Lil Nas X", splitAmpersand: true) == ["Lil Nas X"])
        #expect(SearchQuery.splitArtists("Simon & Garfunkel", splitAmpersand: false) == ["Simon & Garfunkel"])
    }
}

@MainActor
struct LibraryIndexTests {
    private func makeTracks(_ specs: [(title: String, artist: String, album: String)]) throws -> (ModelContainer, [Track]) {
        let container = try ModelContainer(for: Track.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let tracks = specs.map { spec -> Track in
            let track = Track(title: spec.title, artist: spec.artist, audioFileName: "\(spec.title).mp3")
            track.album = spec.album
            container.mainContext.insert(track)
            return track
        }
        return (container, tracks)
    }

    @Test func collaborationStaysInAlbum() throws {
        let (container, tracks) = try makeTracks([
            ("Intro", "rocket", "Album X"),
            ("Duet", "rocket, lildrughill", "Album X"),
            ("Hit", "Other", "Greatest Hits"),
            ("Hit 2", "Someone", "Greatest Hits"),
        ])
        _ = container
        let albums = LibraryIndex.albums(from: tracks)
        #expect(albums.count == 3)
        let albumX = albums.first { $0.key.title == "Album X" }
        #expect(albumX?.tracks.count == 2)
        #expect(albumX?.key.artist == "rocket")
    }

    @Test func everyArtistGetsAPage() throws {
        let (container, tracks) = try makeTracks([
            ("Intro", "rocket", "Album X"),
            ("Duet", "rocket, lildrughill", "Album X"),
        ])
        _ = container
        let second = LibraryIndex.artist(named: "lildrughill", in: tracks)
        #expect(second?.tracks.map(\.title) == ["Duet"])
        #expect(second?.albums.isEmpty == true)
        #expect(second?.appearsOn.first?.key.title == "Album X")
        #expect(LibraryIndex.artist(named: "rocket", in: tracks)?.albums.count == 1)
        #expect(LibraryIndex.artists(from: tracks).map(\.name).sorted() == ["lildrughill", "rocket"])
    }
}

struct VideoArtistMatchTests {
    private func item(_ wrapper: String, _ artistId: Int, _ name: String, title: String? = nil, kind: String? = nil, trackId: Int? = nil) -> VideoService.Item {
        .init(wrapperType: wrapper, kind: kind, artistId: artistId, trackId: trackId, trackName: title,
              artistName: name, artworkUrl100: nil, releaseDate: nil, trackViewUrl: nil)
    }

    @Test func picksNamesakeWhoseSongsAreInLibrary() {
        let candidates = [item("artist", 1, "FACE"), item("artist", 2, "FACE")]
        let songs = [item("track", 1, "FACE", title: "Cypress"), item("track", 2, "FACE", title: "Бургер"),
                     item("track", 2, "FACE", title: "Я роняю запад")]
        let id = VideoService.bestArtistID(candidates: candidates, songs: songs, knownTitles: ["Я РОНЯЮ ЗАПАД (prod. by X)"])
        #expect(id == 2)
    }

    @Test func fallsBackToCatalogOrder() {
        let candidates = [item("artist", 1, "FACE"), item("artist", 2, "FACE")]
        #expect(VideoService.bestArtistID(candidates: candidates, songs: [], knownTitles: ["Unknown"]) == 1)
    }

    @Test func keepsOnlyMusicVideosWithoutDuplicates() {
        let items = [item("artist", 1, "FACE"),
                     item("track", 1, "FACE", title: "Плачу", kind: "music-video", trackId: 10),
                     item("track", 1, "FACE", title: "Плачу [Live]", kind: "music-video", trackId: 11),
                     item("track", 1, "FACE", title: "Бургер", kind: "song", trackId: 12)]
        #expect(VideoService.musicVideos(from: items).map(\.id) == [10])
    }
}
