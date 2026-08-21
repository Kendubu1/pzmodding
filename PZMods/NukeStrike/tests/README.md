# Logic tests

Offline checks for the parts of Nuke Strike that do not need the game running.
They stub the Project Zomboid globals (`Events`, `ModData`, `getCell`,
`getOnlinePlayers`, sandbox vars, the UI classes) and drive the real mod files
with `dofile`.

| File | What it covers |
| --- | --- |
| `test_targeting.lua` | The pure maths: what a typed command means, which damage tier a distance falls in, that the outward ring sweep visits every square exactly once, bucket keys, haze falloff over distance and time. |
| `test_zones.lua` | The record of what has been nuked: overlapping craters, haze expiry, the patch bookkeeping that stops ground being levelled twice, the cap on how many strikes are kept. |
| `test_blast.lua` | The blast engine against a toy sixteen-by-sixteen world: that the queue drains, that it levels inside the radius and not outside, that a patch which was only half loaded is left for later and levelled when it arrives, and that the fire cap holds across the sweep *and* the late arrivals. Also the vehicles: that all four halves of a wrecked car happen (parts ruined, bodywork smashed, damage overlay rebuilt, conditions transmitted), that cars beyond the blast are spared, that one car the build cannot read does not take every car after it down with it, and that a car which cannot be damaged at all is removed instead. The fakes model the API the game actually has — the previous ones offered getPartCount/getPartByIndex, which `BaseVehicle` does not have, so they passed against methods that do not exist. |
| `test_server.lua` | The server's decisions: admin gating, target resolution, off-map rejection, the d6, the countdown and aborting it, and what the fallout costs a player with and without a mask — and that the haze kills bandits (by either identifying mark) at a player's pace while leaving plain zombies alone. |
| `test_contextmenu.lua` | The right-click menu: who is offered it, that the measuring pass adds nothing, that ground with no square is skipped, that each option sends the command it says it does, and that an error inside it cannot escape into the game's menu code and take everyone's right-click with it. |
| `test_client.lua` | The screen overlay, and the one rule that matters most about it: that the element is **one pixel**, never screen-sized, and that it is not on screen at all when there is nothing to draw. An element's size is its hit box, so a full screen one swallows every click behind it — `setConsumeMouseEvents(false)` does not prevent that, it succeeds and the element eats clicks anyway. This is the test that stops the mod taking right-click away from the whole game. |
| `test_gating.sh` | Loads the mod once per game mode and checks which halves come alive against the expected matrix. The guard against the mod silently doing nothing in a mode it should support. |

They cannot test anything the game owns — whether the events actually fire,
whether `transmitRemoveItemFromSquare` really takes a wall off a square, whether
the mod loads at all. That still needs a live server.

Run from the **repository root**:

```bash
lua5.1 PZMods/NukeStrike/tests/test_targeting.lua
lua5.1 PZMods/NukeStrike/tests/test_zones.lua
lua5.1 PZMods/NukeStrike/tests/test_blast.lua
lua5.1 PZMods/NukeStrike/tests/test_server.lua
lua5.1 PZMods/NukeStrike/tests/test_contextmenu.lua
lua5.1 PZMods/NukeStrike/tests/test_client.lua
sh      PZMods/NukeStrike/tests/test_gating.sh
```

Any Lua 5.1 interpreter works (`apt install lua5.1`). All of them exit non-zero
on failure. A syntax check over the mod is worth running too:

```bash
find PZMods/NukeStrike -name '*.lua' -exec luac5.1 -p {} \;
```

This folder sits outside `42/`, so the game never reads it.
