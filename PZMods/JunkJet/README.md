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
| `41/media/lua/server/junkJet_reload.lua` | Defines `Recipe.OnCreate.junkJetAmmoLoad`. That namespace is B41's crafting system and does not exist in B42, so loading it there would error |

`common/media/scripts/junkJet_fixing.txt` is shared: the fixing syntax is the
same on both builds as far as could be established.

Everything else — textures, models, sounds, translations, distributions, sandbox
options — is shared.

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

## Repairing it

Asked for twice on the Workshop, and until now impossible: `ConditionMax = 10`
with no fixing entry meant the gun degraded and then broke permanently.

| Fixer | Skill | Notes |
| --- | --- | --- |
| Blow torch ×2 | Metalworking 1 | A proper weld, the intended repair |
| Sheet metal ×1 | Metalworking 2 | Patching it up |
| Duct tape ×3 | none | The desperate option |

`ConditionModifier : 2`, matching how the thing is welded together in the first
place.

**Two routes, deliberately.** The `fixing` block covers Build 41 and, as far as
could be established, Build 42. Separately the Build 42 item carries the
`hasMetal` tag, which is what B42's own metal repair recipe keys off. If both
work you get two ways to repair it, which is harmless; once it is known which
one actually fires, delete the other.

## Not yet verified in game

The Build 42 conversion is complete but untested. These are the parts that were
converted from documentation and a reference mod rather than confirmed running,
and they are commented in the script files too:

- `needToBeLearn` — the B42 spelling of B41's `NeedToBeLearn:True`
- `category = Weapons` — B41's category names may not survive into B42
- `item 90 [Base.BlowTorch]` — how B42 counts drainable use in a recipe
- `Base.Pipe` — B42 renamed `MetalPipe`, applied here but unconfirmed for this recipe
- Whether B42 reads `fixing` blocks at all, and whether `hasMetal` is spelled
  that way now that 42.13 moved item tags to an enum

## Fixed on the way through

Two distribution bugs, both present since Build 41 and both silent:

- Four `GarageTools` inserts targeted `ProceduralDistributions.list["GarageTools"]`
  rather than its `.items` list, so the gun and its magazine never spawned in
  garages at all
- `SuburbsDistributions` was used for the postbox spawn without ever being
  required
