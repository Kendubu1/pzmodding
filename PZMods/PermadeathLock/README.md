# Fate Token — Multiplayer Permadeath

Permadeath for Project Zomboid **Build 42** multiplayer — dedicated servers and
co-op Host games alike. When a player dies they go on a death list and cannot
come back with a new character. Admins can pardon
someone (fresh start) or revive them (new character, old skills), and players
carrying a **Fate Token** buy back one death without needing an admin at all.

**The Workshop name and the internal id are deliberately different.** The
listing is *Fate Token*, because the token is the thing that makes this mod
different from every other permadeath mod and a title should sell what you get
rather than what you lose. The id stays `PermadeathLock`, and so do
`PL.MODULE`, `SandboxVars.PermadeathLock`, the `IGUI_PermadeathLock_*` keys, the
chat command and the death file: none of that is visible to a player, and
renaming it would break the sandbox settings of everyone already running it in
exchange for nothing.

## Publishing

Two different files describe this mod, and they are read by different things:

| File | Feeds | When it takes effect |
| --- | --- | --- |
| `42/mod.info` | The in-game **Select Mods** panel — name, description, author, icon, version | Read from the mod folder at game start. Edit, restart, done. Steam is not involved. |
| `workshop.txt` + `preview.png` | The **Steam Workshop page** — title, description, tags, thumbnail | Read by the in-game Workshop uploader when you publish or re-publish. |

So the mod list updates the moment you copy the folder into `Zomboid/mods/` and
restart; the Workshop page updates when you next run the uploader. Nothing in
`mod.info` reaches Steam, and nothing in `workshop.txt` reaches the mod list.

`workshop.txt` starts with **no `id=` line**: the uploader assigns one on first
upload and writes it back. Keep that line once it appears — losing it publishes
a second, separate Workshop item instead of updating the first. It is also what
fills the **WorkshopID** row in the mod panel, which stays blank while the mod
is only a local folder.

`author` is written twice, as both `author=` and `authors=`, since builds differ
on which they read. `url=` fills the **Homepage** row.

| File | Size | What it is for |
| --- | --- | --- |
| `preview.png` | 512×512 | The Workshop thumbnail. Carries the name, because the grid renders it small. |
| `42/poster.png` | 512×512 | Shown larger in the in-game mod panel. |
| `42/icon.png` | 128×128 | The mod list. The token alone — it still reads at 32px, which is what that list gives it. |

Each slot gets its own cut rather than one image reused three times.

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
├── common/media/lua/shared/Translate/EN/    every language file
└── 42/
    ├── mod.info
    ├── poster.png
    └── media/
        ├── sandbox-options.txt
        ├── scripts/          item script for the Fate Token
        ├── textures/         its inventory icon
        └── lua/{shared,server,client}/
