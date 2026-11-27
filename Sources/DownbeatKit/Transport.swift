import ApplicationServices

extension LogicApp {
    public func play() throws {
        guard try !status().playing else { return }
        try press("playButton")
        try wait("playback to start") { try status().playing ? true : nil }
    }

    /// Stops playback or recording. When stopped, the button would move the playhead, so nothing happens.
    public func stop() throws {
        let before = try status()
        guard before.playing || before.recording else { return }
        try press("stopButton")
        try wait("the transport to stop") {
            let now = try status()
            return !now.playing && !now.recording ? true : nil
        }
    }

    /// Starts recording on the armed or selected track.
    public func record() throws {
        guard dialogs.isEmpty else { throw DownbeatError("A dialog is open in Logic Pro. Close it first.") }
        guard try !status().recording else { return }
        try press("recordButton")
        try wait("recording to start") { try status().recording ? true : nil }
    }

    func press(_ button: String) throws {
        try control { $0.identifier == "controlBar/\(button)" }.perform(kAXPressAction)
    }
}
