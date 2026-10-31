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
