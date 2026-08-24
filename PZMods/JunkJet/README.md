# Fallout 4 Junk Jet

Fires scavenged junk. [Steam Workshop item 3005797817](https://steamcommunity.com/sharedfiles/filedetails/?id=3005797817).

## Layout

```
JunkJet/
├── workshop.txt      Steam metadata, in version control rather than only on Steam
├── preview.png       Workshop thumbnail
├── common/media/     everything identical on both builds
├── 41/               Build 41: mod.info, poster, icon, B41 scripts and Lua
└── 42/               Build 42: mod.info, poster, icon, B42 scripts
```

Build 42 loads `common/` plus the folder matching the running build, and
`mod.info` lives *inside* each version folder. One upload serves both, which
matters because the mod is in use on a Build 41 multiplayer server.

### What is build-specific, and why

| Path | Reason |
| --- | --- |
| `*/media/scripts/junkJet_weapon.txt` | B42 replaced `Type = Weapon` with `ItemType = base:weapon` |
| `*/media/scripts/junkJet_recipe.txt` | B42 replaced `recipe` blocks with `craftRecipe` |
| `41/media/scripts/junkJet_fixing.txt` | `fixing` blocks are confirmed Build 41 syntax. No Build 42 mod I could find repairs anything, so B42 repairability is unproven and not shipped as a guess |
| `41/…/Translate/` vs `42/…/Translate/` | Build 42.15 replaced the Lua-table `Name_EN.txt` with a flat JSON `Name.json`. B41 reads only the `.txt`, so `common/` carries `.txt` alone and `42/` carries both |

Everything else — textures, models, sounds, distributions, sandbox options — is
shared, and so is the crafting callback: Build 42's `craftRecipe` takes
`OnCreate` with the same `(items, result, player)` signature Build 41's `recipe`
did, so `common/media/lua/server/junkJet_reload.lua` serves both. It used to
live in `41/` on the assumption that `Recipe.OnCreate` was Build-41-only, and
Build 42 players silently lost the auto-load as a result.

### Translations are generated

`common/…/Translate/EN/*_EN.txt` are the **source**. Everything else is built:

```
python3 ../../tools/build_translations.py
```

which writes `.txt` into `common/` for Build 41 and both `.txt` and `.json` into
`42/`. This is the layout a large dual-build mod ships, arrived at
independently.

## Installing while working on it

Copy the `JunkJet` folder into `%USERPROFILE%\Zomboid\mods\`, so that
`Zomboid\mods\JunkJet\42\mod.info` exists.

`watch-junkjet.ps1` does that on a loop, so a save reaches the game without a
manual copy:

```powershell
powershell -ExecutionPolicy Bypass -File .\watch-junkjet.ps1
```

Mods are not hot-loaded — restart the game or server to pick changes up.

### There is no build step

This used to be a [pzstudio](https://github.com/Konijima/project-zomboid-studio)
project. That tool was dropped: its last release was May 2023, it emits only the
flat Build 41 layout with no version folders, and its templates are not in this
repository, so it could not be patched in a way that survives a reinstall.

`mod.info` and `workshop.txt` are now written by hand and checked in.

## Not yet verified in game

The Build 42 conversion is complete but untested. These are the parts that were
converted from documentation and a reference mod rather than confirmed running,
and they are commented in the script files too:

- `needToBeLearn` — the B42 spelling of B41's `NeedToBeLearn:True`
- `category = Weapons` — B41's category names may not survive into B42
- `item 90 [Base.BlowTorch]` — how B42 counts drainable use in a recipe
- `Base.Pipe` — B42 renamed `MetalPipe`, applied here but unconfirmed for this recipe

## Fixed on the way through

Two distribution bugs, both present since Build 41 and both silent:

- Four `GarageTools` inserts targeted `ProceduralDistributions.list["GarageTools"]`
  rather than its `.items` list, so the gun and its magazine never spawned in
  garages at all
- `SuburbsDistributions` was used for the postbox spawn without ever being
  required
