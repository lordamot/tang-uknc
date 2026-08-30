# Git Usage

## Branch Model

| Branch | Purpose                                         |
|--------|-------------------------------------------------|
| `main` | ready working solution                          |
| `feat/<name>` | Feature branches (short kebab-case name) |

## Workflow

Work onto mine branch - allowed.
Never push.
Always ask before commit something.

## Commit Messages

Short imperative subject line, no period. Examples:

```
fix ay chipselect aliasing
document ppu register map
```

- Keep subject under 72 characters
- No ticket/issue prefix required
- English only

## What Not to Commit

- `/.idea/`, `/.vscode/` - editor state
- `/tools/` - the fetched toolchain, ~5 GB, restored by `make toolchain`
- `/build/`, `/sim/out/`, `/mnano/build/` - build products
  (those five are the whole of `.gitignore`)
- New Gowin scratch.  Note that the existing `temp/` directories **are**
  tracked - 72 files under `tang/impl/temp/` and `tang/src/**/ip/*/temp/`
  went in with the initial import, so `.gitignore` would not touch them
  now.  Leave them alone: do not add more, and do not stage the churn when
  the IDE rewrites them.

## What *is* committed on purpose

- **`bin/tang.fs` and `bin/bl616.bin`** - the two shipped binaries, so a
  user can flash without a toolchain.  They are the point of the repo for
  anyone who is not developing it.
- **`tang/impl/pnr/`** - the last place-and-route output, including its
  reports.  `test003.rpt.txt` is the only record of the resource budget and
  `test003.log` the only record of the clock-domain warnings, and neither
  can be regenerated on this host.  Do not clean them out.
- **`.mif` files under `tang/rom*/`** - ROM images the IP cores are
  initialised from.  Binary in effect, but they are build inputs.

## Working tree noise

The tree usually shows a long list of `mode change 100755 => 100644`
entries plus one deleted symlink under `mnano/u8g2/`.  That is a checkout
artefact, not work.  Do not "fix" it by committing the mode changes, and do
not let it hide a real edit - use `git diff --summary` to tell them apart.
