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

-- Seconds to let a new character finish loading before the server does anything
-- to it - kill it, or hand it back a dead character's skills.
--
-- Not zero, and this matters. OnCreatePlayer fires while the character is still
-- loading into the world. Acting at that instant leaves the client with no
-- valid camera target and a black screen it does not recover from; it happened
-- with the kill, and it happened again with a restore applying a whole
-- character's worth of perk levels in one go. Waiting also gives an admin a few
-- seconds to pardon someone mid-spawn without it landing on a character that
-- has already been killed.
local GRACE_SECONDS = 4

local booting = false
local bootTicks = 0
local bootTick

local awaitingKill = false
local graceTicks = 0
local graceTick

--------------------------------------------------------------------------------
-- text
--------------------------------------------------------------------------------

-- The English we ship, kept here as well as in the translation files.
--
-- getText returns the KEY when it cannot find an entry, so a translation file
-- the game has not read puts "IGUI_PermadeathLock_TokenSpent" on a player's
-- screen at the single worst moment - the instant they die. Whether those files
-- are read has turned out to depend on things outside this mod's control, and
-- the sentence a player reads at that moment should not.
--
-- The files still work and still win when they load; this is only the floor.
local FALLBACK = {
    IGUI_PermadeathLock_Blocked =
        "You died on this server. Permadeath is enabled here, so you cannot create a new"
        .. " character. If you think this is a mistake, contact an admin - they can bring"
        .. " you back.",
    IGUI_PermadeathLock_BlockedKilled =
        "You died on this server, and permadeath is enabled here. No new character of"
        .. " yours is allowed to live - this one dies now, and so will the next. An admin"
        .. " can lift it: they can pardon you, or revive you and give you back what you"
        .. " learned.",
    IGUI_PermadeathLock_TokenSpent =
        "Your Fate Token burns away. You are NOT locked out - reconnect and make a new"
        .. " character, and the skills this one earned come with you. Your body and"
        .. " everything on it stay where they fell.",
    IGUI_PermadeathLock_FateSealed =
        "Your fate has been decided. You carried no Fate Token, so this world is closed"
        .. " to you: a new character will not be allowed in. Wait, and pray for a pardon -"
        .. " only an admin can lift this.",
}

--- getText, with the shipped English as the floor.
---@param key string
---@return string
local function text(key)
    local resolved = getText(key)
    if resolved == nil or resolved == "" or resolved == key then
        return FALLBACK[key] or key
    end
    return resolved
end

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

--------------------------------------------------------------------------------
-- letting the world load before the server acts
--------------------------------------------------------------------------------

graceTick = function()
    graceTicks = graceTicks + 1
    if graceTicks < GRACE_SECONDS * TICKS_PER_SECOND then return end

    Events.OnTick.Remove(graceTick)
    graceTicks = 0
    awaitingKill = false

    local player = getPlayer()
    if player == nil or player:isDead() then return end

    -- The server re-reads the death list at this point and decides what is
    -- owed: a kill, a restore, or nothing at all because an admin pardoned them
    -- while the world was loading.
    sendClientCommand(player, MODULE, "spawnSettled", {})
end

--- Start the countdown to whatever the server has waiting for this character.
local function beginGrace()
    if awaitingKill then return end
    awaitingKill = true
    graceTicks = 0
    Events.OnTick.Add(graceTick)
end

-- Where the bottom edge of a death-screen notice sits, as a fraction of screen
-- height. Below the death screen's scrolling text, above its "continue with a
-- new character" buttons.
local LOW_NOTICE_BOTTOM = 0.72

--- A modal, not a chat line: these notices land while the player is dead, and
--- the chat window is not on screen behind the death UI.
---
--- Always horizontally centred. The vertical placement is the part that
--- matters: the death screen runs its own scrolling text through the middle of
--- the screen, so a notice shown at that moment is dropped below it rather than
--- on top of it, and the two stop fighting to be read.
---@param text string
---@param onClose function?
---@param low boolean? true to sit below centre, clear of the death text
local function showNotice(text, onClose, low)
    local width, height = 460, 210
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()

    local x = math.max(0, (screenWidth - width) / 2)

    local y
    if low then
        y = math.floor(screenHeight * LOW_NOTICE_BOTTOM) - height
    else
        y = (screenHeight - height) / 2
    end
    -- Never off the top or bottom of a short screen.
    y = math.max(0, math.min(y, screenHeight - height))

    local modal = ISModalDialog:new(x, y, width, height, text, false, nil, onClose)
    modal:initialise()
    modal:addToUIManager()
end

---@param text string
local function showBlockNotice(text)
    if booting then return end
    booting = true

    -- Dead centre: this one is a disconnect warning shown on a fresh spawn,
    -- with no death screen behind it to compete with.
    showNotice(text, onDialogClosed, false)

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
        if args ~= nil and args.kill then
            -- This character is forfeit rather than us being shown the door, so
            -- stay connected: the notice sits low, over the death screen that
            -- is a few seconds away.
            showNotice(text("IGUI_PermadeathLock_BlockedKilled"), nil, true)
            beginGrace()
        else
            showBlockNotice(text("IGUI_PermadeathLock_Blocked"))
        end
    elseif command == "settle" then
        -- Something is owed to this character - the skills of the one that
        -- died. Tell the server once the world has finished loading around us.
        beginGrace()
    elseif command == "notice" then
        -- Server-composed text, shown on screen rather than only in chat.
        -- Centred: by the time this arrives the death screen is long gone.
        local text = args and args.text
        if text ~= nil and text ~= "" then
            showNotice(text, nil, false)
        end
    elseif command == "tokenSpent" then
        -- Arrives at the moment of death, so it has to be a modal, and low.
        showNotice(text("IGUI_PermadeathLock_TokenSpent"), nil, true)
    elseif command == "fateSealed" then
        -- The other half of the same moment: died with no token, and the lock
        -- has closed. Says so now instead of leaving them to discover it by
        -- being thrown off the server on their next character.
        showNotice(text("IGUI_PermadeathLock_FateSealed"), nil, true)
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
