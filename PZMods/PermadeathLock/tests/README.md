# Logic tests

Offline checks for the parts of the mod that do not need the game running: the
death list's file format, the server's decision-making, and the admin panel's
geometry. They stub the Project Zomboid globals (`getFileWriter`,
`getOnlinePlayers`, `PerkFactory`, `Events`, the `IS*` UI classes, sandbox vars)
and drive the real mod files with `dofile`.

**The harnesses set `next` to nil before loading anything.** Kahlua, the Lua
implementation the game runs, does not provide it, and a single call to it threw
on every sweep in 1.4.0 — invisible here, because the tests run on real Lua 5.1
where `next` exists. Anything else Kahlua is missing belongs in the same place.

They cannot test anything the game owns — whether events actually fire, whether
`Kill()` behaves, whether the mod loads at all. That still needs a live server.

Run from the **repository root**:

```bash
lua5.1 PZMods/PermadeathLock/tests/test_store.lua
lua5.1 PZMods/PermadeathLock/tests/test_server.lua
lua5.1 PZMods/PermadeathLock/tests/test_layout.lua
sh      PZMods/PermadeathLock/tests/test_gating.sh
```

`test_layout.lua` builds the admin panel against stubbed UI classes at several
window sizes and checks that no band lands on another: the status line clears
the title bar, the column titles clear the status line, the list clears the
titles, the buttons clear the list, and the bottom row clears the resize strip
`ISCollapsableWindow` draws along the frame's edge. In 1.4.0 the second row of
buttons was placed two pixels *past* the bottom of the window at every size,
underneath that strip — which no syntax check can see.

`test_gating.sh` loads the mod once per game mode (dedicated, co-op host, client,
single player) and checks which halves come alive against the expected matrix.
It is the guard against the mod silently doing nothing in a mode it should
support.

Any Lua 5.1 interpreter works (`apt install lua5.1`). They all exit non-zero on
failure. A syntax check over the mod is worth running too:

```bash
find PZMods/PermadeathLock -name '*.lua' -exec luac5.1 -p {} \;
```

This folder sits outside `42/`, so the game never reads it.
