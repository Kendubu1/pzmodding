# Project Zomboid modding notes

Things that cost real debugging time in this repo, written down so they cost it
once. Build 42, mostly multiplayer. Each entry is *symptom → cause → rule*,
because the symptom is what you will actually be holding when you need it.

---

## 1. Your mod does not run once

This is the big one. It caused a week of wrong diagnoses.

Project Zomboid loads your Lua **once per game context**, and each context is a
**separate Lua world**: separate globals, separate tables, separate event
registrations. They cannot see each other's variables. The only channel between
them is `sendClientCommand` / `sendServerCommand`.

Most people picture two contexts, "server" and "client". There are really five
situations, and **a Host game is two contexts inside one process on one
machine**:

| Situation | `isServer()` | `isClient()` | `isCoopHost()` |
| --- | --- | --- | --- |
| Dedicated server | true | false | false |
| Player connected to one | false | true | false |
| Host game — server side | true | false | **true** |
| Host game — host's own client | false | true | **true** |
| Single player | false | false | false |

Look at the last column. **`isCoopHost()` is true in both halves of a Host
game.** So this, which reads as obviously correct —

```lua
-- "authoritative logic: dedicated servers and co-op hosts"
if not (isServer() or isCoopHost()) then return end
```

— loads your authoritative logic **twice** on a Host game. Two copies of your
state machine, two caches, two timers, both handling the same events, both
writing the same save file. Last writer wins, silently.

Say what you actually mean — *the side that is not a client*:

```lua
if isClient() then return end                      -- never the client half
if not (isServer() or isCoopHost()) then return end
```

and the mirror for player-facing code:

```lua
if isServer() then return end                      -- never the server half
if not (isClient() or isCoopHost()) then return end
```

### Why it hides

Two copies of correct code usually produce a correct-looking result. It only
breaks when the copies **disagree**, and they only disagree when your code
*changes the evidence*.

In Permadeath Lock, copy A saw the player die holding a Fate Token, saved them,
and **burned the token**. Copy B ran a fifth of a second later on the same
death, found no token — because A had just destroyed it — and locked the player
out. Both were behaving perfectly. The player got their skills back *and* an
execution.

Doubling is invisible for pure reads and vicious for anything that mutates:
consuming an item, incrementing a counter, spending currency, writing a file.

### How to catch it in ten seconds

One line at the bottom of each file:

```lua
print("[MyMod] server half loaded. isServer=" .. tostring(isServer())
    .. " isClient=" .. tostring(isClient()) .. " isCoopHost=" .. tostring(isCoopHost()))
```

Boot, then **count**. If a "server half" line appears twice, that is the bug —
no reproduction needed. Ours printed `Loaded 0 death record(s)` twice, eleven
seconds apart, in the very first log we looked at, and it went unread for six
rounds of fixing the wrong things.

---

## 2. Which side owns what

Nearly every hard bug here was the same question. Get it wrong and the failure
is *silence*, not an error.

| Thing | Owner in B42 | What going the wrong way looks like |
| --- | --- | --- |
| Inventory | **Server** | Client adds an item, reports success; the server never sees it, so any server-side check finds nothing |
| Death | **Server** | Client kills its own player; the server thinks they are alive, the death is never recorded, admin tools show them fine |
| Perk levels | Server, synced | A server-side read of a *just-spawned* remote player can disagree with the client |
| UI, notices, input | **Client** | Nothing happens at all |

Ask: *"if I do this on the wrong side, what silently doesn't happen?"* That is
usually the bug.

Vanilla is the reference implementation. `/additem` adds server-side and works,
including for server-side checks afterwards — so do what `/additem` does.

---

## 3. Log what happened, not what you attempted

A restore in this repo set perk levels by adding XP. The call was accepted, no
error was raised, and **the level never moved**. The log said:

```
restore Woodwork -> 4 (xp)      <- "I called AddXP", not "Woodwork is now 4"
Restored Willy Guggenheim (10 skills)
```

so it read as a complete success for several releases, while the next snapshot a
minute later found three of the ten. The game's own log recorded no level change
at all, which would have settled it immediately had anyone compared the two.

Engine calls in PZ frequently **accept a write and do nothing** — wrong context,
wrong ownership, not-yet-synced object, an API that means something subtler than
its name. They rarely throw.

So: **write, read it back, and log the reading.** One extra line per operation,
and a whole class of ghost bug stops existing:

```lua
player:setPerkLevelDebug(perkType, level)
if (player:getPerkLevel(perkType) or 0) >= level then return "set" end
-- ...try the next route, and if nothing works, say FAILED in the log
```

Same rule for counts reported to the player. "10 skills restored" should mean
ten levels moved, not ten calls made.

---

## 4. Kahlua is not Lua 5.1

The game runs Kahlua, which is close to Lua 5.1 but not the same.

- **`next` does not exist.** `next(t)` throws. Count in a loop instead. This
  crashed on every restore for a release, and the offline tests never saw it
  because they run on real Lua where `next` is fine.
- **`pcall` is not silent.** A caught error still prints its full stack trace to
  the server log. A `pcall` in a per-item loop will flood the log. Test the
  condition first (`item:IsInventoryContainer()`) rather than catching the
  throw.
- Assume nothing else exotic is present either. `pairs`, `ipairs`, `table.*`,
  `string.*`, `math.*` are fine.

**Make your test harness lie the same way the game does:**

```lua
next = nil   -- at the top of every harness, before loading the mod
```

That turns this whole class of mistake into a failing test instead of a server
log full of stack traces.

---