```

**The translations are shipped three times** — at the mod root, in `common/`,
and in `42/` — as identical files:

```
PermadeathLock/media/lua/shared/Translate/EN/
PermadeathLock/common/media/lua/shared/Translate/EN/
PermadeathLock/42/media/lua/shared/Translate/EN/
```

Which root the game reads them from is **not** the same question as which root
it loads Lua from: the Lua VM and the Java translator walk different paths, and
a multi-version mod (`mod.info` inside `42/`, with a `common/`) puts three
plausible answers on the table. Getting it wrong is silent — the game renders
the key instead of the sentence and logs nothing — which cost this mod a raw
`Tooltip_FateToken` on the item and a settings page full of
`Sandbox_PermadeathLock_...`. A few kilobytes of duplicated text is cheaper
than being wrong; `test_translations.lua` asserts all three stay byte-identical.

Once one is confirmed working in game, the other two can go.

Two rules that are easy to break and invisible until a player sees a raw key:

- An `IGUI_EN = {...}` table must be in a file named **`IG_UI_EN.txt`**. A file
  called `IGUI_EN.txt` is never read.
- A key containing a dot must be **bracketed**:
  `["ItemName_Base.FateToken"] = "Fate Token"`. Written bare it is not valid
  table syntax, and it takes the whole file down with it — every other string in
  that file falls back to its key too.

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

A Host game is not a dedicated server, and — this is the part that cost the most
— **it runs two Lua states in one process**: the in-process server, and the
host's own client. `isCoopHost()` is true in *both* of them.

So gating a "server only" half on `isCoopHost()` alone loads it **twice**: two
death lists, two sweeps, two Fate Token caches, both writing the same file. What
that looked like in play was a single death judged twice, a fifth of a second
apart, reaching opposite conclusions:

```
death of Willy: token on body=true,  ... not locked out. Token consumed.
death of Willy: token on body=false, ... and is locked out. No Fate Token.
```

The first state found the Fate Token and spent it. The second ran after it,
found nothing left, and locked the player out — who was then killed by the
enforcement seconds after respawning. The rescue is what killed them.

The gate therefore excludes the state that is a client, and the client half
excludes the state that is the server. Exactly one of each, on every mode. The
boot line prints `isServer` / `isClient` / `isCoopHost` so a double load is
visible at a glance: **if `Server module … loaded` appears twice, that is the
fault, not noise.**

**If you are hosting, you are almost certainly an admin, and `ExemptAdmins`
defaults to on** - your deaths will be ignored until you turn it off in the
sandbox settings, and an ignored death looks exactly like nothing happening.

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

All of them are centred, wrapped to fit, and sized from the font. Two things
have to be right for that and both were wrong: the text is wrapped **here**,
because handed a paragraph on one line the dialog runs it out sideways rather
than breaking it; and the centring uses `ISModalDialog.CalcSize`, because the
dialog resizes itself to fit its text when it is built — centring on the size
passed in left a box that then grew wider hanging off to the right.

The death-time notices previously sat below centre, clear of the death screen's
own scrolling text. They are centred again by request.

**Every one of these sentences is also compiled into the mod**, and used
whenever `getText` hands back the key instead of a translation. That happens
when the game has not read the language files, and it put
`IGUI_PermadeathLock_TokenSpent` on players' screens at the exact instant they
died, more than once. The language files still win when they load; this is only
the floor. There is no equivalent floor for the item's **category** — a script
cannot fall back — which is why that uses a stock category rather than one of
ours.

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
3. If the block still stands, **the server** kills the character.
4. If a client never reports in, the server kills them anyway fifteen real
   seconds after the notice. That deadline is in real seconds, not sweeps —
   a sweep is one *in-game* minute and how long that lasts depends on the
   server's day length.

1.7.0 had step 3 the other way round: the server asked the client to kill
itself, to avoid a remote-kill desync. That produced the desync in the other
direction — the client died, **the server went on believing the character was
alive**, the admin panel showed them alive, and the death was never recorded.
There is one authority for whether somebody is dead and it is the server.

**Every kill the lock performs says so**, on screen and in chat:

> Permadeath Lock: your character has been killed — you are on the death list
> and made a new character. An admin can pardon you, or revive you and give back
> what you learned.

and in the log as `KILLED <name> - <why>`. If you die and see no such message,
this mod did not kill you. That is the point of it: "I just suddenly died" was
impossible to attribute to anything.

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
| `FateBinding` | on | Right-clicking a token offers "Bind your fate here", and dying with that token returns you there. |

## Admin commands

Type these in chat as an admin (`/pd` is a shorthand):

```
/fate status          is the lock on, and how many are locked out
/fate status <user>   everything the mod knows about one player
/fate ui              open the admin panel
/fate list            show the death list
/fate binds           every place a Fate Token is bound to
/fate revive <user>   bring a player back, keeping their skills
/fate pardon <user>   let a player back in, from scratch
/fate give <user>     hand a player a Fate Token
/fate take <user>     take a Fate Token back
/fate add <user>      lock a player out by hand
/fate clear confirm   wipe the whole death list
/fate reload          re-read the death list from disk
```

`/permadeath` and `/pd` still work. Every server running this before the rename
has the old word in its admin notes, and an alias costs one line.

Usernames are matched case-insensitively, may contain **spaces**, and may be
quoted:

```
/fate pardon Willy Guggenheim
/fate pardon "Willy Guggenheim"
```

Both work. Until 1.9.1 neither did: the parser took only the next word, so the
first addressed a player called `Willy` and the second one called `"Willy`. Each
answered "X is not on the death list", which reads as the death list being wrong
rather than the name never having arrived.

