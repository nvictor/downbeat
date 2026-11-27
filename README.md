# logic-cli

A command line tool for Logic Pro. V1 targets MIDI region and note editing.

Status: V1 commands work on Logic Pro 13.0. Findings and limits: [docs/spike-roundtrip.md](docs/spike-roundtrip.md).

## Requirements

- macOS 15 or later
- Logic Pro, English UI
- Accessibility permission for the app that runs `logic`
- Automation permission for System Events

## Install

```bash
swift build -c release
```

```bash
install -m 755 .build/release/logic ~/.local/bin/logic
```

## Usage

```bash
logic check
```

```bash
logic region list
```

```bash
logic note list --track 1 --bar 3
```

Editing replaces the region. `--project` must match the front project.
Keep hands off keyboard and mouse while a command runs.

```bash
logic note transpose --track 1 --bar 3 --project RoundTrip --semitones=-2
```

```bash
logic region export --track 1 --bar 3 --output /tmp/part.mid
```

```bash
logic region import /tmp/part.mid --track 1 --bar 3 --project RoundTrip
```

Regions with Loop or playback settings are refused.

The agent skill lives in `~/Developer/skills/logic-cli`.

## Commands

Implemented and planned: [docs/commands.md](docs/commands.md).

## License

[MIT](LICENSE).
