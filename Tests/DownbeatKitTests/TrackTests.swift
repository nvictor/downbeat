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
