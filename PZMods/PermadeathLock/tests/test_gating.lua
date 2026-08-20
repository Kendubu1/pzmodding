-- Harness: checks which halves of the mod load in each game mode.
--
-- Run once per mode (the mod files set globals, so modes cannot share a process):
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua dedicated
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua coophost
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua client
--     lua5.1 PZMods/PermadeathLock/tests/test_gating.lua singleplayer
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
function getFileReader() return nil end
function getFileWriter() return nil end

local base = "PZMods/PermadeathLock/42/media/lua/"
dofile(base .. "shared/PermadeathLock_Shared.lua")
dofile(base .. "server/PermadeathLock_Store.lua")
dofile(base .. "server/PermadeathLock_Server.lua")
dofile(base .. "client/PermadeathLock_Client.lua")
dofile(base .. "client/PermadeathLock_Commands.lua")

-- The server half is live if it hooked the sweep; the client half if it hooked
-- the spawn handshake and replaced the chat command handler.
local serverLive = registered["EveryOneMinute"] == true and registered["OnClientCommand"] == true
local clientLive = registered["OnCreatePlayer"] == true and registered["OnServerCommand"] == true

io.write(string.format("%s server=%s client=%s\n", mode, tostring(serverLive), tostring(clientLive)))
