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

Everything the panel can do, chat can do, and the server re-checks the caller's
real access level either way. The one client command that is not an admin action
— the acknowledgement that a token has been added or removed — is not trusted
for anything: the resulting count is re-read server-side, so the worst a forged
one can do is make an admin's panel redraw.

### What the player sees

Three notices, all modal dialogs rather than chat lines — two of them land while
the player is dead and the chat window is not on screen behind the death UI.

| When | Message |
| --- | --- |
| Died with no token | Their fate has been decided; wait and pray for a pardon. |
| Died with a token | The token burned away; they are not locked out. |
| Blocked on spawn | Why this character just died, and that an admin can lift it. |
| Blocked on spawn, `KillOnSpawn` off | The same, then disconnects after 12s. |

The two death-time notices sit *below* the middle of the screen, clear of the
death screen's own scrolling text and above its "continue with a new character"
buttons. The block notice is centred; there is nothing behind it.

The handshake is the polite path and the sweep is the authoritative one. A player
running a modified client that never reports its death is still caught by the
sweep within one in-game minute.

### What happens to a locked-out player

By default (`KillOnSpawn`) their new character is **killed where it stands** and
they stay connected. Every character they make after that dies the same way.

This is deliberate. Being thrown off the server is indistinguishable from a
crash or a bad connection, and it makes the mod much harder to work on: you lose
the console, the chat and the world the instant anything happens. Killed, the
player reads the notice, stays where they are, and sees a rule rather than a
fault.

**The kill is not immediate, and must not be.** It runs four seconds after they
spawn, carried out by their own client:

1. The spawn handshake finds them locked and sends the notice. It does *not*
   kill anything — see **Nothing happens during the spawn handshake** below.
2. Four seconds later, the client tells the server it has settled. The server
   re-reads the death list; a pardon in that window calls the kill off entirely.
3. If the block still stands, the client kills its own character. That side owns
   and simulates it; a kill applied to a remote player from the server is the
   same class of desync that made items pushed into a remote inventory
   unreliable.
4. If a client never goes through with it, the server kills them fifteen real
   seconds after the notice. That deadline is in real seconds, not sweeps —
   a sweep is one *in-game* minute and how long that lasts depends on the
   server's day length.

### Nothing happens during the spawn handshake

`OnCreatePlayer` fires **while the character is still loading into the world**,
and the handshake the client sends from it is the earliest the server hears
about a new character. Acting on the character at that instant leaves the client
with no valid camera target and a **black screen it does not recover from**.

This caught the mod twice. First with the kill. Then, after that was deferred,
with the restore — which is not a small thing either: it hands a character a
dozen perk levels in one go, on a body that is not finished loading. Reported as
"I respawn after using a Fate Token and suddenly die".

So the handshake now only ever *sends*: a notice, or a request for the client to
say when it has settled. Four seconds later the client says so, the server
re-reads the death list, and only then does anything happen — kill, restore, or
nothing at all because an admin stepped in.

The sweep is the backstop for a client that never reports in, and it waits too:
it will only restore someone a *previous* sweep already saw alive. That is not
belt and braces, it is load-bearing — **a sweep is one in-game minute, which at
the default day length is two or three real seconds**, so an unguarded sweep
beat the client's four-second signal nearly every time and put the restore right
back into the moment it was moved out of.

Turn `KillOnSpawn` off for the older behaviour: the player is shown a notice and
their client disconnects itself after twelve seconds, with `EnforceKill` as the
backstop for a modified client that ignores it. Killing is the strongest action
available either way — the game does not expose a kick to server Lua.

An enforcement kill never spends a Fate Token: the player is already on the
list, so the death is not recorded again and nothing is taken from them.

Nothing the client sends is trusted. Death reports are checked against
`player:isDead()`, and admin commands are re-checked against the sender's real
access level on the server.

## Sandbox options

Under **Permadeath Lock** in the sandbox settings:

| Option | Default | Effect |
| --- | --- | --- |
| `Enabled` | on | Suspends the lock when off. The death list is kept. |
| `ExemptAdmins` | on | Admins are never recorded or blocked. Stops you locking yourself out. |
| `KillOnSpawn` | on | Kill a locked-out player's new character on the spot and leave them connected, instead of disconnecting them. |
| `EnforceKill` | on | Only used when `KillOnSpawn` is off: kill locked-out players whose client ignored the disconnect request. |
| `RestoreSkillsOnRevive` | on | Revived players get their old skill levels on their next character. |
| `FateTokenEnabled` | on | Dying with a Fate Token spends it instead of locking you out. |
| `FateTokenConsume` | on | The token is removed from the body when it saves someone. Off = lootable and reusable. |

