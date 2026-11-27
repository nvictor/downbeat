# logic-cli

Edit MIDI regions in Logic Pro from the command line.

Needs macOS 15+, Logic Pro (English), and Accessibility and Automation permissions.

## Install

```bash
swift build -c release
```

```bash
install -m 755 .build/release/logic ~/.local/bin/logic
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
