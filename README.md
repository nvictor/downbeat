# logic-cli

A command line tool for Logic Pro. V1 targets MIDI region and note editing.

Status: round-trip spike done, go with limits. See [docs/spike-roundtrip.md](docs/spike-roundtrip.md).

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
swift run logic check
```

```bash
swift run logic inspect --tree --depth 6
```

`logic spike` commands are throwaway experiments. Run them on a scratch project only (`RoundTrip` by default).
Keep hands off keyboard and mouse while they run.

```bash
swift run logic spike export /tmp/logic-cli/before.mid
```

Export removes the extra pitch bend points Logic Pro adds to ramps.

```bash
swift run logic spike transpose /tmp/logic-cli/before.mid /tmp/logic-cli/edited.mid --semitones 2
```

Replace the selected region with the edited file. If it stops midway, use Undo in Logic Pro.

```bash
swift run logic spike replace /tmp/logic-cli/edited.mid
```

## Commands

Implemented and planned: [docs/commands.md](docs/commands.md).

## License

[MIT](LICENSE).
