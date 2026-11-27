# How downbeat works, and its limits

downbeat drives Logic Pro through accessibility, keystrokes, mouse clicks, AppleScript and MIDI files.

Tested on Logic Pro 13.0, macOS 27.2.1, Swift 6.4.2, English UI.

## Editing a region

A region is exported, edited as a MIDI file, and put back on the same track and bars.
`downbeat region import` does this:

1. Read the selected region's track, start bar and end bar.
2. Add text events on the first and last tick of the file, to fix the region length, and move everything to start at tick 0.
3. Move the playhead to the start bar, by way of the project start.
4. `File > Import > MIDI File…`, decline the tempo if asked.
5. Click the extra track's header, `Edit > Cut` the imported region.
6. Click the original track's header, select the original region, `Edit > Delete`.
7. Click the original track's header, `Edit > Paste` at the start bar.
8. Click the extra track's header, `Track > Delete Track`.

The header clicks focus the Tracks area, because `Cut`, `Delete` and `Paste` act on the focused pane. Tested with `note transpose` while the Piano Roll had focus.

If a step fails, the finished steps are undone. Tested with failures injected after Cut and after Paste.

Regions with Loop, Mute or playback settings are refused, read from the Region inspector.

## Starting a project

`downbeat project new`:

1. Refuses if an open project has unsaved changes.
2. Copies the template, without its autosave, backup and undo data.
3. Opens the copy, starting Logic Pro if needed.
4. Sets meter, key and tempo at bar 1.
5. Saves, then checks the stored settings.

Logic Pro keeps the window layout in the project, so close extra windows before saving a template.

## Tracks

- Created with the `Track` menu. Logic Pro adds the track after the selected one.
- Renaming double-clicks the name and writes into the editor. Nothing is typed, because keys outside an edit field act as Logic Pro key commands.
- Off-screen tracks are scrolled into view before a rename.

## Transport, mute and delete

- `play`, `stop` and `record` press the control bar buttons. `stop` does nothing when already stopped, because the button would move the playhead.
- Mute and Solo are clicked. Accessibility presses change nothing.
- A solo hides mute states: `track list` does not report them, and `track mute` is refused.
- `region delete` clicks the track header, selects the region, then uses `Edit > Delete`. The region must start and end on a bar line.
- `midi import` keeps the project tempo and prints the tracks it added.
- Tested live: all of the above. `record` was tested without MIDI input, so no recorded region was checked.

## Note JSON

```json
{"notes": [{"pitch": 60, "beat": 0, "duration": 1, "velocity": 100, "releaseVelocity": 64}]}
```

- `pitch`: 0 to 127. `beat` and `duration`: quarter notes, `beat` from the region start.
- `velocity` and `releaseVelocity` are optional.
- No channel: imported notes use the region's channel.
- `note import` replaces every note and keeps the other events.
- Refused: notes outside the region, and overlapping notes of the same pitch.

## Creating a region

`downbeat region create` imports a MIDI file holding only a name and two text events, cuts the region, pastes it on the target track and deletes the extra track.

- Length comes from the meter at the start bar. A meter change inside the region is caught by the final bar check, which undoes the steps.
- Tested in 4/4 and 6/8, on software instrument and external MIDI tracks.
- Audio tracks are refused: Logic would accept the region and play nothing.
- Refused when a region already covers any of the bars, or a region on the track is off the bar lines.
- The Region inspector shows no color until the region has notes.

## Renaming a region

`downbeat region rename` double-clicks the name in the Region inspector, writes into the editor and presses Return. The new name survives later edits.

## Moving and duplicating a region

`downbeat region duplicate` uses `Edit > Copy` and `Edit > Paste` on the same track. `downbeat region move` uses `Cut` instead of `Copy`. Both replace Logic's clipboard.

- Refused when another region already covers any of the target bars. A move may overlap its own old bars.
- Tested: single and multi-channel regions, an empty region, a muted track, a target before the source.
- Not tested: looped regions and region settings. The free space check ignores loops.
- A copy keeps the name, so pick one of them with `--bar` afterwards.
- Move tested: forward, backward and onto its own old bars.

