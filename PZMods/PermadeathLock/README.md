# Permadeath Lock

Permadeath for Project Zomboid **Build 42** multiplayer — dedicated servers and
co-op Host games alike. When a player dies they go on a death list and cannot
come back with a new character. Admins can pardon
someone (fresh start) or revive them (new character, old skills), and players
carrying a **Fate Token** buy back one death without needing an admin at all.

## Install

Copy the `PermadeathLock` folder into `Zomboid/mods/`, so that
`Zomboid/mods/PermadeathLock/42/mod.info` exists. Nesting it one level too deep is
the most common install mistake.

**Hosting from the game:** enable it in the mod list when you set up the world,
the same as any other mod.

**Dedicated server:** add it to `servertest.ini`:

```ini
Mods=PermadeathLock
WorkshopItems=
```

Every player needs the same folder in their own `Zomboid/mods/` unless it is a
Workshop item. Restart after installing — mods are not hot-loadable.

### Folder layout

```
PermadeathLock/
└── 42/
    ├── mod.info
    ├── poster.png
    └── media/
        ├── sandbox-options.txt
        ├── scripts/          item script for the Fate Token
        ├── textures/         its inventory icon
        └── lua/{shared,server,client}/
```

Build 42 only loads files from the version folder matching the running build, and
`mod.info` lives *inside* that folder. To also ship a Build 41 version, add a
sibling `41/` folder with its own `mod.info`, and move anything identical between
the two into `common/media/`.

## Where it runs

| Mode | Enforced? |
| --- | --- |
| Dedicated server | Yes |
| Co-op **Host** game | Yes - the host runs the server in-process |
| Single player | No, by design - loads and does nothing |

A Host game is not a dedicated server: `isServer()` is false there, and for the
host `isClient()` is false too. The mod therefore gates on `isCoopHost()` as well,
so the host gets both halves - they are the server *and* a player.

**If you are hosting, you are almost certainly an admin, and `ExemptAdmins`
defaults to on** - your deaths will be ignored until you turn it off in the
sandbox settings. That looks identical to the mod being broken.

## How enforcement works

The game gives server Lua **no "player connected" event and no kick function**, so
the mod uses two paths:

| Path | Trigger | What it does |
| --- | --- | --- |
| Client handshake | `OnPlayerDeath`, `OnCreatePlayer` | Reports the death, asks for status on spawn. Gives the player a readable notice and disconnects them. |
| Server sweep | `EveryOneMinute` over `getOnlinePlayers()` | Records any dead player, and catches anyone locked out who is walking around. |

The handshake is the polite path and the sweep is the authoritative one. A player
running a modified client that never reports its death is still caught by the
sweep within one in-game minute: they are asked to leave, and if they are still
in the world on the next sweep their character is killed (sandbox option
`EnforceKill`). Killing is the strongest action available — the game does not
expose a kick to server Lua.

Nothing the client sends is trusted. Death reports are checked against
`player:isDead()`, and admin commands are re-checked against the sender's real
access level on the server.

## Sandbox options

Under **Permadeath Lock** in the sandbox settings:

| Option | Default | Effect |
| --- | --- | --- |
| `Enabled` | on | Suspends the lock when off. The death list is kept. |
| `ExemptAdmins` | on | Admins are never recorded or blocked. Stops you locking yourself out. |
| `EnforceKill` | on | Kill locked-out players whose client ignored the disconnect request. |
| `RestoreSkillsOnRevive` | on | Revived players get their old skill levels on their next character. |
| `FateTokenEnabled` | on | Dying with a Fate Token spends it instead of locking you out. |
| `FateTokenConsume` | on | The token is removed from the body when it saves someone. Off = lootable and reusable. |

## Admin commands

Type these in chat as an admin (`/pd` is a shorthand):

```
/permadeath status          is the lock on, and how many are locked out
/permadeath list            show the death list
/permadeath revive <user>   bring a player back, keeping their skills
/permadeath pardon <user>   let a player back in, from scratch
/permadeath add <user>      lock a player out by hand
/permadeath clear confirm   wipe the whole death list
/permadeath reload          re-read the death list from disk
```

