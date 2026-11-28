import Testing
@testable import EZdrummerKit

// A trimmed project. 6562960 is a kick (36) at velocity 100: velocity, pitch and status bytes.
private let project = """
    PlugVersion 3.1.2
    SAMPLER {
    HQ {
    soundlib "EZX2_70s"
    }
    mixer {
    buss 0 {
    pan 0.5
    volume 0.645655
    solo 0
    mute 1
    username "Kick"
    send 9 {
    volume 0.1
    }
    }
    }
    }
    SongTrack 0 {
    Tempo 69 0 0
    TimeSig 4 4 0
    TrackName "chorus"
    MidiLoop 0 {
    Name "Untitled"
    StartTime 0
    EndTime 4
    Offset 4
    MidiEvents { 
    EndTime 8
    Events 6562960 0 0.125 6562960 3.5 3.625 6562960 4 4.125
    Tempo 120 0 0
    }
    SongPart 4 8 8 "13 grv d" 176 181 203 "abc"
    FileName "/tmp/My Chorus.mid"
    }
    }
    editorVars {
    DrumsMixerPresetName "Mark Arnold Basic"
    ChosenKitPresetName ""
    PresetAltered 1
    }
    """

@Test func readsALoopedClip() throws {
    let report = try ProjectReport(text: project, notes: true)
    #expect(report.library == "EZX2_70s")
    #expect(report.mixerPreset == "Mark Arnold Basic")
    #expect(report.kitPreset == nil)
    #expect(report.mixer.map(\.name) == ["Kick"])
    #expect(report.mixer[0].mute == true)
    #expect(report.mixer[0].volume == 0.645655)
    let track = report.songTracks[0]
    #expect(track.name == "chorus")
    #expect(track.tempo == 69)
    let clip = track.clips[0]
    #expect(clip.name == "13 grv d")
    #expect(clip.startBar == 2)
    #expect(clip.bars == 1)
    #expect(clip.sourceFile == "/tmp/My Chorus.mid")
    // Only the source notes inside the loop, moved by the offset.
    #expect(clip.noteCount == 2)
    #expect(clip.barList?[0].notes.map(\.position) == [1, 4.5])
    #expect(clip.barList?[0].notes.map(\.articulation) == ["kick", "kick"])
    #expect(report.warnings.isEmpty)
}

@Test(arguments: ["SAMPLER {", "}", "PlugVersion 3.1.2", "SAMPLER {\n}\nSongTrack 0 {\nMidiLoop 0 {\nMidiEvents {\nEvents 1 2\n}\n}\n}"])
func refusesWhatItCannotRead(text: String) {
    #expect(throws: ProjectError.self) { try ProjectReport(text: text) }
}