## Volume and pan

`downbeat mixer volume` steps the fader in the track header until its level is closest to the one asked, then prints the level reached.

- The track does not need to be selected or on screen.
- Tested from -∞ to +6 dB. Every level tried was reached exactly.
- Needs the volume slider shown in the track header.
- External MIDI tracks are refused: their volume is not in dB.

`downbeat mixer pan` steps the pan knob of the track header, from -64 to 63. Tested at both ends, the middle and between, on audio, software instrument and external MIDI tracks.

Neither command is tested with automation.

## Markers

`downbeat marker create` reads the Marker List, moves the playhead, uses `Navigate > Create Marker` and `Rename Marker`, then reads the list again.

- Refused when a marker already sits in the bar, and for names with `#`, which Logic replaces with the marker number.
- The Marker List is closed afterwards, even if it was open: with focus, it disables the marker commands.
- If naming fails, the unnamed marker stays. Remove it with Undo.
- Tested with the list empty, open and longer than the window.

## MIDI ports

`downbeat midi ports` lists the CoreMIDI sources and destinations of the Mac. It does not use Logic Pro or need permissions. Tested with the two Logic Pro virtual ports only: no hardware, and no offline device.

## Plugins

`downbeat plugin list` selects the track, reads the channel strip in the inspector, then restores the selection. `downbeat plugin bypass` presses the bypass checkbox of a slot.

- The list follows the signal: the instrument first, then the effects. Accessibility lists them the other way round.
- Pick a plugin by name or number. Use the number when two share a name.
- Tested on software instrument tracks. The result was checked in the Mixer.
- `plugin add` picks the name from Logic's plugin menu, categories and Audio Units included, then closes the window Logic opens. A new effect goes last.
- `--format` picks a menu format such as `Stereo` or `Dual Mono`. Default: the first one.
- `plugin remove` picks `No Plug-in` in the slot's menu. The settings are lost. Undo was not tested.
- Add and remove tested on software instrument and audio tracks. Removing an instrument works too. External MIDI tracks are refused.
- Seen once: the instrument slot was named `input` and its checkbox kept a stale state, while the Mixer was right. It went back to normal after effects were removed. downbeat reports the bypass as unknown and refuses to change it.
- Not tested: MIDI effects, aux and output channels, third-party plugins.

## Audio files

`downbeat audio import` selects an audio track, moves the playhead and uses `File > Import > Audio File…`.

- Refused on other track types, and when a region already touches the bars the file would cover. Those bars are estimated from the tempo and meter at the start bar.

`downbeat audio export` uses `File > Export > 1 Track as Audio File…` into an empty folder, then moves the file to the output.

- Sets the file type to WAVE. Bit depth, range, normalize, effects bypass and volume/pan automation stay as Logic Pro last used them.
- The file starts at the project start, so positions line up. Seen with `Trim Silence at File End`.
- A muted track still exports its audio.
- Tested with a mono tone on an audio track, and a software instrument track. Other file formats and sample rates were not tested.

## What survives a region edit

Test region: one software instrument track, bars 3 to 5, 3 notes, 75 CC events, 215 pitch bend events.

| Item | Result |
| --- | --- |
| Track | Preserved. |
| Start and end bar | Preserved. |
| Notes: pitch, timing, velocity, release velocity | Preserved. |
| Timing inside a bar (beat 2 plus 7 ticks) | Preserved. Tested with import and export. |
| CC | Preserved (75 of 75). The test values had no gaps to interpolate. |
| Pitch bend | Preserved over 3 passes with the fix below. One duplicate event was dropped (215 to 214). |
| Region name | Preserved in the test, where it matched the file's track name. |
| Tempo in the file | AudioToolbox rounds it by 1 microsecond per quarter. The import does not change the project tempo. |
| Text event added for length | Stays in the region. |
| Transpose, velocity offset, quantize (region settings) | **Baked into the export.** The notes carry the result. The new region has no settings. |
| Loop | The export contains every repeat (64 tracks in the test). Refused. |
| Custom color | Lost: the new region takes the default. Detected after the replace, which is then undone. |
| Automation, other region settings | Not tested. The region is new, so expect loss. |
| SysEx, markers | Not tested. |
| Regions that start or end inside a bar | Refused. |
| Deleting the first, the last or every note | Region bounds preserved. A custom color is not detected when every note goes. |
| Several MIDI channels in one region | Can be read. Replacing is refused: Logic gives the imported region another color. |
| Region on a muted track, or silenced by a solo | Cannot be exported. Refused. |
| 3/4 | Preserved. |
| 6/8 | Preserved since the file starts at tick 0. |
| Several regions on a track | The other region is untouched (identical export). |

