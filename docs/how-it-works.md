# How downbeat works, and its limits

downbeat drives Logic Pro through accessibility, keystrokes, mouse clicks, AppleScript and MIDI files.

Tested on Logic Pro 13.0, macOS 27.2.1, Swift 6.4.2, English UI.

## Editing a region

A region is exported, edited as a MIDI file, and put back on the same track and bars.
`downbeat region import` does this:

1. Read the selected region's track, start bar and end bar.
2. Add a text event on the last tick of the file, to fix the region length.
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
| Several MIDI channels in one region | Can be read. Replacing is refused: Logic gives the imported region another color. |
| Region on a muted track, or silenced by a solo | Cannot be exported. Refused. |
| 3/4 | Preserved. Other meters not tested. |
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
| Track and region descriptions gain `, mute`, `, solo` or `, muted`. | Ignore the suffix when reading names. |

## AudioToolbox

- Loading and saving turns format 0 into format 1 (separate tempo track).
- Channel events are kept, including pitch bend, pressure, program change and release velocity.
- Saving an exported file drops nothing, apart from the thinning above.

## Open issues

- A custom color is compared by the name the inspector reports, so a change of shade alone may go unnoticed.
- A first event placed before its bar line has not been tested.
