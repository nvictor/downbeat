# Spike: MIDI round trip

Question: can a region be exported, edited and put back in Logic Pro without losing anything?

## Verdict: go, with limits

Export, edit, import and move back works end to end, on the same track and bars.
Limits: see the untested rows below.

Environment: Logic Pro 13.0, macOS 27.2.1, Swift 6.4.2, English UI.

Test region: one software instrument track, bars 3 to 5, 3 notes, 75 CC events, 215 pitch bend events.

## The sequence (`logic spike replace`)

1. Read the selected region's track, start bar and end bar.
2. Add a text event on the last tick of the file, to fix the region length.
3. Move the playhead to the start bar.
4. `File > Import > MIDI File…`, decline the tempo if asked.
5. `Edit > Cut` the imported region.
6. Select the original region, `Edit > Delete`.
7. Select the original track, `Edit > Paste` at the start bar.
8. Click the extra track's header, `Track > Delete Track`.

## Preserved or lost

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
| Color, loop, region parameters (quantize, transpose), automation | Not tested. The region is new, so expect loss. |
| SysEx, markers | Not tested. |
| Regions that start or end inside a bar | Refused. |
| Meters other than 4/4, several regions on a track | Not tested. |

## Pitch bend growth (fixed)

Without a fix the count grew on each pass: 215, 428, 854.

- Logic Pro adds points between close pitch bend events.
  - 60 ticks apart or less: filled in. 240 ticks apart: left alone. Between them: not tested.
  - Ramps are filled on a 1/256 note grid (7.5 ticks at 480). Closer events get a midpoint.
  - Not checked whether it happens on import or on export.
- Fix: `logic spike export` removes pitch bend events that lie on a ramp denser than 1/256 note (`MIDIFile.thinPitchBend`).
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
- `Undo` restored the original exactly (identical export).

## Automation notes

| Problem | Solution |
| --- | --- |
| An opened menu stays up behind a file panel and swallows Return and typing. | Press the menu item without opening the menu. |
| `CGEvent` `Cmd+Shift+G` had no effect, with the menu open. | System Events keys, guarded by a front-app check. `CGEvent` was not retested after the menu fix. |
| Accessibility selection of a track header reports success and changes nothing. | Mouse click, after checking what is under the point. |
| Playhead sliders move one step per write. | Write until the value matches. |
| Floating editors report the dialog subrole. | Detect blocking dialogs by modality. |

## AudioToolbox

- Loading and saving turns format 0 into format 1 (separate tempo track).
- Channel events are kept, including pitch bend, pressure, program change and release velocity.
- Saving an exported file drops nothing, apart from the thinning above.

## Next

- Test region color, loop and parameters.
- Decide how to restore a failed replace (today: `Undo` by hand).

## Scratch project

`~/Music/Logic/RoundTrip.logicx`:

- One software instrument track.
- One MIDI region starting at bar 3.
- A few notes, some CC and pitch bend.