## Pitch bend growth (fixed)

Without a fix the count grew on each pass: 215, 428, 854.

- Logic Pro adds points between close pitch bend events.
  - 60 ticks apart or less: filled in. 240 ticks apart: left alone. Between them: not tested.
  - Ramps are filled on a 1/256 note grid (7.5 ticks at 480). Closer events get a midpoint.
  - Not checked whether it happens on import or on export.
- Fix: `downbeat region export` removes pitch bend events that lie on a ramp denser than 1/256 note (`MIDIFile.thinPitchBend`).
- Side effects
  - Real recorded data that dense, on a straight line, is thinned too.
  - Events 8 to 60 ticks apart are filled to the 1/256 grid by the first pass.
  - Logic Pro still holds a filled ramp, so a manual export from Logic shows the extra events.
- CC events 8 ticks apart were not filled. Wider CC gaps came through unchanged in one test (960 ticks).

## What Logic Pro does

- AppleScript has no tracks, regions or notes. Standard suite only.
- Accessibility exposes tracks, regions (start and end bar in the help text) and Piano Roll notes.
- Export writes a format 0 file with absolute project positions. End of track is the region end.
- Import creates a new track and places the region at the playhead bar.
- Import ignores the end-of-track marker. The last event sets the length.
- Outside 4/4, import reads a file that starts later than tick 0 as offset inside a bar, which lengthens the region. Seen in 6/8.
- A file without a track name gives a region named after the added text event (`.`).
- `Undo` restored the original exactly (identical export).

## Automation notes

| Problem | Solution |
| --- | --- |
| An opened menu stays up behind a file panel and swallows Return and typing. | Press the menu item without opening the menu. |
| `CGEvent` `Cmd+Shift+G` had no effect, with the menu open. | System Events keys, guarded by a front-app check. `CGEvent` was not retested after the menu fix. |
| Accessibility selection of a track header reports success and changes nothing. | Mouse click, after checking what is under the point. |
| Playhead sliders move one step per write. | Write until the value matches. |
| Menu items stay disabled until their menu has opened. | Open and close the menu when an item looks disabled. |
| Selecting an already selected region deselects it. Selecting another one adds to the selection. | Clear the others, then select only if needed. |
| Floating editors report the dialog subrole. | Detect blocking dialogs by modality. |
| Logic Pro rebuilds the control bar after a change, so a pop-up menu may not open. | Fetch the button again and retry. |
| The `Save` menu item is ignored after a pop-up menu was used. | Press `Cmd+S`. |
| Some changes are recorded after they show, so a saved project turns modified again. | Save until it stays saved. |
| The first click after coming to the front may only raise the window. | Wait before clicking. |
| The track list has page actions that fail. | Scroll with the mouse wheel and wait for it to stop. |
| Playback leaves divisions and ticks that cannot be written, so a paste lands off the bar line. | Press the stop button (go to beginning) before moving the playhead. |
| Exporting a region with several channels asks whether to convert them. | Answer `Don't Convert`. |
| A region without channel events, or with several channels, reports its color as `not set`. | Skip the color check when there was no color to keep. |
| Track and region descriptions gain `, mute`, `, solo` or `, muted`. | Ignore the suffix when reading names. |

## AudioToolbox

- Loading and saving turns format 0 into format 1 (separate tempo track).
- Channel events are kept, including pitch bend, pressure, program change and release velocity.
- Saving an exported file drops nothing, apart from the thinning above.

## Open issues

- A custom color is compared by the name the inspector reports, so a change of shade alone may go unnoticed.
- A first event placed before its bar line has not been tested.
