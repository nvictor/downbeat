# Commands

## Implemented

```
downbeat --version
downbeat midi build <arrangement.json> --output <folder> [--per section|part] [--section s] [--replace] [--json]
downbeat midi inspect <file.mid>... [--map m | --arrangement a.json] [--json]
downbeat midi edit <arrangement.json> <operations.json> [--dry-run] [--json]
downbeat midi humanize <arrangement.json> --section s --seed n [--timing q] [--velocity n] [--drop p]
                       [--part p] [--bars r] [--articulation a] [--clear] [--dry-run]
downbeat midi ports [--json]
downbeat ezdrummer inspect <project.ezd3p> [--notes] [--json]
downbeat logic check [--json]
downbeat logic inspect [--menus] [--json]
downbeat logic status [--json]
downbeat logic project new <name> [--tempo n] [--signature 6/8] [--key "A minor"] [--directory d] [--template t]
downbeat logic project template [<path.logicx> [--replace]]
downbeat logic project open <path.logicx>
downbeat logic project save --project <name>
downbeat logic project info [--json]
downbeat logic play
downbeat logic stop
downbeat logic record --project <name>
downbeat logic tempo get
downbeat logic tempo set <n> --project <name>
downbeat logic track list [--json]
downbeat logic track create --type instrument|audio|external [--name n] --project <name>
downbeat logic track rename <track> <new name> --project <name>
downbeat logic track select <track> --project <name>
downbeat logic track mute <track> [--off] --project <name>
downbeat logic track solo <track> [--off] --project <name>
downbeat logic mixer volume <track> --db n --project <name>           # up to +6, or -inf
downbeat logic mixer pan <track> --value n --project <name>           # -64 to 63
downbeat logic marker create <name> --bar n --project <name>
downbeat logic plugin list <track> [--json]
downbeat logic plugin add <track> <plugin> [--format f] --project <name>
downbeat logic plugin remove <track> <plugin> --project <name>
downbeat logic plugin bypass <track> <plugin> [--off] --project <name>
downbeat logic audio import <file> --track t --bar n --project <name>
downbeat logic audio export --track t --output <file.wav>
downbeat logic midi import <file.mid> [--bar n] --project <name>      # adds tracks
downbeat logic region list [--track t] [--json]
downbeat logic region create --track t --bar n [--bars 1] [--name n] --project <name>
downbeat logic region rename <new name> <region> --project <name>
downbeat logic region move <region> --to-bar n --project <name>
downbeat logic region duplicate <region> --to-bar n --project <name>
downbeat logic region split <region> --at-bar n [--notes keep|shorten|split] --project <name>
downbeat logic region join <region> --project <name>                  # with the next one
downbeat logic region export <region> --output <file.mid>
downbeat logic region import <file.mid> <region> --project <name>     # replaces the region
downbeat logic region delete <region> --project <name>
downbeat logic note list <region> [--json]
downbeat logic note add <region> --project <name> --pitch C3 --beat 0 --duration 0.5 [--velocity 100]
downbeat logic note delete <region> --project <name> --id n
downbeat logic note update <region> --project <name> --id n [--pitch p] [--beat b] [--duration d] [--velocity v]
downbeat logic note export <region>                                    # JSON on stdout
downbeat logic note import <file.json> <region> --project <name>      # replaces the notes
downbeat logic note transpose <region> --project <name> --semitones n
downbeat logic note velocity <region> --project <name> --value n
downbeat logic note quantize <region> --project <name> --division 1/16
```

See [Arrangements](arrangements.md) and [EZdrummer](ezdrummer.md).

`<region>` is any of `--region <name>`, `--track <name|number>`, `--bar n`, matching one region.
`--bar` is the bar the region starts in. MIDI export, import and note commands need a region on bar lines.

## Planned

See [PLAN.md](../PLAN.md).

## Rules

- `--json` on all read commands.
- Note ids are valid for one region snapshot only.
