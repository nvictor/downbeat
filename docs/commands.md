# Commands

## Implemented

```
downbeat check [--json]
downbeat inspect [--menus] [--json]
downbeat status [--json]
downbeat project new <name> [--tempo n] [--signature 6/8] [--key "A minor"] [--directory d] [--template t]
downbeat project template <path.logicx> [--replace]
downbeat project open <path.logicx>
downbeat project save --project <name>
downbeat project info [--json]
downbeat play
downbeat stop
downbeat record --project <name>
downbeat tempo get
downbeat tempo set <n> --project <name>
downbeat track list [--json]
downbeat track create --type instrument|audio|external [--name n] --project <name>
downbeat track rename <track> <new name> --project <name>
downbeat track select <track> --project <name>
downbeat track mute <track> [--off] --project <name>
downbeat track solo <track> [--off] --project <name>
downbeat midi import <file.mid> [--bar n] --project <name>      # adds tracks
downbeat region list [--track t] [--json]
downbeat region create --track t --bar n [--bars 1] [--name n] --project <name>
downbeat region export <region> --output <file.mid>
downbeat region import <file.mid> <region> --project <name>     # replaces the region
downbeat region delete <region> --project <name>
downbeat note list <region> [--json]
downbeat note add <region> --project <name> --pitch C3 --beat 0 --duration 0.5 [--velocity 100]
downbeat note delete <region> --project <name> --id n
downbeat note update <region> --project <name> --id n [--pitch p] [--beat b] [--duration d] [--velocity v]
downbeat note export <region>                                    # JSON on stdout
downbeat note import <file.json> <region> --project <name>      # replaces the notes
downbeat note transpose <region> --project <name> --semitones n
downbeat note velocity <region> --project <name> --value n
downbeat note quantize <region> --project <name> --division 1/16
```

`<region>` is any of `--region <name>`, `--track <name|number>`, `--bar n`, matching one region.

## Planned

See [PLAN.md](../PLAN.md).

## Rules

- `--json` on all read commands.
- Note ids are valid for one region snapshot only.
