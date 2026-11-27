# Plan

V1: MIDI region and note editing in Logic Pro, plus a skill.

- [x] Round-trip spike: go, with limits ([findings](docs/spike-roundtrip.md))
- [x] Commit the spike
- [ ] Close the remaining risks
  - [ ] Region color, loop, quantize and transpose settings
  - [ ] Meters other than 4/4
  - [ ] Several regions on one track
- [ ] Undo automatically when `replace` stops midway
- [ ] `logic region list`, `export`, `import`
- [ ] `logic note list`, `transpose`, `velocity`, `quantize`, with `--json`
- [ ] `SKILL.md` in `~/Developer/skills/logic-cli`

All commands, including later ones: [docs/commands.md](docs/commands.md).