## Admin commands

Type these in chat as an admin (`/pd` is a shorthand):

```
/permadeath status          is the lock on, and how many are locked out
/permadeath status <user>   everything the mod knows about one player
/permadeath ui              open the admin panel
/permadeath list            show the death list
/permadeath revive <user>   bring a player back, keeping their skills
/permadeath pardon <user>   let a player back in, from scratch
/permadeath give <user>     hand a player a Fate Token
/permadeath take <user>     take a Fate Token back
/permadeath add <user>      lock a player out by hand
/permadeath clear confirm   wipe the whole death list
/permadeath reload          re-read the death list from disk
```

Usernames are matched case-insensitively.

### When nothing seems to be happening

`/permadeath status <user>` answers it in one go: are they online, are they
dead, are they **exempt**, how many Fate Tokens are they carrying, are they on
the death list, are they owed a restore, and which sandbox switches are on.

Reach for it first. Almost every "the mod is broken" report has been one of
those lines. An exempt player's death in particular does nothing at all — not
recorded, no token spent, nothing locked — which from the inside is
indistinguishable from a fault. The server log now says so explicitly when it
happens:

```
[PermadeathLock] Willy died, but is EXEMPT (an admin, with ExemptAdmins on):
not recorded, no Fate Token spent, not locked out.
```

### The admin panel

`/permadeath ui` opens a window over the **whole roster** — everyone online as
well as everyone on the death list. Most of what an admin needs to know is about
people who are not dead, so limiting it to the list made it much less useful
than it looks.

| Column | What it says |
| --- | --- |
| Player | Username. A trailing `*` means they are offline. |
| State | `LOCKED OUT`, `awaiting restore`, `alive`, `alive (exempt)`, `dead, not listed`, `offline` |
| Died | How long ago, for anyone on the list |
| Skills held | How many perk levels are being kept for their next character |
| Tokens | Fate Tokens they are carrying right now |

The window sizes itself to your screen — about two thirds of its width, within
sensible bounds — rather than to a pixel count picked on somebody else's
monitor. It is also freely resizable, and the columns follow when you drag it.

Its bands are laid out from both edges inward: the status line and column titles
down from the title bar, the buttons up from the bottom, and the list takes what
is left between them. Sizing the list first and letting the buttons fall where
that put them is what pushed the bottom row off the frame in 1.4.0, underneath
the resize strip.

One geometry function, `bands()`, answers where everything goes, and both
`createChildren` and `layout` go through it. Children are therefore *built* at
their real size rather than at a placeholder that gets corrected a moment later:
`ISScrollingListBox` positions its scrollbar when it is built and never moves it
again, so a list born 10x10 got a 10px bar at x = -7 — a sliver hanging off the
left edge — and its rows did not appear at all until the window was dragged to a
new size.

Every band's height comes from `getTextManager():getFontHeight(UIFont.Small)`,
never from a pixel count. **The UI Scaling setting changes the size of every
glyph on screen**, so a 20px status band holding 28px text bleeds into the
column titles, which bleed into the first row, while the bottom row of buttons
has its labels clipped by the frame — all three of which happened at 2x.
`tests/test_layout.lua` builds the panel at five text heights and checks that
every band is at least as tall as the text inside it.

Rows sort trouble-first: locked out, then awaiting a restore, then anyone else
listed, then everyone simply playing, alphabetically inside each group. The
roster refreshes itself every few seconds while the window is open, and keeps
your selection across a refresh so a row cannot slide out from under a click.

Select a row and use **Pardon**, **Revive**, **Give token** or **Take token**.
Pardon and Revive on somebody who is not on the death list say so in the panel
rather than sending a command whose only possible answer is "not on the death
list".
**Refresh** re-reads from the server, and **Clear all** wipes the death list
behind a confirmation — it sits alone in the far corner so a misclick on Refresh
cannot land on it.

