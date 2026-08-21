# Nuke Strike

A nuclear strike you can call on any map coordinate in Project Zomboid
**Build 42**. It levels buildings, sets the ground alight, kills everything in
the radius, wrecks the cars, and leaves a toxic haze behind for three days.

Works in single player, in a co-op Host game and on a dedicated server.

```
/nuke 10500 9500        call a strike on a map coordinate
/nuke roll 10500 9500   roll a d6, and only detonate on a six
```

The second one is the point of the mod: roll where everybody can see it, and if
it comes up six, the coordinates you picked off the map stop being hypothetical.

## Install

Copy the `NukeStrike` folder into `Zomboid/mods/`, so that
`Zomboid/mods/NukeStrike/42/mod.info` exists. Nesting it one level too deep is
the most common install mistake.

**Hosting from the game:** enable it in the mod list when you set up the world,
the same as any other mod.

**Dedicated server:** add it to `servertest.ini`:

```ini
Mods=NukeStrike
WorkshopItems=
```

Every player needs the same folder in their own `Zomboid/mods/` unless it is a
Workshop item — the client half draws the flash and the haze, so a player without
it will see a building fall over in silence. Restart after installing; mods are
not hot-loadable.

## Two ways to set one off

**Right-click the ground.** A **Nuke Strike** submenu appears on any square, with
*Call a strike on x, y*, *Roll the die for x, y*, and *Call one with no warning*.
The coordinates on the labels are the square you clicked. This is the trigger to
use in single player, which has no dependable chat box, and it is the quickest
one anywhere: point at the spot and click.

**Type `/nuke`.** Press **T** or **Enter** to open chat on a server, then type the
command. This is the one you want when the coordinates came off a map rather than
off your screen — you cannot right-click a place you are not standing near.

The menu only shows for people who could call a strike anyway, but that is a
courtesy rather than a lock: the server checks again when the command arrives,
and its answer is the one that counts.

## Commands

Anyone can type these. The server decides whether to listen, and by default only
admins are listened to (sandbox option **Admins only**). `status` and `coords`
are open to everyone.

| Command | What it does |
| --- | --- |
| `/nuke <x> <y> [radius]` | Strike a map coordinate. `10500,9500` works too. |
| `/nuke here [radius]` | Strike where you are standing. |
| `/nuke player <name> [radius]` | Strike a player. |
| `/nuke roll <target>` | Roll a d6 in front of everyone. Six detonates; anything else does not. |
| `/nuke now <target>` | Skip the warning countdown. |
| `/nuke status` | What is inbound, and what is still glowing. |
| `/nuke coords` | Print your own coordinates. |
| `/nuke abort` | Call back an inbound strike. |
| `/nuke clear` | Forget every strike and clear the haze. |

`roll` and `now` compose with any target: `/nuke roll now here` is legal, if
unwise.

### Finding the coordinates