### Reading a status dump

`awaiting restore=true` means the mod owes your **next** character the skills of
the one that died — it is a promise, not a block. `locked=true` is the one that
stops you playing. A token save sets `locked=false, awaiting restore=true`: you
are free to make a new character, and it collects the old one's skills.

### When nothing seems to be happening

`/fate status <user>` answers it in one go: are they online, are they
dead, are they **exempt**, how many Fate Tokens are they carrying, are they on
the death list, are they owed a restore, **all seven sandbox switches**, and
which Lua state answered.

That last line matters on a co-op Host — see *Where it runs*. Getting this
reply **twice** means the server half is loaded twice, which is a fault in
itself.

Reach for it first: it answers most questions on its own. An exempt player's
death in particular does nothing at all — not recorded, no token spent, nothing
locked — which from the inside is indistinguishable from a fault. The server log now says so explicitly when it
happens:

```
[PermadeathLock] Willy died, but is EXEMPT (an admin, with ExemptAdmins on):
not recorded, no Fate Token spent, not locked out.
```

### The admin panel

`/fate ui` opens a window over the **whole roster** — everyone online as
well as everyone on the death list. Most of what an admin needs to know is about
people who are not dead, so limiting it to the list made it much less useful
than it looks.

| Column | What it says |
| --- | --- |
| Player | Username. A trailing `*` means they are offline. |
| State | `LOCKED OUT`, `awaiting restore`, `alive`, `alive (exempt)`, `dead, not listed`, `offline` |
| Died | How long ago, for anyone on the list |
| Skills held | How many perk levels are being kept for their next character |
| Tokens | Fate Tokens they are carrying right now, and how many are bound |
| Bind | Where a token would put them: `1200,1300`, with `+2` when other bound tokens are behind it, and `-> 1200,1300` when a spent token is already owed them |

The window sizes itself to your screen — about two thirds of its width, within
sensible bounds — rather than to a pixel count picked on somebody else's
monitor. It is freely resizable in **both** directions, down to about the width
of a username.

**The columns give themselves up as you narrow it** rather than colliding. Each
one is measured from the longest thing it realistically has to show — `awaiting
restore`, `under an hour ago`, `-> 12000,13000` — and gets at least that much
room; whatever is spare is then shared out, so a wide panel spreads instead of
bunching against the left edge. When there is not enough for everything, columns
are dropped one at a time in this order:

`Skills held` → `Died` → `Bind` → `Tokens` → `State`

`Player` is never dropped, and a column only ever disappears as the window
shrinks — widen it and everything comes straight back. Measuring beats setting
the columns at fractions of the window width, which only holds while the window
is wide: 15% of a small number is not enough room for "awaiting restore" however
you slice it.

Its bands are laid out from both edges inward: the status line and column titles
down from the title bar, the buttons up from the bottom, and the list takes what
is left between them. Sizing the list first and letting the buttons fall where
that leaves them puts the bottom row under the resize strip, which
`ISCollapsableWindow` lays along the whole bottom edge.

One geometry function, `bands()`, answers where everything goes, and both
`createChildren` and `layout` go through it. Children are therefore *built* at
their real size rather than at a placeholder that gets corrected a moment later:
`ISScrollingListBox` positions its scrollbar when it is built and never moves it
again, so a list built at 10x10 gets a 10px bar at x = -7 — a sliver hanging off
the left edge — and shows no rows at all until the window is dragged to a
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

The client opens the panel itself rather than asking the server to. The server
has no `ui` subcommand, so without the client-side interception the word falls
through to the help text and no panel appears.

It is only a face on the chat commands. Every button sends the same message the
typed command does, and the server re-checks the sender's access level before
acting, so the panel grants nothing.

Whatever the server says back appears in the panel's status line as well as in
chat. It has to: every refusal the mod can give — not online, no token to take,
not on the death list — is written to chat, and **the panel sits on top of the
chat window**. A refused action was indistinguishable from a button that does
nothing, and was reported as exactly that.

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
- Target **online but dead** → same, but they have to respawn first; the corpse
  stays a corpse. The command tells you so.
