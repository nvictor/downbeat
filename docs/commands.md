# Commands

## Implemented

```
logic check [--json]                    # setup check (ChatGPT: doctor)
logic inspect [--menus] [--json]        # accessibility tree
logic spike tracks                      # visible tracks and regions
logic spike export <out.mid>            # selected region
logic spike import <in.mid>             # onto a new track
logic spike replace <in.mid>            # selected region, same track and bars
logic spike transpose <in> <out> --semitones n
logic spike diff <a.mid> <b.mid>
```

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
logic status --json

# project
logic project open <path.logicx>
logic project save
logic project info

# tempo
logic tempo get
logic tempo set 120

# tracks (V1)
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

# regions (V1)
logic region list --track "Drums"
logic region create --track "Drums" --bar 1 --bars 4
logic region delete "Verse"
logic region rename "Verse" "Intro"
logic region duplicate "Intro" --bar 5
logic region move "Intro" --bar 9
logic region export "Intro" --output intro.mid
logic region import intro.mid --track "Drums" --bar 1

# notes (V1)
logic note list --region "Intro" [--json]
logic note add --region "Intro" --pitch C4 --beat 1 --duration 0.5 --velocity 100
logic note delete --region "Intro" --id 12
logic note update --region "Intro" --id 12 --pitch D4
logic note transpose --region "Intro" --semitones 2
logic note quantize --region "Intro" --division 1/16
logic note velocity --region "Intro" --value 100
logic note export --region "Intro" > notes.json
logic note import --region "Intro" notes.json
swift build
swift test
swift run logic check
swift run logic inspect --tree --depth 6
swift run logic spike export /tmp/logic-cli/before.mid
```

## Also deferred

- Scripter bridge (virtual MIDI ports)
- MCP adapter
- Plugin management
- Audio editing
- Homebrew distribution
- `SKILL.md`, in `~/Developer/skills/logic-cli`
- GUS, MEL and HAL integration

## Rules

- `--json` on all read commands.
- Note ids are valid for one region snapshot only.
