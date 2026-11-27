# Plan

## Remaining commands

Names can change.

### Notes

- [ ] `downbeat note delete --region "Intro" --id 12`
- [ ] `downbeat note update --region "Intro" --id 12 --pitch D4`
- [ ] `downbeat note export --region "Intro" > notes.json`
- [ ] `downbeat note import --region "Intro" notes.json`

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
- [ ] Plugin management
- [ ] Audio editing
