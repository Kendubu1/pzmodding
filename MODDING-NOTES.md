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
| Player position | **That player's client** | Server moves them, reads back the new coordinate, believes it worked; the client's next movement packet puts them back |
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

## 5b. Build 42 mod folder layout

Build 42 replaced the flat `ModName/media/` layout with **version folders plus a
shared one**:

```
ModName/
    common/
        media/          <- everything identical on both builds
    42/
        mod.info        <- the manifest lives IN the version folder
        poster.png
        media/          <- build-specific content
    41/
        mod.info
        media/
```

Loading is ordered: `common/` first, then the version folder closest to the
running build, whose files **overwrite** the common ones. So both
`common/media/...` and `42/media/...` are real media roots, and a path only
present in `common/` is still found.

Translations therefore go at either of:

```
ModName/common/media/lua/shared/Translate/EN/
ModName/42/media/lua/shared/Translate/EN/
```

A guide-recommended migration is to **copy** (not move) the old `media/`,
`mod.info` and `poster.png` into `42/`, which leaves the flat layout in place
for Build 41 players. A B42-only mod does not need the root copy.

Do not reason about B42 layout from a Build 41 mod sitting next to yours. They
are different shapes, and the older one being correct says nothing.

### The upload folder is a different shape again

What the game loads from `Zomboid/mods/` is NOT what you hand the Workshop
uploader. The uploader refuses anything without a `Contents/` wrapper - *"All
the files and folders to upload must be inside a folder called Contents/"* - so
the upload root holds the packaging and the mod sits two levels down:

```
UploadRoot/
    workshop.txt
    preview.png          <- 256x256, and the uploader rejects any other size
    Contents/
        mods/
            ModName/     <- this is what goes in Zomboid/mods/
                common/
                42/
```

Only `preview.png` is size-locked. `poster.png` and `icon.png` live inside the
mod and are whatever suits them.

