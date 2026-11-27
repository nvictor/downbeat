# downbeat

A command line tool for Logic Pro: start projects, control playback, manage tracks and edit MIDI notes.

Needs macOS 15+, Logic Pro (English), and Accessibility and Automation permissions.

## Install

```bash
swift build -c release
```

```bash
install -m 755 .build/release/downbeat ~/.local/bin/downbeat
```

## Start a project

Once: save an empty project in Logic Pro, then keep it as the template.

```bash
downbeat project template ~/Music/Logic/Blank.logicx
```

Then:

```bash
downbeat project new "Night Drive" --tempo 92 --signature 6/8 --key "A minor"
```

## Tracks

```bash
downbeat track list
```

```bash
downbeat track create --type instrument --name "Bass" --project "Night Drive"
```

```bash
downbeat track rename 1 "Drums" --project "Night Drive"
```

```bash
downbeat track mute "Bass" --project "Night Drive"
```

## Play and save

```bash
downbeat play
```

```bash
downbeat stop
```

```bash
downbeat project save --project "Night Drive"
```

## Edit notes

```bash
downbeat check
```

```bash
downbeat region list
```

```bash
downbeat note list --track 1 --bar 3
```

```bash
downbeat note transpose --track 1 --bar 3 --project MySong --semitones=-2
```

```bash
downbeat note add --track 1 --bar 3 --project MySong --pitch F#3 --beat 0 --duration 0.5
```

- Edits replace the region. `--project` must match the front project.
- Keep hands off keyboard and mouse while a command runs.
- Regions with Loop, playback settings, a custom color or several MIDI channels are refused.

## More

- [Commands](docs/commands.md)
- [Plan](PLAN.md)
- [How it works and limits](docs/how-it-works.md)
- Agent skill: [skills/downbeat](https://github.com/nvictor/skills/tree/main/downbeat)

## License

[MIT](LICENSE)

Logic and Logic Pro are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This project is not affiliated with or endorsed by Apple Inc.
