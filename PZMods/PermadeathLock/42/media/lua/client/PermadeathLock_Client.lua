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

--- A modal, not a chat line: both notices land while the player is dead, and
--- the chat window is not on screen behind the death UI.
---
--- Placed off the centre line by default. The death screen runs its own
--- scrolling text straight down the middle, and a centred dialog lands on top
--- of it with both fighting to be read.
---@param text string
---@param onClose function?
---@param centred boolean? true to sit in the middle of the screen
local function showNotice(text, onClose, centred)
    local width, height = 440, 200
    local screenWidth = getCore():getScreenWidth()

    local x
    if centred then
        x = (screenWidth - width) / 2
    else
        -- A margin in from the left, but never off a narrow screen.
        x = math.min(64, math.max(0, (screenWidth - width) / 2))
    end
    local y = (getCore():getScreenHeight() - height) / 2

    local modal = ISModalDialog:new(x, y, width, height, text, false, nil, onClose)
    modal:initialise()
    modal:addToUIManager()
end

---@param text string
local function showBlockNotice(text)
    if booting then return end
    booting = true

    -- Centred: this one is a disconnect warning, and there is no death screen
    -- behind it to compete with.
    showNotice(text, onDialogClosed, true)

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
    elseif command == "tokenSpent" then
        -- Arrives at the moment of death, so it has to be a modal.
        showNotice(getText("IGUI_PermadeathLock_TokenSpent"), nil)
    elseif command == "openUI" then
        if PermadeathLockUI ~= nil then PermadeathLockUI.open() end
    elseif command == "listData" then
        -- Only lands if the panel asked for it; ignored when it is not open.
        if PermadeathLockUI ~= nil and PermadeathLockUI.instance ~= nil then
            PermadeathLockUI.instance:setData(args or {})
        end
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
