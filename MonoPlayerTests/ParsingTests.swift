import Foundation
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
