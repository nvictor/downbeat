# Plan

## Next

- [ ] Try it on a copy of an `Atalanta` project
- [ ] Search trademark databases for `downbeat` before promoting it

## Remaining commands

Names can change.

### Notes

- [ ] `downbeat note add --region "Intro" --pitch C4 --beat 1 --duration 0.5 --velocity 100`
- [ ] `downbeat note delete --region "Intro" --id 12`
- [ ] `downbeat note update --region "Intro" --id 12 --pitch D4`
- [ ] `downbeat note export --region "Intro" > notes.json`
- [ ] `downbeat note import --region "Intro" notes.json`

### Quick wins

- [ ] `downbeat play`
- [ ] `downbeat stop`
- [ ] `downbeat record`
- [ ] `downbeat track select "Drums"`
- [ ] `downbeat track mute "Bass"`
- [ ] `downbeat track solo "Lead Guitar"`
- [ ] `downbeat project open <path.logicx>`
- [ ] `downbeat project save`
- [ ] `downbeat project info`
- [ ] `downbeat midi import drums.mid`
- [ ] `downbeat region delete "Verse"`

### Needs experiments

- [ ] `downbeat region create --track "Drums" --bar 1 --bars 4`
- [ ] `downbeat region rename "Verse" "Intro"`
- [ ] `downbeat region duplicate "Intro" --bar 5`
- [ ] `downbeat region move "Intro" --bar 9`
- [ ] `downbeat mixer volume "Bass" -6`
- [ ] `downbeat mixer pan "Lead Guitar" 20`
- [ ] `downbeat marker create "Intro" --bar 1`
- [ ] `downbeat midi ports`

## Later

- [ ] `--version`
- [ ] Homebrew distribution
- [ ] GUS, MEL and HAL integration
- [ ] Scripter bridge (virtual MIDI ports)
- [ ] MCP adapter
- [ ] Plugin management
- [ ] Audio editing