- Target **online and alive** (they already made a new character) → skills are
  restored immediately and they are healed to full.

`pardon` just removes them from the list — they come back with nothing.

Pardoning someone whose character is *still lying dead in the world* does not
stand that character back up; nothing can. They respawn as normal, and the
command says so. Their corpse is left alone by the sweep from then
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

Levels are set with `setPerkLevelDebug`, falling back to `LevelPerk` once per
level — and **each perk is then read back to check the level actually moved**.

That check is not paranoia. A version of this restored by adding XP
(`AddXPNoMultiplier`), which is how the game levels a character normally. The
call was accepted, no error was raised, and **the level never moved**. Ten perks
were logged as applied, "Restored (10 skills)" was reported to the player, and
the next death's snapshot a minute later found three. The game's own PerkLog
recorded no level change at all.

The logging was as much at fault as the API: it printed what was *attempted*,
not what *happened*. A perk that resists every route now reads `FAILED, still at
0` in the log, is not counted, and is listed as missing.

**Fitness and Strength are restored last**, and each perk is logged as it lands:

```
[PermadeathLock] restoring Willy...
[PermadeathLock]   restore Aiming -> 3 (xp)
[PermadeathLock]   restore Woodwork -> 6 (xp)
[PermadeathLock]   restore Fitness -> 5 (xp)
[PermadeathLock] ...restore of Willy finished.
```

Those two are what the body's condition is computed from, so they are the
likeliest to hurt a character that has only just spawned. Doing them last means
everything else has already landed, and if the restore takes the character down
part way through, **the last line in the log names the perk it stopped at**. The
character is healed to full immediately afterwards for the same reason.

**A restore that kills the character does not spend the rescue** — the player
has not had what they were owed. But the perk that did the killing is dropped
from their snapshot first, and that part matters: keeping it hands the same perk
to their next character, and the one after that, so they die on every spawn
forever. Losing one skill is by far the cheaper failure. Each retry drops one
more, so it converges.

When a restore fails with nothing to blame — it raised rather than killing
anyone — the rescue is kept and retried, and abandoned after three attempts. At
that point something is wrong that dropping perks will not converge on, and a
player who dies on every spawn is worse off than one who lost their skills.
Either way they are told on screen that they are **not** locked out.

If a restore is killing characters on your server, `RestoreSkillsOnRevive` off
is the switch that isolates it: Fate Tokens still save people, they just come
back without their old skills.

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

### Binding a token to a place

Right-click a Fate Token → **Bind your fate here**. Die carrying *that* token
and your next character wakes at that spot instead of wherever the game would
have put them.

**The binding lives on the token, not on the player.** Each one carries its own
coordinate, so you can hold several bound to different places, an unbound one is
simply a token with nothing written on it, and a binding travels with the item —
drop it, trade it, leave it in a crate, and it goes too. Binding again picks an
*unbound* token in preference, so you end up with two bound tokens rather than
moving the one you already placed. The admin panel shows it as `3 (1 bound)`.

Only a token pays for this. An admin **revive** has no token, and so nothing to
read: it never moves anyone.

**The teleport waits, and then checks it took.** Moving the character the moment
the restore finishes does not stick: the game is still placing the freshly
spawned character and puts them back a second later, which from the player's
side looks like appearing at the bound spot for a blink and then being dragged
away. So the move waits about six seconds, and every sweep afterwards checks
whether they are actually there — retrying up to four times if the game has
undone it. Only once they are confirmed at the spot is it announced, and once
confirmed it is finished with them: nobody gets teleported again five minutes
later for having walked off.

**The move itself is done by your own client, not the server.** In Build 42
multiplayer a player's *position* is owned by their own machine: the server's
copy is a shadow updated from movement packets, so a server-side move is
overwritten by the next packet the client sends a fraction of a second later.
The server asks, the client places the character — setting the position, the
"last" position the movement code interpolates from, and the square it is
standing on, because setting only the first makes it snap back on the next step
— and then reports where it ended up. That report is what confirms arrival: the
server's own lagging copy of the position is not allowed to fail a teleport the
player can see worked.

