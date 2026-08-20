--[[
    Permadeath Lock - client side.

    Runs for a connected client, and for a co-op host, who is both the server and
    a player and so needs both halves.

    Reports this player's death to the server, asks for its status on spawn, and
    handles being told to leave. Nothing here is trusted by the server: it exists
    so a locked-out player gets an explanation instead of dying to an invisible
    hand, and so the block lands the moment they spawn rather than up to a minute
    later when the server sweep next runs.
]]

if not PermadeathLock.isClientSide() then return end

local PL = PermadeathLock
local MODULE = PL.MODULE

-- Seconds the notice stays up before we disconnect regardless of the button.
local BOOT_SECONDS = 12
local TICKS_PER_SECOND = 60

local booting = false
local bootTicks = 0
local bootTick

--------------------------------------------------------------------------------
-- being blocked
--------------------------------------------------------------------------------

local function leaveServer()
    if bootTick ~= nil then Events.OnTick.Remove(bootTick) end
    forceDisconnect()
end

bootTick = function()
    bootTicks = bootTicks + 1
    if bootTicks >= BOOT_SECONDS * TICKS_PER_SECOND then
        leaveServer()
    end
end

local function onDialogClosed()
    leaveServer()
end

---@param text string
local function showBlockNotice(text)
    if booting then return end
    booting = true

    local width, height = 520, 220
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local modal = ISModalDialog:new(x, y, width, height, text, false, nil, onDialogClosed)
    modal:initialise()
    modal:addToUIManager()

    -- Backstop: leave even if the notice is never dismissed.
    Events.OnTick.Add(bootTick)
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

---@param playerIndex integer
---@param player IsoPlayer
local function onCreatePlayer(playerIndex, player)
    if playerIndex ~= 0 or player == nil then return end
    sendClientCommand(player, MODULE, "checkStatus", {})
end

---@param player IsoPlayer
local function onPlayerDeath(player)
    if player == nil then return end
    sendClientCommand(player, MODULE, "reportDeath", {})
end

---@param module string
---@param command string
---@param args table?
local function onServerCommand(module, command, args)
    if module ~= MODULE then return end

    if command == "blocked" then
        showBlockNotice(getText("IGUI_PermadeathLock_Blocked"))
    elseif command == "message" then
        local text = args and args.text
        if text ~= nil and text ~= "" then
            processGeneralMessage(text)
        end
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnServerCommand.Add(onServerCommand)
