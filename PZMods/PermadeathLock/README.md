# Permadeath Lock

Dedicated-server permadeath for Project Zomboid **Build 42**. When a player dies they
go on a death list and cannot come back with a new character. Admins can pardon
someone (fresh start) or revive them (new character, old skills).

## Install

Copy the `PermadeathLock` folder into the server's mod directory, then add it to
`servertest.ini`:

```ini
Mods=PermadeathLock
WorkshopItems=
```

Clients connecting to the server download it automatically if it is a Workshop
item; if you are running it as a local mod, every player needs the same folder in
their `Zomboid/mods/`. Restart the server after installing — mods are not
hot-loadable.

### Folder layout

```
PermadeathLock/
└── 42/
    ├── mod.info
    ├── poster.png
    └── media/
        ├── sandbox-options.txt
        └── lua/{shared,server,client}/
```

Build 42 only loads files from the version folder matching the running build, and
`mod.info` lives *inside* that folder. To also ship a Build 41 version, add a
sibling `41/` folder with its own `mod.info`, and move anything identical between
the two into `common/media/`.

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

1. Start the server with `ExemptAdmins` **off** (otherwise you will never trigger
   it as an admin).
2. Join, then `/kill` yourself or take a bite.
3. Check the console for `[PermadeathLock] <name> died ... and is locked out`, and
   that your name appears in the death list file.
4. Reconnect and make a new character — you should get the notice and be
   disconnected within a few seconds.
5. As an admin (second account, or turn `ExemptAdmins` back on), run
   `/permadeath revive <name>`, reconnect on the first account, and confirm the
   skills come back.

Server-side messages are prefixed `[PermadeathLock]` in the console log.

## Known limits

- Dedicated servers only. The logic is gated on `isServer()`, so single-player and
  a co-op host are unaffected.
- Identity is the username. A player with a second account is a different person
  as far as this mod is concerned.
- The sweep runs once per in-game minute, so a locked-out player may be in the
  world for up to two of those before their character is killed. They cannot get a
  meaningful head start, but they are not blocked instantly either.
