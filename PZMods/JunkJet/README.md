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

## Testing

`TESTING.md` is the build-by-build plan for what only the game can check.
Offline, the arithmetic has its own suites:

```
lua5.1 tests/test_ammorule.lua    what counts as ammo, what the hopper remembers
lua5.1 tests/test_flight.lua      where a fired thing goes and where it lands
```

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

## Loading the Junk Jet

Right-click anything in your inventory → **Load into Junk Jet**. Select a stack,
or several things at once, and the entry says how many it will take.

Loading is a **timed action**, about half a second an item, and it cancels if
you walk. It used to be instant, which was two problems wearing one coat: forty
items became forty rounds mid-horde with no time cost, where crafting a round
takes ten seconds — and it felt like nothing had happened. One action per item,
so a stack of thirty reads as thirty loads you can watch and walk away from.

Two sandbox settings decide what qualifies:

| Setting | Default | What it does |
| --- | --- | --- |
| Only junk can be loaded | on | Restricts it to items the game files under Junk. Turn off and anything qualifies. |
| Heaviest thing you can load | 1.0 | In the game's own units — a toy car is about 0.1, a hammer 2. Set to 0 for no limit. |

Three things are never loadable whatever the settings say: the Junk Jet, its
rounds, and its magazine. Nor is a container, which would take its contents
along with it.

### Why this is not a recipe

The crafting recipe lists about eighty item names, written into a script file
that the game reads once at boot. **No sandbox setting can reach it** — which is
why the config asked for twice on the Workshop page was never possible in that
shape, and why the answer had to be a Lua action instead. Lua can read settings;
a script file cannot.

The rule lives in `common/media/lua/shared/junkJet_ammoRule.lua`, apart from the
menu that uses it and free of game state, because it is the part with a decision
in it and the part `tests/test_ammorule.lua` can check offline.

The crafting recipe still works and still has its list. Deleting it is the other
half of this job — see below.

### The gun remembers what is in it

Loading records the item's type on the weapon, oldest first, not just a count.
Ammo count alone is enough to *fire*; it is not enough to fly a toy car across
the street and let somebody pick the toy car up, and that moment at the hopper
is the only chance the gun ever gets to learn what it is holding.

Stored as one delimited string in the weapon's mod data, because that has to
serialise into the save and sync over the network. Capped at 64 remembered
rounds — mod data rides along on every sync — and rounds past the cap still
fire, they just fire as anonymous junk.

## Flying junk you can pick up

Fire the Junk Jet and the thing you loaded flies, lands, and can be picked up
again. Landing is the part that makes the weapon what it is, and it comes almost
free: the round already knows it was a toy car, so a toy car goes on the ground
and is an ordinary world item from that moment.

The work is split so the half with decisions in it can be tested without the
game:

| File | Does |
| --- | --- |
| `shared/junkJet_flight.lua` | Pure arithmetic. Where the junk is each tick, and when it stops. Touches nothing in the world — the caller injects a function answering "is the way from here to there blocked". |
| `client/junkJet_projectile.lua` | Finds squares, decides what blocked means, draws, drops the item, and hangs off the trigger. |

`tests/test_flight.lua` covers the flight: that a diagonal shot does not travel
further than a straight one, that a blocked shot lands **against** the wall
rather than inside it — junk inside a wall cannot be retrieved — and that a
zero-speed shot terminates instead of hanging the game.

### What is honestly not solved

Every one of these is shared with the mods that already do this, and none of it
is fixed here either:

| Problem | Consequence |
| --- | --- |
| **Walls have no side.** The square test cannot tell a north-south wall from an east-west one, so a shot passing a wall can read as a hit. Where the build offers `isBlockedTo`, the directional question is asked properly; otherwise it falls back, in the one function a fix has to touch. | Occasional phantom stops near walls |
| **No elevation.** Junk flies flat. | Firing off a balcony looks wrong. Bow and Arrow has had this for years |
| **Single-machine.** The shot simulates where it was fired. | Other players do not see it. `JunkJetProjectile.fire()` is a separate entry point precisely so a server command can call it later |
| **`Render3DItem` may not exist on every build.** | Drawing fails quietly and the round still flies and still lands — invisible junk you can pick up beats a Lua error every tick |
| **A repeating weapon breaks the one-shot-at-a-time assumption** both reference mods are built on. | Hard ceiling of 12 in the air; past it junk lands at the muzzle rather than queueing work |
| **`OnWeaponSwing` for a ranged weapon** is the conventional hook but is not confirmed on every build. | If the gun shoots and nothing flies, suspect that line first; `OnPlayerAttackFinished` is the alternative |

## Still to do

### Reference reading

Two existing mods do this and both were read before planning it:

- **Bow and Arrow** moves the arrow using the technique from Nolan's Driving
  Cars mod — the world item is removed and re-placed a square along, every
  tick.
- **Projectile and Targeting System Example** is the same lineage, written as a
  reusable `ISBaseObject`-derived class with its full Lua source included, and
  its newer versions use **`Render3DItem`** rather than shuffling a world item.

Their own pages are candid about the weak points, which is where the table
above came from — the reference mod says arrows are "more lethal in multiplayer
due to game limitations", and that a drawn bow renders wrongly to other players.

### Other

- **Delete the recipe's hardcoded item list.** Build 41 recipes can call a Lua
  function for their inputs (`[Recipe.GetItemTypes.Something]`, which this mod
  already uses for the hammer and saw), so the list could be generated from the
  same rule the menu uses. Whether Build 42's `craftRecipe` has an equivalent
  hook is unknown.
- **Multiplayer check on loading and firing.** Both happen client-side, the way
  vanilla's reload does. Believed right, not verified, and the person who asked
  for the feature runs a multiplayer server. See `TESTING.md`.

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
