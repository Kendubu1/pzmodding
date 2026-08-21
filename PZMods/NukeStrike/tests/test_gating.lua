-- Harness: checks which halves of the mod come alive in each game mode.
--
-- Run once per mode (the mod files set globals, so modes cannot share a
-- process):
--     lua5.1 PZMods/NukeStrike/tests/test_gating.lua dedicated
--     lua5.1 PZMods/NukeStrike/tests/test_gating.lua coophost
--     lua5.1 PZMods/NukeStrike/tests/test_gating.lua client
--     lua5.1 PZMods/NukeStrike/tests/test_gating.lua singleplayer
--
-- test_gating.sh runs all four and checks them against the expected matrix.

local mode = ...
assert(mode, "usage: test_gating.lua <dedicated|coophost|client|singleplayer>")

local MODES = {
    dedicated    = { server = true,  client = false, coop = false },
    coophost     = { server = false, client = false, coop = true  },
    client       = { server = false, client = true,  coop = false },
    singleplayer = { server = false, client = false, coop = false },
}
local flags = assert(MODES[mode], "unknown mode: " .. tostring(mode))

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
stubs.install(flags)
stubs.loadMod()

local registered = stubs.registered

-- The authoritative half is live if it took the commands and is watching for
-- ground loading inside a crater; the player-facing half if it took the server's
-- messages and put its entry on the right-click menu.
--
-- OnCreatePlayer used to stand in for the client half. It was only ever there to
-- ask the server for the haze zones, and the overlay that needed them is gone.
local serverLive = registered["OnClientCommand"] ~= nil and registered["LoadGridsquare"] ~= nil
local clientLive = registered["OnServerCommand"] ~= nil
    and registered["OnFillWorldObjectContextMenu"] ~= nil

stubs.realPrint(string.format("%s server=%s client=%s",
    mode, tostring(serverLive), tostring(clientLive)))