Usernames are matched case-insensitively.

### Revive vs pardon

**A dead character cannot be brought back to life.** The Lua API exposes no way to
clear a character's dead flag — `setDead` exists only on `SurvivorDesc`, the NPC
descriptor, not on a live `IsoPlayer`. Any mod claiming otherwise is restoring a
replacement character, not the original.

So "revive" means: unlock the player, and hand their **next** character the skill
levels the dead one had.

- Target **offline** → they are unlocked, and their skills are restored the moment
  they log in with a new character.
- Target **online but dead** → same, but they must reconnect first; the corpse
  stays a corpse. The command tells you so.
- Target **online and alive** (they already made a new character) → skills are
  restored immediately and they are healed to full.

`pardon` just removes them from the list — they come back with nothing.

Skills are restored, not overwritten: a level the new character already exceeds is
left alone. Traits, profession and inventory are **not** restored — traits are not
readable from the Lua API in B42, and inventory would need item serialisation.

## The Fate Token

`Base.FateToken` is an item that buys back one death. Die carrying one — anywhere
on you, bags included — and the token burns away instead of locking you out. Your
next character comes back with the skills the dead one had, automatically, with no
admin involved.

It does **not** stop you dying. There is no pre-death hook in the game, so nothing
can veto a killing blow; the token is insurance that pays out afterwards, not a
shield. Your corpse and everything on it still stay where they fell.

One token is spent per death. Carrying three does not make you immortal three
times over in a single death — but the other two are still on the body.

### Handing them out

Nothing spawns them by default; that is a deliberate balance decision left to you.
Give one out with:

```
/additem <username> Base.FateToken
```

To make them lootable instead, add a distribution file under
`42/media/lua/server/` — for a rare medical-cabinet spawn:

```lua
require 'Items/ProceduralDistributions'
table.insert(ProceduralDistributions.list["MedicalClinicMisc"].items, "Base.FateToken")
table.insert(ProceduralDistributions.list["MedicalClinicMisc"].items, 0.5)
```

The number is a weight, not a percentage — keep it low.

## The death list

Stored at `Zomboid/Lua/PermadeathLock_deaths.txt`, one tab-separated record per
line:

```
username <tab> steamID <tab> timestamp <tab> reason <tab> skills <tab> locked <tab> pendingRestore
```

It is plain text on purpose: you can edit it with the server down and then run
`/permadeath reload`, or just add a bare username on its own line to lock someone
out. Lines starting with `#` are ignored. The Steam ID is recorded for
identification only — matching is always by username.

## Testing it

1. Start with `ExemptAdmins` **off** (otherwise you will never trigger it as an
   admin, and hosts are always admins).
2. Join, then get yourself killed — there is no vanilla `/kill` command, so use
   `/createhorde 30` with godmode off, or the debug menu.
3. Check the console for `[PermadeathLock] <name> died ... and is locked out`, and
   that your name appears in the death list file.
4. Reconnect and make a new character — you should get the notice and be
   disconnected within a few seconds.
5. As an admin (second account, or turn `ExemptAdmins` back on), run
   `/permadeath revive <name>`, reconnect on the first account, and confirm the
   skills come back.
6. For the Fate Token: `/additem <name> Base.FateToken`, die again, and check the
   console says `died holding a Fate Token; not locked out`. You should be able to
   reconnect straight away, with your skills.

Server-side messages are prefixed `[PermadeathLock]` in the console log.

## Known limits

- Dedicated servers and **co-op Host games**. Single player is deliberately left
  alone: the mod loads and does nothing.
- Identity is the username. A player with a second account is a different person
  as far as this mod is concerned.
- The sweep runs once per in-game minute, so a locked-out player may be in the
  world for up to two of those before their character is killed. They cannot get a
  meaningful head start, but they are not blocked instantly either.

## Tests

Offline logic checks live in `tests/`. See `tests/README.md`.
