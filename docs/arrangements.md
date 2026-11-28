# Arrangements

Write a song as drum voices in GUS and a form in PAL, then build MIDI clips. No app is needed.

```bash
downbeat midi build examples/artemis.json --output /tmp/artemis --per part
```

```bash
downbeat midi inspect "/tmp/artemis/chorus/08 fill a.mid" --arrangement examples/artemis.json
```

## File

```json
{
  "version": 1,
  "title": "artemis",
  "pal": "69 bpm · A8 B16 C16 D8",
  "drumMap": "ezdrummer",
  "sections": [
    { "id": "A", "name": "intro", "parts": [
      { "bar": 1, "bars": 2, "name": "grv a",
        "voices": [
          { "articulation": "kick", "velocity": 115,
            "gus": ["P4 A↓ O(2,4) S(3)<", "P4 A↓ O(2,3,4) U(2)"] },
          { "articulation": "snare-center", "velocity": 122, "accent": true, "gus": "P4 A↔ O(1,2,4)",
            "flam": { "offset": 0.0625, "velocity": 44, "duration": 0.025 } }
        ],
        "notes": [ { "articulation": "crash-1", "beat": 0, "duration": 1, "velocity": 110 } ] },
      { "bar": 3, "bars": 2, "name": "grv a", "use": "01 grv a" }
    ] }
  ]
}
```

A real file needs one section for each PAL letter. See [artemis.json](../examples/artemis.json).

| Key | Meaning |
| --- | --- |
| `pal` | Tempo, meter, section order and section lengths. Sections match by `id`. |
| `tempo`, `meter` | Used without `pal`, or where `pal` leaves them out. `meter` is 4/4 by default. |
| `channel` | MIDI channel, 1 by default. |
| `drumMap` | `ezdrummer`, a `.json` file next to the arrangement, or an object. |
| `sections` | `name`, `parts`, and optional `id`, `bars`, `tempo`, `meter`. One meter per section. |
| `humanize` | Rules written by `midi humanize`. |

### Parts

- `bar` is the first bar in the section, from 1. `bars` is the length.
- The clip name is the bar and the name: `08 fill a`.
- Parts do not overlap. Bars without a part are silent.
- `use` plays another part: `"11 grv d"`, or `"intro/08 fill a"` for another section. Edit the source to change every user.
- A part with `use` has no `voices` or `notes`. A source cannot use another part.

### Voices

- `gus`: one line, or one per bar, repeating. Read as in the Atalanta diary: `<` and `>` are the sixteenth before and after the pulse, wrapping around the bar.
- GUS gives positions only. Set `velocity`, `accent`, `flam` and `duration` on the voice.
- `articulation` and `velocity` may be lists. They repeat over the hits of each bar, for example down a tom roll.
- A signature such as `6/8 · P6` must match the section.

### Notes

- `beat` and `duration` are quarter notes. `beat` counts from 0 at the start of the part.
- `articulation` or `pitch`, `beat`, and optional `duration` (0.125), `velocity` (100), `releaseVelocity` (64), `accent`, `flam`.
- A flam is one note with a grace stroke before it. Edits and humanizing keep the two together.

### Drum map

```json
{ "extends": "ezdrummer", "articulations": { "ride-bell": 53 }, "voices": { "ride": ["ride-bow", "ride-bell"] } }
```

The 53 above is an example. Check pitches in your kit.

| `ezdrummer` articulation | Pitch | Checked |
| --- | --- | --- |
| `floor-tom-1-center` | 43 | Named in a saved project |
| `crash-1` | 49 | Named in a saved project |
| `ride-bow` | 51 | Named in a saved project |
| `hi-hat-tight-tip` | 63 | Named in a saved project |
| `kick` | 36 | Inferred |
| `snare-center` | 38 | Inferred |
| `hi-hat-tight-edge` | 62 | Inferred |

- Voices: `snare`, `toms`, `cymbals`, `hi-hat`, `ride`.
- Checked against the EZX 70s library only.

## Build

```bash
downbeat midi build examples/artemis.json --output /tmp/artemis --replace
```

- `--per section` (default) writes `chorus.mid`, with a marker at each part.
- `--per part` writes `chorus/08 fill a.mid`, one file for every part, references included.
- `--section chorus` builds one section. With `--replace`, files of other sections from the last build are removed.
- `downbeat-manifest.json` lists every file with its hash.
- The folder must be new or empty. `--replace` removes only files the manifest lists and you did not change.
- Files are format 0, 960 ticks per quarter note. The same input gives the same bytes.
- The end of track marks the exact length. Text events on the first and last tick keep silent edges in Logic Pro.

## Inspect

```bash
downbeat midi inspect /tmp/artemis/chorus.mid --arrangement examples/artemis.json --json
```

- Prints a list, one entry per file.
- Every bar is listed, empty ones too. `position` counts beats from 1: 3.5 is `3&`.
- `sameAs` names the first earlier bar with the same notes.
- A quieter note of the same pitch up to 1/8 quarter before another is reported as its flam.
- Text output marks a flam with `f` and puts the velocity in brackets.

## Edit

```bash
downbeat midi edit examples/artemis.json examples/artemis-ride.json --dry-run
```

```json
{ "operations": [
  { "op": "replace", "section": "chorus", "articulations": ["hi-hat"],
    "with": "ride-bow", "every": 0.5, "velocity": [112, 92] },
  { "op": "remove", "section": "chorus", "bars": "15", "beats": [4, 5], "articulations": ["ride"] },
  { "op": "copy", "section": "chorus", "bars": "9-10", "articulations": ["kick"],
    "to": { "section": "verse", "bar": 9 } }
] }
```

| Key | Meaning |
| --- | --- |
| `section` | Required. |
| `part` | One clip, such as `16 fill b`. |
| `bars` | Section bars: `"8"` or `"9-10"`. |
| `beats` | Positions from, up to: `[4, 5]` is all of beat 4. |
| `articulations` | Articulation or voice names. |
| `with` | `replace`: the new articulation. Without `every`, timing and velocity stay. |
| `every` | `replace`: write one hit every so many quarters, in bars that played the old or new sound. |
| `velocity` | With `every`: a number, or a list that repeats. |
| `to` | `copy`: destination `section` and `bar`. It replaces those articulations there. |
| `shared` | `source` or `detach`. |

- Operations run in order. All must pass, or nothing is written.
- Running a batch again changes nothing.
- Parts that share a source are never split silently. Set `shared`:
  - `source`: every user gets the change.
  - `detach`: changed parts get their own notes.
- A GUS voice that an edit touches is written out as notes. Other voices keep their GUS lines.
- Saving rewrites the file in a standard layout.

## Humanize

```bash
downbeat midi humanize examples/artemis.json --section chorus --seed 7 --timing 0.01 --velocity 6 --dry-run
```

- Stores a rule. `midi build` applies it, so it never adds up.
- The same seed gives the same result. Changing one note does not move the others. Renaming a source part does.
- `--timing` is quarter notes, up to 0.03125. `--velocity` is separate.
- `--drop` leaves out hits by chance. It is 0 unless you set it.
- Accents keep their velocity and are never dropped. Flam strokes move together. Hits stay inside their part. Nothing is added.
- `--part`, `--bars` and `--articulation` narrow a rule. The last matching rule wins.
- `--clear` removes the rules of a section or part.

## Not covered

- Hi-hat pedal and other controller data.
- Reading `.mid` or `.ezd3p` files into an arrangement.
- Meter changes inside a section.
