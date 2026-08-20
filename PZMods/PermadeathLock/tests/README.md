# Logic tests

Offline checks for the parts of the mod that do not need the game running: the
death list's file format and the server's decision-making. They stub the Project
Zomboid globals (`getFileWriter`, `getOnlinePlayers`, `PerkFactory`, `Events`,
sandbox vars) and drive the real mod files with `dofile`.

They cannot test anything the game owns — whether events actually fire, whether
`Kill()` behaves, whether the mod loads at all. That still needs a live server.

Run from the **repository root**:

```bash
lua5.1 PZMods/PermadeathLock/tests/test_store.lua
lua5.1 PZMods/PermadeathLock/tests/test_server.lua
```

Any Lua 5.1 interpreter works (`apt install lua5.1`). Both exit non-zero on
failure. A syntax check over the mod is worth running too:

```bash
find PZMods/PermadeathLock -name '*.lua' -exec luac5.1 -p {} \;
```

This folder sits outside `42/`, so the game never reads it.
