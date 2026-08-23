-- Harness: checks which halves of the mod load in each game mode.
--
-- Run once per mode (the mod files set globals, so modes cannot share a process):
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua dedicated
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua coophost-server
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua coophost-client
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua client
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua singleplayer
--
-- test_gating.sh runs all five and checks them against the expected matrix.
--
-- A co-op Host is TWO modes, not one, and that is the whole point of this file
-- now. The game runs two Lua states in one process for a Host game, and
-- isCoopHost() is true in both. Treating it as a single mode hid a fault where
-- the entire server half loaded twice - two death lists arbitrating the same
-- death and reaching opposite conclusions.

local mode = ...
assert(mode, "usage: test_gating.lua <dedicated|coophost|client|singleplayer>")

local MODES = {
    dedicated         = { server = true,  client = false, coop = false },
    -- The two halves of one Host game.
    ["coophost-server"] = { server = true,  client = false, coop = true  },
    ["coophost-client"] = { server = false, client = true,  coop = true  },
    client            = { server = false, client = true,  coop = false },
    singleplayer      = { server = false, client = false, coop = false },
}
local flags = assert(MODES[mode], "unknown mode: " .. tostring(mode))

function isServer() return flags.server end
function isClient() return flags.client end
function isCoopHost() return flags.coop end
function getTimestamp() return 0 end
function print() end

SandboxVars = {}

local registered = {}
Events = setmetatable({}, { __index = function(t, name)
    local slot = {
        Add = function() registered[name] = true end,
        Remove = function() end,
    }
    rawset(t, name, slot)
    return slot
end })

-- Minimal stubs for what the files touch while loading.
ISChat = { onCommandEntered = function() end }

--- Stand-in for an ISUI class: enough for `X:derive("Name")` at load time.
local function isClass()
    local cls = {}
    cls.derive = function() return isClass() end
    return cls
end
ISCollapsableWindow = isClass()
ISScrollingListBox = isClass()
ISButton = isClass()
ISLabel = isClass()
ISModalDialog = isClass()
function getFileReader() return nil end
function getFileWriter() return nil end
function require(_) end
ProceduralDistributions = { list = {} }

local base = "PZMods/PermadeathLock/42/media/lua/"
dofile(base .. "shared/PermadeathLock_Shared.lua")
-- Alphabetical, as the game loads them: Server before Store.
dofile(base .. "server/PermadeathLock_Binds.lua")
dofile(base .. "server/PermadeathLock_Loot.lua")
dofile(base .. "server/PermadeathLock_Server.lua")
dofile(base .. "server/PermadeathLock_Store.lua")
dofile(base .. "client/PermadeathLock_AdminUI.lua")
dofile(base .. "client/PermadeathLock_Client.lua")
dofile(base .. "client/PermadeathLock_Commands.lua")
dofile(base .. "client/PermadeathLock_TokenMenu.lua")

-- The server half is live if it hooked the sweep; the client half if it hooked
-- the spawn handshake and replaced the chat command handler.
-- Loot injection counts as the server half too. It writes to a shared table
-- that persists for the life of the process, so a copy of it running in the
-- client half of a co-op Host would double every drop rate - the same shape of
-- bug as the one that used to burn a Fate Token twice.
local serverLive = registered["EveryOneMinute"] == true
    and registered["OnClientCommand"] == true
    and registered["OnPreDistributionMerge"] == true
local clientLive = registered["OnCreatePlayer"] == true and registered["OnServerCommand"] == true

io.write(string.format("%s server=%s client=%s\n", mode, tostring(serverLive), tostring(clientLive)))
