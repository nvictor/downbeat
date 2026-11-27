# Plan

V1: MIDI region and note editing in Logic Pro, plus a skill.

- [x] Round-trip spike: go, with limits ([findings](docs/spike-roundtrip.md))
- [x] Commit the spike
- [ ] Close the remaining risks
  - [x] Loop, quantize, transpose and velocity settings
  - [ ] Region color
  - [x] Meters other than 4/4 (tested 3/4)
  - [x] Several regions on one track
- [x] Undo automatically when `replace` stops midway
- [x] Decide how to treat Loop and region settings, then enforce it
- [x] `logic region list`, `export`, `import`
- [x] `logic note list`, `transpose`, `velocity`, `quantize`, with `--json`
- [x] `SKILL.md` in `~/Developer/skills/logic-cli`

All commands, including later ones: [docs/commands.md](docs/commands.md).
