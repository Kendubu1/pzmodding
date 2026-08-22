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
lua5.1 PZMods/PermadeathLock/tests/test_commands.lua
sh      PZMods/PermadeathLock/tests/test_gating.sh
```

`test_commands.lua` drives the `/permadeath` chat parser against a stubbed
ISChat. Usernames may contain spaces and people quote them, and the parser took
only the first word after the subcommand — so `pardon Willy Guggenheim`
addressed `Willy` and `pardon "Willy Guggenheim"` addressed `"Willy`.

`test_layout.lua` builds the admin panel against stubbed UI classes and checks
that no band lands on another: the status line clears the title bar, the column
titles clear the status line, the list clears the titles, the buttons clear the
list, and the bottom row clears the resize strip `ISCollapsableWindow` draws
along the frame's edge. It also checks each band is at least as tall as the text
inside it.

It runs the whole matrix at **five font heights**, because the game's UI Scaling
setting moves them all. That is what the panel's geometry has got wrong twice:
in 1.4.0 the bottom button row sat two pixels past the frame at every size, and
through 1.6.0 every band was a fixed pixel count, so at 2x the status line, the
column titles and the first row drew on top of each other. Neither is visible
from reading the code and neither shows up in a syntax check.

`test_gating.sh` loads the mod once per game mode and checks which halves come
alive against the expected matrix. It guards against the mod silently doing
nothing in a mode it should support — and, since 1.10.0, against it doing
everything *twice*.

A co-op Host is **two** rows in that matrix, not one, because the game really
does run two Lua states in one process for a Host game and `isCoopHost()` is
true in both. Modelling it as a single mode hid a fault where the whole server
half loaded twice and two death lists arbitrated the same death to opposite
conclusions.

Any Lua 5.1 interpreter works (`apt install lua5.1`). They all exit non-zero on
failure. A syntax check over the mod is worth running too:

```bash
find PZMods/PermadeathLock -name '*.lua' -exec luac5.1 -p {} \;
```

This folder sits outside `42/`, so the game never reads it.
