import Testing
@testable import DownbeatKit

private func track(_ number: Int, _ name: String) -> TrackSummary {
    TrackSummary(number: number, name: name, selected: false, muted: false, soloed: false, recordEnabled: false)
}

private let tracks = [track(1, "Drums"), track(2, "Bass"), track(3, "Bass"), track(4, "2")]

@Test func matchesATrackByNameBeforeNumber() throws {
    #expect(try LogicApp.match("Drums", in: tracks).number == 1)
    #expect(try LogicApp.match("3", in: tracks).name == "Bass")
    #expect(try LogicApp.match("2", in: tracks).number == 4)
}

@Test(arguments: ["Bass", "9", "drums"])
func refusesUnclearTrackReferences(reference: String) {
    #expect(throws: DownbeatError.self) { try LogicApp.match(reference, in: tracks) }
}

@Test(arguments: ["", "   ", "a\nb"])
func refusesBadTrackNames(name: String) {
    #expect(throws: DownbeatError.self) { try LogicApp.checkTrackName(name) }
}

@Test func readsNamesThatContainQuotes() {
    #expect(LogicApp.trackParts("Track 2 “Bass “Low””").name == "Bass “Low”")
}

@Test func ignoresTheStateAfterARegionName() {
    #expect(LogicApp.regionName("Verse, muted") == "Verse")
    #expect(LogicApp.regionName("Verse, take 2") == "Verse, take 2")
}

@Test(arguments: ["Track 2 “Bass”, mute", "Track 2 “Bass”, solo", "Track 2 “Bass”, mute, solo"])
func ignoresTheStateAfterATrackName(description: String) {
    let parts = LogicApp.trackParts(description)
    #expect(parts.number == 2)
    #expect(parts.name == "Bass")
}

@Test(arguments: [("+0.0 dB", 0.0), ("-6.2 dB", -6.2), ("+6.0 dB", 6.0), ("-∞ dB", -Double.infinity)])
func readsFaderLevels(text: String, level: Double) {
    #expect(LogicApp.decibels(text) == level)
}

@Test func readsMarkerPositions() throws {
    let start = try #require(LogicApp.markerPosition("13 1 1 1 "))
    #expect(start == (13, true))
    #expect(try #require(LogicApp.markerPosition("5 2 1 1 ")) == (5, false))
    #expect(LogicApp.markerPosition("∞") == nil)
}

@Test func matchesPluginsByNameOrNumber() throws {
    let plugins = [
        Plugin(number: 1, name: "Compressor", bypassed: false),
        Plugin(number: 2, name: "Channel EQ", bypassed: false),
        Plugin(number: 3, name: "Compressor", bypassed: true),
    ]
    #expect(try LogicApp.match("channel eq", in: plugins).number == 2)
    #expect(try LogicApp.match("3", in: plugins).number == 3)
    #expect(throws: DownbeatError.self) { try LogicApp.match("Compressor", in: plugins) }
    #expect(throws: DownbeatError.self) { try LogicApp.match("Reverb", in: plugins) }
}

@Test func readsPositionsInsideBars() throws {
    let end = "Region starts at 5 bars  and ends at 6 bars 2 beats 4 divisions , Audio region."
    #expect(LogicApp.position(help: end)
        == Position(startBar: 5, endBar: 7, startsOnBarLine: true, endsOnBarLine: false))
    let onLines = "Region starts at 1 bar  and ends at 3 bars , MIDI region."
    #expect(LogicApp.position(help: onLines)?.onBarLines == true)
    let start = "Region starts at 2 bars 3 beats  and ends at 4 bars , Audio region."
    #expect(LogicApp.position(help: start)
        == Position(startBar: 2, endBar: 4, startsOnBarLine: false, endsOnBarLine: true))
    let short = "Region starts at 2 bars  and ends at 2 bars 3 beats , Audio region."
    #expect(LogicApp.position(help: short)?.endBar == 3)
}

@Test(arguments: [(5.0, 120.0, "4/4", 3), (2.0, 120.0, "4/4", 1), (3.0, 60.0, "6/8", 1), (3.1, 60.0, "6/8", 2)])
func countsTheBarsOfAnAudioFile(seconds: Double, tempo: Double, signature: String, bars: Int) {
    #expect(LogicApp.bars(covering: seconds, tempo: tempo, signature: signature) == bars)
}
