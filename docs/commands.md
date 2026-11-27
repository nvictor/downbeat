# Commands

## Implemented

```
logic check [--json]
logic inspect [--menus] [--json]
logic status [--json]
logic project new <name> [--tempo n] [--signature 6/8] [--key "A minor"] [--directory d] [--template t]
logic project template <path.logicx> [--replace]
logic tempo get
logic tempo set <n> --project <name>
logic region list [--track t] [--json]
logic region export <region> --output <file.mid>
logic region import <file.mid> <region> --project <name>     # replaces the region
logic note list <region> [--json]
logic note transpose <region> --project <name> --semitones n
logic note velocity <region> --project <name> --value n
logic note quantize <region> --project <name> --division 1/16
```

`<region>` is any of `--region <name>`, `--track <name|number>`, `--bar n`, matching one region.

## Planned

Proposed, not implemented. Names can change.

```
# diagnostics
logic menus
logic windows
logic midi ports

# transport
logic play
logic stop
logic record

# project
logic project open <path.logicx>
logic project save
logic project info

# tracks
logic track list [--json]
logic track select "Drums"
logic track create --type instrument --name "Bass"
logic track mute "Bass"
logic track solo "Lead Guitar"

# mixer
logic mixer volume "Bass" -6
logic mixer pan "Lead Guitar" 20

# markers
logic marker create "Intro" --bar 1

# MIDI files
logic midi import drums.mid

# regions
logic region create --track "Drums" --bar 1 --bars 4
logic region delete "Verse"
logic region rename "Verse" "Intro"
logic region duplicate "Intro" --bar 5
logic region move "Intro" --bar 9

# notes
logic note add --region "Intro" --pitch C4 --beat 1 --duration 0.5 --velocity 100
logic note delete --region "Intro" --id 12
logic note update --region "Intro" --id 12 --pitch D4
logic note export --region "Intro" > notes.json
logic note import --region "Intro" notes.json
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
