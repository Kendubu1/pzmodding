# Testing the Junk Jet

Everything here needs the game. The offline suites in `tests/` already cover the
arithmetic — what counts as ammo, what the hopper remembers, where a shot lands
— so none of that is repeated below. What follows is only what a machine cannot
check.

Run the offline suites first; if they fail, do not bother launching anything:

```
lua5.1 PZMods/JunkJet/tests/test_ammorule.lua
lua5.1 PZMods/JunkJet/tests/test_flight.lua
```

## Installing a test copy

The game loads `Zomboid/mods/JunkJet/`, and the folder that goes there is the
mod folder itself:

```
PZMods/JunkJet/  ->  %USERPROFILE%\Zomboid\mods\JunkJet\
```

`watch-junkjet.ps1` in the mod folder mirrors it on a two-second loop:

```
powershell -ExecutionPolicy Bypass -File .\watch-junkjet.ps1
```

**Lua is not hot-loaded.** Restart the game after every change, not just the
save.

## Which build is which

The two builds read different folders, and that is the whole point of testing
both:

| Build | Reads | Does **not** read |
| --- | --- | --- |
| 41 | `common/` + `41/` | anything in `42/` |
| 42 | `common/` + `42/` | anything in `41/` |

So a fault in `common/` shows up on both, and a fault in a version folder shows
up on exactly one. **If something misbehaves on one build only, look in that
build's folder first** — that is almost always where it is.

---

## Build 41

The live build: this is what the multiplayer server runs and what the Workshop
subscribers have. Regressions here matter most.

### 1. Nothing broke (do this first)

- [ ] The mod appears in the mod list, named and with its icon
- [ ] `/additem <you> JunkJet.JunkJet_Weapon` gives you the gun
- [ ] The gun is **visible in your hands** and **visible on the ground** when
      dropped
- [ ] The crafting recipes still appear after reading *Vault Dwellers Builder
      Guide*, and still work
- [ ] Crafting a round **while holding the gun** loads it straight in — the
      count goes up and no loose ammo appears in your bag

That last one is the auto-load. It is old behaviour and easy to break.

### 2. Repairability — the request this closes

- [ ] Damage the gun (shoot it until the condition drops)
- [ ] Right-click it: a repair option appears
- [ ] It repairs with sheet metal, screws, duct tape, glue or tape
- [ ] Condition actually goes up

**Build 41 only.** If this is missing on 42, that is expected and documented.

### 3. Loading junk

- [ ] Right-click a toy car with the gun in your inventory → **Load into Junk
      Jet**
- [ ] A progress bar runs — it is not instant
- [ ] Walking away part-way **cancels** it and you keep the item
- [ ] On finishing, the item is gone and the gun's ammo count is up by one
- [ ] Select a stack of several → the entry reads **Load into Junk Jet (n)** and
      queues n loads

Then the rules:

- [ ] A tin of beans is **not** offered (default: junk only)
- [ ] Sandbox → Junk Jet → turn **Only junk can be loaded** off → the beans are
      now offered
- [ ] Set **Heaviest thing you can load** to 0 → a sledgehammer is offered
- [ ] The Junk Jet, its ammo and its magazine are **never** offered
- [ ] A bag with things in it is **never** offered

### 4. Flying junk

- [ ] Load a toy car, fire at a zombie
- [ ] **Something visibly flies.** If not, see *When junk does not fly* below
- [ ] The toy car is on the ground where it stopped
- [ ] You can pick it back up
- [ ] Fire at a wall from a few tiles away → the junk lands **against** the
      wall, not inside it, and is retrievable
- [ ] Fire ten rounds quickly → no stutter, and junk from every shot is
      findable

### 5. Multiplayer — the one that matters most

Quakethorn's report was from a multiplayer server, so this is the real
acceptance test. Two clients, or a host and a joiner.

- [ ] Player A loads junk. **A's own ammo count is right**
- [ ] A disconnects and reconnects — the count survives
- [ ] A fires. **A sees junk fly**
- [ ] **What does B see?** Expected: nothing flies for B, but the item does
      appear on the ground. Anything worse than that is a finding
- [ ] B can pick up junk A fired
- [ ] Neither client logs a Lua error

Say what B actually saw either way. "Nothing flew for B" is a useful result, not
a failure.

---

## Build 42

Newer, less proven, and the build three people asked about on the Workshop page.

### 1. Does it load at all

- [ ] The mod appears, named, with its icon and poster
- [ ] The console shows **no** script or Lua errors at boot

### 2. Text — the fault that hides

Build 42.15 changed the translation format, so this is the first thing to look
at and the easiest to miss:

- [ ] The gun's tooltip is a **sentence**, not `Tooltip_JunkJetWeapon`
- [ ] The item names read properly
- [ ] The right-click entry says **Load into Junk Jet**, not
      `ContextMenu_JunkJet_Load`
- [ ] Sandbox → Junk Jet options read as sentences, not
      `Sandbox_JunkJet_...`

Any raw key here means the `.json` files are not being read, and the whole
category fails together.

### 3. Models

- [ ] The gun is visible **in your hands**
- [ ] The gun is visible **on the ground** — this is the fix that went in; it
      was invisible before
- [ ] Ammo and the magazine are visible on the ground

### 4. Crafting — three fixes to confirm

Each of these was wrong and is now changed:

- [ ] The recipes are **not** available until you read the magazine
      (`NeedToBeLearn` had the wrong capitalisation and was being ignored)
- [ ] Making the gun asks for **one** blowtorch, not ninety, and does not
      destroy it
- [ ] `/additem <you> Base.Pipe` gives you a pipe. **Still unverified** — if it
      errors, the recipe needs a different item name
- [ ] Crafting a round while holding the gun loads it straight in (this was
      silently missing on 42 entirely)

### 5. Everything else

Repeat Build 41 sections 3 and 4 — loading and flying — on 42.

- [ ] Loading behaves the same
- [ ] Junk flies and lands the same
- [ ] Repair is **absent**. Expected, not a bug

---

## When junk does not fly

In order of likelihood:

1. **`OnWeaponSwing` may not fire for a ranged weapon on your build.** This is
   the single most likely cause and it is a one-line swap to
   `OnPlayerAttackFinished`. Symptom: the gun shoots normally, nothing flies,
   and no error appears.
2. **`Render3DItem` may not exist.** Symptom: nothing flies, but the junk still
   lands on the ground and is retrievable. Drawing fails quietly on purpose —
   an invisible round you can pick up beats an error every tick.
3. **The hopper forgot.** Past 64 remembered rounds the gun fires anonymous
   junk with nothing to draw or drop. Only reachable by loading a great deal at
   once.

Tell them apart by whether the item lands: **lands but does not fly** is (2) or
(3); **neither** is (1).

## What to send back

- `console.txt` from the run, if anything went wrong
- Which build, and single player or multiplayer
- For multiplayer, what the **other** player saw

A checklist item that failed is more useful than one that passed, so do not tidy
those out.