Sources: [PZ B42 mod template](https://github.com/LabX1/ProjectZomboid-Build42-ModTemplate),
[updating a mod for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3391657438).

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
- **A player's position is owned by their own client.** Add it to the ownership
  table in §2: a server-side `teleportTo` on a remote player moves the server's
  shadow and is then overwritten by that client's next movement packet. The
  server reads back the new coordinate and believes itself; the player sees the
  destination for a blink. Send the move to the owning client and let it report
  back — and set the "last" position and the current square too, not just x/y/z,
  or the character snaps back on its first step.
- **The game keeps placing a spawning character after you have moved it.**
  `teleportTo` during or just after the spawn handshake appears to work — the
  character *is* at the new coordinate when you read it back on the same tick —
  and then the game's own placement lands a second later and drags them back.
  The player sees the destination for a blink and then somewhere else, which
  reads as the teleport being ignored. Wait several real seconds, teleport, and
  then **check again on a later tick** that they are still there; retry a
  bounded number of times before giving up. A read-back on the same tick proves
  nothing about where they end up.
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

## 7b. Build 42.15 changed the translation file format

The symptom: **every** string your mod supplies renders as its own key —
`Tooltip_FateToken` in an inventory, `Sandbox_MyMod_Enabled` on the settings
page — while the base game's own text is fine. Nothing is logged.

The cause: **42.15 replaced the Lua-table `.txt` with a flat JSON object.** Same
folder, and the filename drops the language suffix:

| Build | File | Contents |
| --- | --- | --- |
| ≤ 42.14 | `Translate/EN/Sandbox_EN.txt` | `Sandbox_EN = { Key = "text", }` |
| ≥ 42.15 | `Translate/EN/Sandbox.json` | `{ "Key": "text" }` |

A build reads its own format and **ignores the other entirely**. Ship both,
generated from one source so they cannot drift — hand-maintaining two copies of
the same strings is how half of them end up stale.

Two more things Build 42 does differently, from the same evidence:

- **Enum sandbox values are keyed `Sandbox_<translation>_option<N>`**, and there
  is no `valueTranslation` line in `sandbox-options.txt` at all. The Build 41
  scheme — a separate `valueTranslation` key plus a bare number suffix — leaves
  the dropdown showing raw keys.
- **`versionMin=42.14.0`** in `mod.info` is what fills the mod panel's
  `ZomboidVersion` row, and version folders can be *minor*-versioned
  (`42.14/`, `42.15/`) so one upload can serve both formats.

How this was found, which is the transferable part: read a **recently updated**
Build 42 mod's source. One that ships `42.14/` and `42.15/` folders side by side
shows the change as a diff between its own two copies. Guides and wikis lagged
it; a mod that had to survive the update did not.

Source: [phobos-dthorga/mod-pz-chemistry-pathways](https://github.com/phobos-dthorga/mod-pz-chemistry-pathways)

---

## 7c. An item with no world model is invisible on the ground

Symptom: an older item is **invisible** where it is dropped. No error, no
warning, nothing in the log.

Cause: a dropped item is drawn as a **3D model**, and an item with no model to
draw draws nothing. `Icon` alone was enough back when the ground showed a 2D
sprite, and an item written then still parses perfectly today.

(Which build made that switch is not pinned down here — 3D ground items landed
during Build 41's run, not at 42. The rule holds either way; the version does
not matter to it.)

Three separate fields, and they are not interchangeable:

| Field | Where it shows |
| --- | --- |
| `WeaponSprite` | In the character's hands (weapons only) |
| `StaticModel` | Attached to the body, and in some UI |
| `WorldStaticModel` | **On the ground.** The one a B41 conversion forgets. |

A weapon carrying only `WeaponSprite` looks right while equipped and vanishes
the moment it is dropped. Check every item that has a mesh: a shipping Build 42
mod declares `WorldStaticModel` on 119 of its items and `StaticModel` on 55.

When a model goes missing, suspect the **item that references it** before the
model itself.

Source: [phobos-dthorga/mod-pz-chemistry-pathways](https://github.com/phobos-dthorga/mod-pz-chemistry-pathways)
(confirmed Build 42: `ItemType = base:*`, `versionMin=42.14.0`, `42.14/` and
`42.15/` folders).

**How this entry was nearly got wrong**, which is the part worth keeping: the
first reference read for it declared `Type = Clothing`, had no version folders
and no `versionMin` — a Build 41 mod that merely happened to sit inside a
`Contents/` wrapper. Section 5b already says not to reason about Build 42 from
a Build 41 mod, and it is easy to do anyway, because a repo gives no banner.
**Check `ItemType = base:` before trusting anything a mod appears to prove.**

---

## 7d. Build 42 craftRecipe: what a Build 41 conversion gets wrong

Converting `recipe` to `craftRecipe` is mostly mechanical, and three things in
the middle of it are not. All three fail quietly - the recipe either never
appears or asks for something absurd - and all three were confirmed by reading
a shipping mod with ~300 recipes rather than from a guide.

- **`NeedToBeLearn` keeps Build 41's capitalisation.** The rest of the block is
  lowercase (`time`, `category`, `inputs`, `timedAction`), which makes
  `needToBeLearn` look right. It is a script key like any other and a
  mismatched one is simply not read.
- **A drainable is one item, kept, flagged.** Build 41 counted units:
  `BlowTorch=90`. Build 42 is `item 1 [Base.BlowTorch] mode:keep
  flags[MayDegrade]` and the game does the draining. Carrying the 41 number
  across asks for ninety blowtorches and destroys them.
- **`category` is free-form.** A mod names whatever category it likes and it
  parses; there is no fixed list to violate. Only where the recipe lands in the
  crafting UI is at stake.

**`OnCreate` survives, with the same signature.** `OnCreate = MyTable.myFunc`
and `function MyTable.myFunc(items, result, player)` work in Build 42 exactly as
in Build 41 - so a callback can live in `common/` and serve both. Worth knowing
because it is easy to assume it is gone and silently drop the behaviour, which
is what happened here: the Junk Jet's auto-load lived in `41/`, and Build 42
players lost it without a word.

---

## 7e. A vanilla stack trace can still be your bug

Symptom, repeating several times a second while a modded gun is in hand:

```
attempted index: getItemKey of non-table: null
  Lua(Vanilla).hasBullets(ISFirearmRadialMenu.lua:136)
  Lua(Vanilla).BeginAutomaticReload(ISReloadWeaponAction.lua:362)
```

Every frame of that stack is `Lua(Vanilla)`. Nothing in it names the mod, which
makes it read as a game bug. It is not: the game asked the weapon for its ammo
type, looked the item up, got nothing, and called a method on nothing.

Cause: `AmmoType = MyAmmo` written **unqualified**. Vanilla always writes
`AmmoType = Base.223Bullets` — module included — and its firearm code resolves
that string against the item registry with no fallback.

The general rule, which is worth more than the specific fix: **when the engine
crashes on a null lookup, find the string you handed it.** A stack that is all
vanilla means the game trusted something you wrote.

And when comparing such a string in your own Lua, accept both spellings. A
comparison against exactly one form that silently never matches is a fault that
can hide for a very long time — this mod's "load the round you just made into
the gun" check had been testing for the qualified name while the script
declared the bare one.

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
- **`ISModalDialog` resizes itself to fit its text**, and does not wrap. Hand it
  a paragraph and it lays the whole thing on one line and grows sideways; centre
  it on the size you passed in and the box it actually becomes hangs off to one
  side. Wrap the text yourself, then ask `ISModalDialog.CalcSize(w, h, text)`
  what it will really measure, and position from that.
- **A panel covers the chat window.** If your mod answers an admin in chat and
  they are looking at your panel, you have said nothing. Every refusal needs to
  surface where the action was taken — a button whose failure is invisible is
  reported as a button that does nothing.
- **Appearance lives on the descriptor, not the live character.** Write
  `getHumanVisual():loadLastStandString()` on the player alone and it looks
  right until anything rebuilds the model — a tick of damage — and then the game
  re-derives it from `getDescriptor()` and your change is gone. Write both.
- **An error thrown while building a context menu takes the whole menu down.**
  Guard the builder. And prefer the *inventory* context menu over the world one
  where you can: a world entry is built for every player on every right-click,
  whether your item is involved or not, so it is the one with the blast radius.
- **Probe Java objects by field, not by `type()`.** `type(x) == "table"` looks
  like a way to tell a Lua wrapper from a game object, and it works right up
  until anything else in the list is also a table — another mod's entry, or a
  test double. `x.getFullType ~= nil` asks the question you actually mean.