`/nuke coords` prints where you are standing. For picking a target off a picture
of the map, [map.projectzomboid.com](https://map.projectzomboid.com) gives you
the cell and tile coordinates of anywhere you click — the numbers it shows for a
tile are exactly what `/nuke` wants. Knox County runs from roughly 3000 to 15000
on both axes; Muldraugh is around 10600, 9600 and West Point around 11700, 6800.

## What happens

1. **The sirens.** Everyone is told a strike is inbound and where. A countdown
   runs on screen for thirty seconds by default, which is enough time to drive
   out if you are quick, and not enough if you stop for your bag.
2. **The flash.** The screen whites out for anyone in line of sight, hardest for
   whoever was closest.
3. **The sound, late.** The bang lags the light in proportion to distance — four
   seconds at two hundred tiles, and a low rumble instead of a crack for anyone
   far enough out that they only hear the weather change.
4. **The blast.** It spreads outwards from ground zero as a wave rather than all
   at once, and the wave is what the destruction rides on:

   | Ring | What is left |
   | --- | --- |
   | Inner 40% | Nothing above the ground. Walls, furniture, trees, upper storeys. Everything alive is gone; zombies are deleted rather than killed, because thousands of corpses is a frame rate problem, not a feature. |
   | Out to 75% | Most structures collapse, fires are common, almost everything alive dies. |
   | Out to 100% | Windows out, roofs stripped, scattered fires, about half of what is alive. |

   The ground floor tile is always left behind, so the ruins are walkable rather
   than a hole in the world.
5. **The cars.** A vehicle inside the fireball is taken out of the world
   outright; further out its parts are all ruined — dead engine, flat tyres,
   smashed windows — and it is very likely left burning. Ruining the parts alone
   is close to invisible, which is why the fireball deletes and the outer rings
   burn. Every strike prints a line to `console.txt` saying how many vehicles it
   found and what it did to them, so "it did nothing to the cars" is answerable.
6. **The fires.** Capped (250 by default) and spread across the whole blast
   rather than clustered at the middle, then they spread on their own. This is
   the setting to turn down first if the server chugs after a strike.
7. **The haze.** For 72 in-game hours a cloud half again as wide as the blast
   sits over the area. Standing in it costs you health, makes you sick and drains
   your endurance, worst at the middle. A gas mask or respirator halves it; a
   hazmat suit blocks most of it; both together still let a little through.
   Bandits caught in it die at the same rate a player would; zombies ignore it.

Everything is tunable in the sandbox options under **Nuke Strike**.

### Bandits and NPCs

Bandits, and the NPCs from **Week One**, are `IsoZombie` under the skin — the
same class, flagged with a `Bandit` variable and given a Lua brain in their mod
data. The blast kills them through the same pass that kills the zombies, with no
special handling, so a strike clears a bandit camp exactly as thoroughly as it
clears a horde.

The **haze** does tell them apart, because it has to. Bandits are living people,
so standing in fallout kills them at the same rate it kills a player — exposure
accumulates in their mod data and they drop at the point a player breathing the
same air would have. Zombies are left alone: they are already dead, and killing
every one that wanders into a three-day cloud would quietly clear the map. With
no Bandits mod installed this finds nothing and costs one variable read per
loaded zombie every ten in-game minutes. Sandbox option **Fallout kills
bandits**.

## Two things worth knowing before you use it

**Most of the map is not there.** Project Zomboid only holds the ground near a
player in memory, and ground that is not in memory cannot be destroyed. A 200
tile radius is far larger than what any one player has loaded. So the strike is
written down as well as carried out: whatever is loaded is levelled immediately,
and the rest is levelled **as it loads**. Drive out to a strike you never saw and
you find the ruins waiting. The one thing that does not survive the wait is fires
and kills, which only apply during the twenty minutes after the blast — the bomb
knocking a house down a week before you arrive makes sense, the bomb setting it
alight as you walk up does not.

**It is not free.** A 200 tile strike is around 125,000 tiles of work. That is
why it is metered out at 250 tiles a frame instead of done in one go, and why it
takes several seconds of real time to finish sweeping. Lower **Squares processed
per tick** if a strike stutters your server, and lower **Maximum fires** if the
minutes afterwards do.

## The screen overlay

The white flash and the green haze tint are drawn by a full-screen UI element,
and a full-screen element sitting in the game's UI manager swallows every mouse
event behind it. Get that wrong and the player loses right-click on *everything*
— doors, corpses, inventory — not just on this mod.

Two rules keep it honest, and both are covered by `tests/test_client.lua`:

* It is made click-through **before** it goes on screen, never after, so there is
  no window where it is live and still eating clicks.
* If a build has no way to make it click-through, it is **never added at all**
  and the visuals are given up. The flash and the tint are worth having; they are
  not worth a broken mouse. Look for a `[NukeStrike]` line in `console.txt`
  saying so.

It is also only on screen while it has something to say — a flash, a countdown,
or fallout you are actually standing in. The rest of the time there is no element
at all, which is the strongest guarantee available that it is not in the way.

## Sounds

The three `.wav` files in `42/media/sound/` are synthesised placeholders — a
blast, a distant rumble and an air-raid siren. They work, and they are meant to
be replaced. Drop your own files in with the same names, or point `NS.SOUND_*` in
`42/media/lua/shared/NukeStrike_Shared.lua` at a sound event from another mod.

## Where it runs

| Mode | Blast | Haze | Commands |
| --- | --- | --- | --- |
| Single player | Yes | Yes | Yes, no admin check — it is your world |
| Co-op **Host** game | Yes | Yes | Yes, the host runs the server in-process |
| Dedicated server | Yes | Yes | Yes, admins only by default |
| Connected client | — | Sees it | Types the command; the server decides |

A Host game is not a dedicated server: `isServer()` is false there, and for the
host `isClient()` is false too. Single player has both false. So the mod gates on
`not isClient()` for the authoritative half and `not isServer()` for the
player-facing half, which gives the host and the single player both halves and
gives a connected client only the second.

Nothing a client sends is trusted. The client parses the line you typed and
forwards what it means; every decision about whether that is allowed, where it
lands and who it hurts is made on the server.

## Layout

```
NukeStrike/
├── README.md
├── tests/                    offline logic tests, outside 42/ so the game ignores them
└── 42/
    ├── mod.info
    ├── poster.png
    └── media/
        ├── sandbox-options.txt
        ├── scripts/          the three sound definitions
        ├── sound/            placeholder .wav files
        └── lua/
            ├── shared/       gating, options, geometry, command parsing, networking
            ├── server/       Zones (what has been nuked), Blast (doing it), Server (commands, fallout)
            └── client/       Client (flash, sound, haze overlay), Commands (/nuke), ContextMenu (right-click)
```

Build 42 only loads files from the version folder matching the running build, and
`mod.info` lives *inside* that folder. To also ship a Build 41 version, add a
sibling `41/` folder with its own `mod.info`.

The sub-tables the server files fill (`Zones`, `Blast`, `Server`) are created in
`shared/`, not in the files that fill them. The game loads a folder's Lua files
alphabetically, so `NukeStrike_Blast.lua` runs before `NukeStrike_Zones.lua`;
creating the tables in shared — which loads before both — means every file
captures the same table whatever the order.

## A note on the engine calls

This mod reaches into a lot of the game: object removal, fire, body damage,
vehicle parts, sound. The exact names of those calls have moved between builds.
Every one of them goes through `NS.try()`, which reports a call that is missing
**once** and then stops making it, instead of throwing sixty times a second from
inside the blast loop. If something does not work on your build, the log will say
which call it was on the first attempt — search `console.txt` for `[NukeStrike]`.

## Tests

Offline checks for the parts that do not need the game running: the geometry, the
command parsing, the zone bookkeeping, the server's decisions, and the blast
engine driven against a toy world. They stub the game's globals and drive the
real mod files with `dofile`.

They cannot test anything the game owns — whether the events fire, whether
`transmitRemoveItemFromSquare` really removes a wall, whether the mod loads at
all. That still needs a live server.

Run from the **repository root**:

```bash
lua5.1 PZMods/NukeStrike/tests/test_targeting.lua
lua5.1 PZMods/NukeStrike/tests/test_zones.lua
lua5.1 PZMods/NukeStrike/tests/test_blast.lua
lua5.1 PZMods/NukeStrike/tests/test_server.lua
sh      PZMods/NukeStrike/tests/test_gating.sh
find PZMods/NukeStrike -name '*.lua' -exec luac5.1 -p {} \;
```

Any Lua 5.1 interpreter works (`apt install lua5.1`). All of them exit non-zero
on failure.