Two states are worth knowing on sight. **`alive (exempt)`** means the lock can
never apply to that player — they are an admin and `ExemptAdmins` is on, which
is the single most common reason for "the mod isn't working". **`dead, not
listed`** means a corpse the sweep has not recorded yet, or one belonging to
someone an admin has just pardoned.

The client opens the panel itself rather than asking the server to; the server
has no `ui` subcommand to fall through to, and when the client-side handling
went missing in 1.3.0 the symptom was the command silently printing the help
text.

It is only a face on the chat commands. Every button sends the same message the
typed command does, and the server re-checks the sender's access level before
acting, so the panel grants nothing.

### What this deliberately does not do

An earlier version could put a revived player back at their body, clear the
zombies around it, remove the corpse, and restore the dead character's name and
face. It was cut. The pieces worked in isolation but the whole was fragile and
hard to reason about, and permadeath is worth more when the way back is simple
and predictable. What remains is: you die, you are locked out, an admin can
pardon you or revive you.

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

Pardoning someone whose character is *still lying dead in the world* does not
stand that character back up; nothing can. They have to reconnect and make a new
one, and the command says so. Their corpse is left alone by the sweep from then
on, so the pardon is not quietly undone a minute later.

Skills are restored, not overwritten: a level the new character already exceeds is
left alone, and it still counts as restored — they have the level the dead
character had, which is what was promised. Experience part-way through a level is
not carried over. Traits, profession and inventory are **not** restored — traits
are not readable from the Lua API in B42, and inventory would need item
serialisation.

A perk in an old snapshot that the game no longer knows about (a mod removed
since the death, a renamed vanilla perk) is skipped and named in the server log
rather than being dropped in silence.

Levels are set in one call each (`setPerkLevelDebug`) rather than by calling
`LevelPerk` once per level. A dozen perks restored at once is otherwise forty
level-up cascades — XP maths, sound, screen flash, character-screen refresh —
inside a single frame.

The player is told **on screen**, not only in chat. A restore lands seconds
after a death screen and nobody is reading the chat window then: players spent a
Fate Token, got their life and their skills back, and saw nothing at all.

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

It shows in the inventory under **Junk**, which is a stock Build 42 category and
where the game files oddments.

That is the third attempt, and the lesson is worth keeping: **a category the
game does not already have a name for renders as its own translation key.**
First it was `Misc`, which Build 42 no longer has, and players saw
`IGUI_ItemCat_Misc`. Then it was our own `Fate` with the label shipped in
`IG_UI_EN.txt` — the correct file name, `IGUI_EN.txt` is never read — and it
*still* came out as `IGUI_ItemCat_Fate`. `Junk` needs nothing from us: Junk Jet
uses it, ships no label for it, and reads correctly in game. A right category
beats a right-looking one we have to supply ourselves.

### Handing them out

Nothing spawns them by default; that is a deliberate balance decision left to you.

From the admin panel, select a player and press **Give token** or **Take token**.
From chat, `/permadeath give <user>` and `/permadeath take <user>` do the same.
Vanilla's `/additem <username> Base.FateToken` also works.

The target has to be **online**: a token is a real item and someone has to be
there to hold it.

The item is added and removed **server-side**, the same as vanilla's `/additem`.
1.5.0 relayed it to the target's client instead, reasoning that a player's
inventory belongs to their own machine. In Build 42 it does not, and the
consequence was not cosmetic: the client added the item and reported success,
the server never saw it, and **the death check reads the server's inventory** —
so a token handed out through the panel saved nobody. Players died carrying
three of them and were locked out anyway. The `0` the panel reported straight
afterwards was the visible half of the same fault.

Granting also refreshes the cache the death check consults, so someone handed a
token and killed ten seconds later is saved by it, and someone whose last token
was just taken is not.

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

0. Confirm the console says `[PermadeathLock] Server module 1.4.0 loaded.` before
   anything else. Testing an older copy that is still sitting in `Zomboid/mods/`
   looks exactly like a fix not working.
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
7. For the pardon path: die, then `/permadeath pardon <name>` while your corpse is
   still in the world. Wait two in-game minutes, run `/permadeath list`, and
   confirm you are **not** back on it. Then make a new character and confirm you
   are let in.
8. For the panel: `/permadeath ui`, and confirm you appear on it while alive.
   Select yourself, press **Give token**, and watch the Tokens column go to 1
   without you touching Refresh. **Take token** should put it back to 0.

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
