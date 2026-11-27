# logic-cli

Start Logic Pro projects and edit MIDI regions from the command line.

Needs macOS 15+, Logic Pro (English), and Accessibility and Automation permissions.

## Install

```bash
swift build -c release
```

```bash
install -m 755 .build/release/logic ~/.local/bin/logic
```

## Start a project

Once: save an empty project in Logic Pro, then keep it as the template.

```bash
logic project template ~/Music/Logic/Blank.logicx
```

Then:

```bash
logic project new "Night Drive" --tempo 92 --signature 6/8 --key "A minor"
```

## Tracks

```bash
logic track list
```

```bash
logic track create --type instrument --name "Bass" --project "Night Drive"
```

```bash
logic track rename 1 "Drums" --project "Night Drive"
```

## Use

```bash
logic check
```

```bash
logic region list
```

```bash
logic note list --track 1 --bar 3
```

```bash
logic note transpose --track 1 --bar 3 --project MySong --semitones=-2
```

- Edits replace the region. `--project` must match the front project.
- Keep hands off keyboard and mouse while a command runs.
- Regions with Loop, playback settings or a custom color are refused.

## More

- [Commands](docs/commands.md)
- [How it works and limits](docs/spike-roundtrip.md)

## License

[MIT](LICENSE)
