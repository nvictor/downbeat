# Commands

## Implemented

```
downbeat check [--json]
downbeat inspect [--menus] [--json]
downbeat status [--json]
downbeat project new <name> [--tempo n] [--signature 6/8] [--key "A minor"] [--directory d] [--template t]
downbeat project template <path.logicx> [--replace]
downbeat tempo get
downbeat tempo set <n> --project <name>
downbeat track list [--json]
downbeat track create --type instrument|audio|external [--name n] --project <name>
downbeat track rename <track> <new name> --project <name>
downbeat region list [--track t] [--json]
downbeat region export <region> --output <file.mid>
downbeat region import <file.mid> <region> --project <name>     # replaces the region
downbeat note list <region> [--json]
downbeat note transpose <region> --project <name> --semitones n
downbeat note velocity <region> --project <name> --value n
downbeat note quantize <region> --project <name> --division 1/16
```

`<region>` is any of `--region <name>`, `--track <name|number>`, `--bar n`, matching one region.

## Planned

Proposed, not implemented. Names can change.

```
# diagnostics
downbeat midi ports

# transport
downbeat play
downbeat stop
downbeat record

# project
downbeat project open <path.logicx>
downbeat project save
downbeat project info

# tracks
downbeat track select "Drums"
downbeat track mute "Bass"
downbeat track solo "Lead Guitar"

# mixer
downbeat mixer volume "Bass" -6
downbeat mixer pan "Lead Guitar" 20

# markers
downbeat marker create "Intro" --bar 1

# MIDI files
downbeat midi import drums.mid

# regions
downbeat region create --track "Drums" --bar 1 --bars 4
downbeat region delete "Verse"
downbeat region rename "Verse" "Intro"
downbeat region duplicate "Intro" --bar 5
downbeat region move "Intro" --bar 9

# notes
downbeat note add --region "Intro" --pitch C4 --beat 1 --duration 0.5 --velocity 100
downbeat note delete --region "Intro" --id 12
downbeat note update --region "Intro" --id 12 --pitch D4
downbeat note export --region "Intro" > notes.json
downbeat note import --region "Intro" notes.json
```

## Also deferred

- Scripter bridge (virtual MIDI ports)
- MCP adapter
- Plugin management
- Audio editing
- Homebrew distribution
- GUS, MEL and HAL integration

## Rules

- `--json` on all read commands.
- Note ids are valid for one region snapshot only.