If the bound spot cannot be reached the attempts run out, you are left where the
game put you and told so. Nobody gets dropped inside a wall. Three things can
cause that, and the server log names which:

An **unloaded destination chunk is not a failure** and is not checked for. It is
the normal case for anywhere you are not already standing, and the game handles
being moved into one by streaming the world in around you — a chunk far from
your spawn would never load until somebody stood there, so refusing to move
would make the teleport work only for places you were already near.

What the log does say, per attempt: what the client reported, where the server
thinks the character is, and — as `server-side raised: …` — any error thrown by
`teleportTo`, which is logged rather than swallowed. A throw and a move that
quietly does not hold are different problems and should not arrive looking the
same.

### Finding a bound token that has been lost

Every bind is written down twice: on the item, and in a registry the server
keeps in `PermadeathLock_binds.txt`. `/fate binds` lists all of them.

```
3 bound Fate Token(s):
 - #1 at 1200,1300,0 (bound by Willy, 2 hours ago, held by Willy)
 - #2 at 10800,9400,0 (bound by Rae, 3 days ago, not seen)
```

The registry exists for the case the item copy cannot cover. A token dropped in
a bag, left in a crate, or in the pocket of somebody who has not logged in for a
month is unreachable — **the game keeps no index of items**, and a search would
have to walk the loaded squares, which is the corner of the map somebody happens
to be standing in. What can always be recovered is the *coordinate*, which is
the thing people actually want, and an admin can put someone back there by hand.

So the list is deliberately honest about what it does not know. `held by X` is
only ever said for a player who is online, because that is the only inventory
the server can read; an offline player's pocket, a crate and the floor are
indistinguishable from here and are all reported as `not seen`. Spending a token
retires its entry — that place has been used, and leaving it on a list of
recoverable coordinates would be a lie.

The entry lives on the **item**, not on the ground. A world context-menu entry is
offered to every player on every right-click whether they own a token or not,
and an error raised while the game builds a context menu takes the *whole* menu
down — doors, corpses, inventory, everything. That happened to a neighbouring
mod in this repo. On the item it only exists where it means something, and the
builder is wrapped besides.

### Coming back as yourself — backlogged

Restoring the dead character's face was built and then taken out again. It
half-worked: the face came back and then reverted at the first tick of damage,
because the game re-derives the model from the descriptor. Writing both the live
visual and the descriptor fixed that one case and it still was not reliable.

The code is gone rather than left switched off. It can come back when there is a
reason to work through it properly; a half-working cosmetic is worse than none.

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
From chat, `/fate give <user>` and `/fate take <user>` do the same.
Vanilla's `/additem <username> Base.FateToken` also works.

The target has to be **online**: a token is a real item and someone has to be
there to hold it.

Adding to the server's copy of the container is only **half** of it: the item
then exists here, the panel counts it, and the player's own inventory never
shows it. `sendAddItemToContainer` (and `sendRemoveItemFromContainer`, and the
same on the token the lock spends at death) is the broadcast that makes it real
for them. That was reported as "the UI says they have one and they don't".

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

## Putting tokens in the world

Off by default. A Fate Token undoes the only rule this mod has, so whether the
world hands them out is deliberately the server's decision and not the mod's —
out of the box, the only Fate Token that exists is one an admin gave somebody.

Turn on **Fate Tokens spawn in loot** and they turn up in cash registers, and
more often in banks and vaults. Two settings shape it: how rare, and how much
better a bank is than a corner shop.

### What the rarity numbers actually mean

The number attached to an item in a container's loot list is a **relative
weight inside that list**, not a percentage. Its real odds depend on what else
is in the list and how many draws the container makes, so the same weight is
rarer in a well-stocked container than a sparse one. As a feel for the scale
vanilla uses:

| Weight | Roughly |
| --- | --- |
| 10–100 | Filler. Every other container. |
| 1–4 | Ordinary loot. You will find some. |
| 0.1–0.5 | Rare. The things you remember finding. |
| under 0.1 | Most playthroughs will never see one. |

The four rarity settings sit deliberately at the bottom of that:

