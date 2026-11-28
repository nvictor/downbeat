# downbeat

A command line tool for drum arrangements and Logic Pro.

| Group | Does | Needs |
| --- | --- | --- |
| `downbeat midi` | Builds, inspects, edits and humanizes drum MIDI. Lists ports. | macOS 15+ |
| `downbeat ezdrummer` | Reads saved EZdrummer 3 projects. | macOS 15+ |
| `downbeat logic` | Starts projects, controls playback, tracks, mixer and plugins, edits notes. | Logic Pro (English), Accessibility and Automation permissions |

## Install

```bash
scripts/install.sh
```

It pulls this repo and a `skills` checkout next to it, builds, and installs to `~/.local/bin`. Run it again to update. To build the source as it is:

```bash
scripts/install.sh --no-pull
```

If `~/.local/bin` is not in your `PATH`, add it, then open a new terminal window:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zprofile
```

## Drum arrangements

Write grooves in [GUS](https://github.com/nvictor/gus) and the form in [PAL](https://github.com/nvictor/pal). See [Arrangements](docs/arrangements.md).

```bash
downbeat midi build examples/artemis.json --output /tmp/artemis --per part
```

```bash
downbeat midi inspect "/tmp/artemis/chorus/08 fill a.mid" --arrangement examples/artemis.json
```

```bash
downbeat midi edit examples/artemis.json examples/artemis-ride.json --dry-run
```

## Logic Pro setup

With Logic Pro open, check the setup:

```bash
downbeat logic check
```

Allow what it lists under System Settings > Privacy & Security, then run it again.

- Accessibility: on macOS 27, the list is named Device Control and Data Access. Turn on the terminal app that runs `downbeat`, then quit and reopen it.
- Automation: allow it when macOS asks.

## Start a project

Once: save an empty project in Logic Pro, then keep it as the template.

```bash
downbeat logic project template ~/Music/Logic/Blank.logicx
```

Show where the current template is kept:

```bash
downbeat logic project template
```

Then:

```bash
downbeat logic project new "Night Drive" --tempo 92 --signature 6/8 --key "A minor"
```

## Tracks

```bash
downbeat logic track list
```

```bash
downbeat logic track create --type instrument --name "Bass" --project "Night Drive"
```

```bash
downbeat logic track rename 1 "Drums" --project "Night Drive"
```

```bash
downbeat logic track mute "Bass" --project "Night Drive"
```

```bash
downbeat logic mixer volume "Bass" --db -6 --project "Night Drive"
```

```bash
downbeat logic mixer pan "Bass" --value -20 --project "Night Drive"
```

```bash
downbeat logic marker create "Chorus" --bar 9 --project "Night Drive"
```

```bash
downbeat logic plugin list "Bass"
```

```bash
downbeat logic plugin add "Bass" "Limiter" --project "Night Drive"
```

```bash
downbeat logic plugin remove "Bass" "Limiter" --project "Night Drive"
```

```bash
downbeat logic plugin bypass "Bass" "Compressor" --project "Night Drive"
```

## Play and save

```bash
downbeat logic play
```

```bash
downbeat logic stop
```

```bash
downbeat logic project save --project "Night Drive"
```

## Write a part

```bash
downbeat logic region create --track "Bass" --bar 1 --bars 4 --name "Verse" --project "Night Drive"
```

```bash
downbeat logic note import notes.json --region "Verse" --project "Night Drive"
```

```bash
downbeat logic region rename "Chorus" --region "Verse" --project "Night Drive"
```

```bash
downbeat logic region duplicate --region "Chorus" --to-bar 9 --project "Night Drive"
```

```bash
downbeat logic region move --region "Chorus" --bar 9 --to-bar 17 --project "Night Drive"
```

## MIDI ports

```bash
downbeat midi ports
```

## Audio files

```bash
downbeat logic audio import take.wav --track "Vocals" --bar 5 --project "Night Drive"
```

```bash
downbeat logic audio export --track "Vocals" --output vocals.wav
```

## Split and join

```bash
downbeat logic region split --region "Chorus" --at-bar 13 --project "Night Drive"
```

```bash
downbeat logic region join --region "Chorus" --bar 9 --project "Night Drive"
```

## Edit notes

```bash
downbeat logic check
```

```bash
downbeat logic region list
```

```bash
downbeat logic note list --track 1 --bar 3
```

```bash
downbeat logic note transpose --track 1 --bar 3 --project MySong --semitones=-2
```

```bash
downbeat logic note add --track 1 --bar 3 --project MySong --pitch F#3 --beat 0 --duration 0.5
```

```bash
downbeat logic note delete --track 1 --bar 3 --project MySong --id 2
```

```bash
downbeat logic note update --track 1 --bar 3 --project MySong --id 2 --pitch D3
```

Edit many notes at once, as JSON:

```bash
downbeat logic note export --track 1 --bar 3 > notes.json
```

```bash
downbeat logic note import notes.json --track 1 --bar 3 --project MySong
```

- Edits replace the region. `--project` must match the front project.
- Keep hands off keyboard and mouse while a command runs.
- Regions with Loop, playback settings, a custom color or several MIDI channels are refused.

## More

- [Commands](docs/commands.md)
- [Arrangements](docs/arrangements.md)
- [EZdrummer](docs/ezdrummer.md)
- [Plan](PLAN.md)
- [How it works and limits](docs/how-it-works.md)
- Agent skill: [skills/downbeat](https://github.com/nvictor/skills/tree/main/downbeat)

## Releasing a change

For every change a user can see:

1. Raise `version` in `Sources/DownbeatCLI/Downbeat.swift`.
2. If the skill relies on the change, raise `minimum` in its `scripts/check-update.sh`.
3. Commit and push both repos.

The skill runs `scripts/check-update.sh` before using downbeat, and tells the user what to update.

## License

[MIT](LICENSE)

Logic and Logic Pro are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This project is not affiliated with or endorsed by Apple Inc. EZdrummer is a trademark of Toontrack Music AB, which is not affiliated with this project either.