## 5. Load order is alphabetical

Within a folder, the game loads Lua files in **alphabetical order**.
`MyMod_Server.lua` loads before `MyMod_Store.lua`. So this, at the top of
Server.lua, captures `nil` forever:

```lua
local Store = MyMod.Store   -- Store.lua has not run yet
```

Create shared tables in a file that sorts first, or in the `shared/` folder
which loads before `server/` and `client/`.

And **make your harness load files in the same order the game does.** Ours
loaded Store first, which hid the bug completely.

---

## 6. Timing traps

- **`OnCreatePlayer` fires while the character is still loading into the
  world.** Acting on it at that instant — killing it, applying a dozen perk
  levels — leaves the client with no valid camera target and a **black screen it
  does not recover from**. Wait a few seconds; have the client tell you when it
  has settled.
- **`EveryOneMinute` is one *in-game* minute.** At the default day length that
  is two or three real seconds, not sixty. Any deadline you want in real seconds
  must be measured with `getTimestamp()`, not counted in sweeps.
- **There is no pre-death hook.** You cannot veto a killing blow. Insurance
  that pays out afterwards is the only shape available.
- **There is no server-side "player connected" event and no kick function** in
  server Lua. A client handshake plus a periodic sweep over
  `getOnlinePlayers()` is the substitute.

---

## 7. Text and scripts that fail by showing you the key

If a label renders as its own name — `IGUI_ItemCat_Misc`, `Tooltip_MyItem` —
the game did not find it. Two causes:

- **Translation file names are a fixed set**, and the file name is not the table
  name. `IGUI_EN = { ... }` must live in **`IG_UI_EN.txt`**. A file called
  `IGUI_EN.txt` is never read at all. Check what shipped mods use before
  inventing a name.
- **`DisplayCategory` must be a category the game already knows.** Supplying
  your own label is possible in theory and went wrong twice here. Build 42
  dropped `Misc`; `Junk` is where oddments live and needs nothing from you. A
  right category beats a right-looking one you have to supply.

---

## 8. Build 42 structure and syntax

```
MyMod/
├── common/media/          shared between builds (optional)
├── 41/
│   ├── mod.info           NOTE: inside the version folder
│   └── media/
└── 42/
    ├── mod.info
    └── media/{scripts,lua,textures,...}
```

`mod.info` lives **inside** the version folder, and B42 only loads the folder
matching the running build. Script syntax changed too: `ItemType = base:weapon`
replaces `Type =`, and `craftRecipe` with `inputs`/`outputs` blocks replaces
`recipe`.

---

## 9. How to actually test

**Offline, before launching the game.** Stub the globals and `dofile` the real
mod files. It is far more effective than it sounds, and it is what finally
reproduced the double-load. Worth harnesses for:

- **Gating** — which halves register handlers, one run per situation, with a
  Host game as **two** rows. Asserts each half loads exactly once.
- **Logic** — the state machine, with stubbed `getFileWriter`, `PerkFactory`,
  `getOnlinePlayers`.
- **Geometry**, if you have UI — band positions at several window sizes *and
  several font heights*. See below.
- Always `luac -p` every file. It catches nothing interesting, but it is free.

**Prove the test fails against the old code.** A regression test you have not
seen fail is decoration. Check the previous revision out into a temp directory
and run the new harness against it.

**In game:**

- **Test Host and dedicated as separate platforms.** They are not the same
  thing, and a mod working on one tells you nothing about the other.
- **Know which log you are reading.** On a Host game the two contexts write to
  *different files* — `Zomboid\Logs\*_DebugLog-server.txt` and
  `Zomboid\console.txt`. Ours logged the rescue in one and the lockout in the
  other, so each file alone looked completely sane. **Read both.**
  `Zomboid\Logs\*_PerkLog.txt` is also useful: the game writes level changes and
  deaths there independently of your mod, so it can confirm or refute your
  mod's account of events.
- **Print the version at load and check it before believing any test result.**
  Half the confusing reports in this repo were an old copy still sitting in
  `Zomboid\mods\`.

---

## 10. UI

- **Size every band from the font, never from pixels.**
  `getTextManager():getFontHeight(UIFont.Small)` is the number. The UI Scaling
  setting changes every glyph on screen, so a 20px band holding 28px text bleeds
  into its neighbours. Looked perfect at 1x, unusable at 2x.
- **Build children at their real size.** `ISScrollingListBox` lays out its
  scrollbar when it is *built* and never moves it again. Created 10×10 and
  resized afterwards, its scrollbar ends up a sliver off the left edge and the
  rows do not render until the window is dragged.
- **`ISCollapsableWindow` puts a resize strip along the bottom edge** and a grab
  handle in the corner. Anything flush to the bottom lands underneath them.
- **Resizable windows do not move their children.** Put the geometry in one
  function and call it from both `createChildren` and `onResize`.
- **A full-screen element in the UI manager eats every mouse event behind it**,
  which takes right-click away from the *entire game* — doors, corpses,
  inventory. Make it click-through before it goes on screen, never after.
- **An error thrown while building a context menu takes the whole menu down.**
  Guard the builder. And prefer the *inventory* context menu over the world one
  where you can: a world entry is built for every player on every right-click,
  whether your item is involved or not, so it is the one with the blast radius.
- **Probe Java objects by field, not by `type()`.** `type(x) == "table"` looks
  like a way to tell a Lua wrapper from a game object, and it works right up
  until anything else in the list is also a table — another mod's entry, or a
  test double. `x.getFullType ~= nil` asks the question you actually mean.