| Setting | Register weight | With the default 4× bank bonus |
| --- | --- | --- |
| Almost never | 0.05 | 0.2 |
| **Very rare** (default) | 0.10 | 0.4 |
| Rare | 0.30 | 1.2 |
| Uncommon | 1.00 | 4.0 |

The world's own **Loot Rarity** sandbox setting scales all of it again on top,
so a server already running Abundant loot gets more of these too.

### How they are attached

Containers are matched **by name pattern**, not by a hard-coded list of keys:
anything whose distribution name contains `register` or `till` gets the plain
weight, and anything containing `bank` or `vault` gets the bonus. That catches
the shop till, the gas station till and the bank counter alike, and keeps
working when the game reshuffles its tables between builds.

A hard-coded key that no longer exists fails **silently** — the item simply
never spawns and nothing says why, which is indistinguishable from bad luck. So
the boot log names every list it touched and the weight it used:

```
[PermadeathLock] Fate Tokens added to loot: very rare. Weight 0.1 in 6
register-like list(s), 0.4 in 3 bank-like list(s).
[PermadeathLock] loot lists: CashRegister@0.1, BankVault@0.4, ...
```

and if it matches nothing at all, that is a `WARNING`, not a shrug. `/fate
status` repeats the summary in game, because an admin standing in an empty shop
should not have to go and read a boot log.

## The death list

Stored at `Zomboid/Lua/PermadeathLock_deaths.txt`, one tab-separated record per
line:

```
username <tab> steamID <tab> timestamp <tab> reason <tab> skills <tab> locked <tab> pendingRestore
```

It is plain text on purpose: you can edit it with the server down and then run
`/fate reload`, or just add a bare username on its own line to lock someone
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
4. Respawn — you should get the notice, and the new character should die within
   a few seconds.
5. As an admin (second account, or turn `ExemptAdmins` back on), run
   `/fate revive <name>`, respawn on the first account, and confirm the
   skills come back.
6. For the Fate Token: `/additem <name> Base.FateToken`, die again, and check the
   console says `died holding a Fate Token; not locked out`. You should be able to
   respawn straight away, with your skills.
7. For the pardon path: die, then `/fate pardon <name>` while your corpse is
   still in the world. Wait two in-game minutes, run `/fate list`, and
   confirm you are **not** back on it. Then make a new character and confirm you
   are let in.
8. For the panel: `/fate ui`, and confirm you appear on it while alive.
   Select yourself, press **Give token**, and watch the Tokens column go to 1
   without you touching Refresh. **Take token** should put it back to 0.

Server-side messages are prefixed `[PermadeathLock]` in the console log.

## Before publishing

Three things this repo cannot verify on its own, because they need the game:

1. **The item's inventory category.** `DisplayCategory = Junk` is a stock Build
   42 category and needs no label from us. Look at a Fate Token in an inventory
   and confirm the category reads as a word rather than `IGUI_ItemCat_...`.
2. **The sandbox page.** Open a server's *Edit Settings* → Sandbox and confirm
   the options read as sentences rather than `Sandbox_PermadeathLock_...` keys.
3. **One boot, on a co-op Host.** Count the `Server module ... loaded` lines. Two
   means the gating has regressed and every mutation is happening twice — see
   `MODDING-NOTES.md` section 1 for why that is the worst bug in this repo's
   history.
4. **The loot log.** Switch loot on, boot, and read the `Fate Tokens added to
   loot` line. It names every container list it matched. If it says it matched
   none, the patterns need adjusting to whatever this build calls its tables.

## Known limits

- Dedicated servers and **co-op Host games**. Single player is deliberately left
  alone: the mod loads and does nothing.
- Identity is the username. A player with a second account is a different person
  as far as this mod is concerned.
- The sweep runs once per in-game minute, so a locked-out player may be in the
  world for up to two of those before their character is killed. They cannot get a
  meaningful head start, but they are not blocked instantly either.
- The bind registry records **coordinates, not items**. Where a lost token
  points can always be recovered; where the token itself physically is cannot,
  because the game keeps no index of items in the world.

## Tests

Offline logic checks live in `tests/`. See `tests/README.md`.
