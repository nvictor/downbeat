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

See [PLAN.md](../PLAN.md).

## Rules

- `--json` on all read commands.
- Note ids are valid for one region snapshot only.
