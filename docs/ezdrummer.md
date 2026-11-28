# EZdrummer

## Hand off MIDI

1. Build into one folder.

```bash
downbeat midi build examples/artemis.json --output ~/Desktop/artemis-midi --per part
```

2. Move the folder to the Mac that runs EZdrummer, if needed.
3. Drag the clips onto Song Tracks.
4. Set the tempo, then save the project.
5. Check what was saved.

```bash
downbeat ezdrummer inspect ~/Music/"EZdrummer 3"/artemis.ezd3p --notes
```

6. After reopening the saved project, delete the folder. `downbeat-manifest.json` lists what the build created.

## Read a saved project

`downbeat ezdrummer inspect <project.ezd3p> [--notes] [--json]` reads the file only.

- Reports the library, mixer and kit preset names, mixer channels, Song Tracks (name, tempo, meter) and clips (name, bar, length, note count).
- Mixer volume and pan are the raw numbers of the file, not decibels.
- `--notes` lists hits bar by bar, to compare with `midi inspect`.
- The format is undocumented. Read from projects of version 3.1.2. Other versions get a warning.
- Tested on one real project, which stayed byte for byte the same.

## Controls

Checked on November 27, 2026, with EZdrummer 3.1.2. No UI automation was written.

| Task | Result |
| --- | --- |
| Read library, preset and mixer | Works, from the saved file. |
| Read Song Track names and clip labels | Works, from the saved file. |
| AppleScript | None. `sdef` finds no dictionary. |
| URL scheme | None in `Info.plist`. |
| Import into a named Song Track | Not checked. |
| Set a clip label | Not checked. |
| Save a dated project | Not checked. |
| Accessibility controls | Not checked. The terminal has no Accessibility access for System Events. |

Not tested:

- Whether EZdrummer keeps silent bars at the start or end of a dragged clip.
- Whether it takes the clip label from the file name.
