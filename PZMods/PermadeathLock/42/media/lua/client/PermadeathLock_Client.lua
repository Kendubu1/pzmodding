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

--- Put this character on a square, from the machine that owns its position.
---
--- Done here rather than on the server, and that is the whole point. In Build 42
--- multiplayer a player's POSITION is owned by their own client: the server's
--- copy is a shadow updated from movement packets, so a server-side move is
--- overwritten by the next packet the client sends, a fraction of a second
--- later. That is exactly what a bind teleport looked like - the right place for
--- a blink, then dragged back to where the game spawned them.
---
--- Setting x/y/z alone is not enough either. The movement code interpolates
--- from a separate "last" position and holds a reference to the square the
--- character is standing on; leave those behind and the character snaps back on
--- the first step they take.
---@param x number
---@param y number
---@param z number
---@return boolean moved
local function placeAt(x, y, z)
    local player = getPlayer()
    if player == nil or player:isDead() then return false end

    -- The square has to exist on this machine before anyone can stand on it. A
    -- bind far from where the game spawned them is in a chunk that has not
    -- streamed in yet, and this is the honest way to find that out rather than
    -- moving them into nothing.
    local cell = getCell()
    local square = cell ~= nil and cell:getGridSquare(x, y, z) or nil
    if square == nil then
        print("[PermadeathLock] no square at " .. x .. "," .. y .. "," .. z
            .. " on this client yet; not moving.")
        return false
    end

    if player.setX ~= nil then
        player:setX(x)
        player:setY(y)
        player:setZ(z)
    end
    -- Where the movement code thinks it is coming from.
    if player.setLastX ~= nil then
        player:setLastX(x)
        player:setLastY(y)
    end
    if player.setLx ~= nil then
        player:setLx(x)
        player:setLy(y)
        player:setLz(z)
    end
    if player.setCurrent ~= nil then player:setCurrent(square) end

    return true
end

--- Start the countdown to whatever the server has waiting for this character.
local function beginGrace()
    if awaitingKill then return end
    awaitingKill = true
    graceTicks = 0
    Events.OnTick.Add(graceTick)
end

--- How wide a string renders, in pixels.
---@param str string
---@return number
local function measure(str)
    local manager = getTextManager ~= nil and getTextManager() or nil
    if manager ~= nil and manager.MeasureStringX ~= nil then
        local width = manager:MeasureStringX(UIFont.Small, str)
        if width ~= nil and width > 0 then return width end
    end
    -- Only a floor, for a build that does not expose the measurement.
    return #str * math.max(4, math.floor(PL.textHeight() * 0.5))
end

--- Break text into lines that fit a width, at word boundaries.
---
--- Done here rather than left to the dialog, which lays a long sentence out on
--- one line and grows sideways to fit it - a paragraph then becomes a box the
--- width of the screen.
---@param str string
---@param maxWidth number
---@return string wrapped
local function wrap(str, maxWidth)
    local lines, current = {}, ""

    for word in string.gmatch(str, "%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if current ~= "" and measure(candidate) > maxWidth then
            lines[#lines + 1] = current
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then lines[#lines + 1] = current end

    return table.concat(lines, "\n")
end

--- A modal, not a chat line: these notices land while the player is dead, and
--- the chat window is not on screen behind the death UI.
---
--- Centred, and sized from the font rather than from a pixel count. Two things
--- had to be got right, and both were wrong:
---
---   * The text is wrapped here. Handed a whole paragraph on one line, the
---     dialog runs it out sideways instead of breaking it.
---   * The dialog resizes ITSELF to fit its text when it is built, so the
---     centring has to use the size it will end up at - ISModalDialog.CalcSize
---     is how you ask. Centring on the size passed in put a box that then grew
---     wider hanging off to the right.
---
--- The death-time notices used to sit below centre, clear of the death screen's
--- own scrolling text. They are centred again by request; if the two start
--- fighting to be read, that is what changed.
---@param body string
---@param onClose function?
local function showNotice(body, onClose)
    local line = PL.textHeight()
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()

    -- Wide enough for a sentence to breathe, never more than a third or so of
    -- the screen, and never wider than the screen itself.
    local width = math.min(math.max(line * 26, math.floor(screenWidth * 0.34)), line * 46)
    width = math.max(line * 12, math.min(width, screenWidth - line * 4))

    local wrapped = wrap(body, width - line * 2)

    local breaks = 1
    for _ in string.gmatch(wrapped, "\n") do breaks = breaks + 1 end
    local height = math.min((breaks * line) + (line * 5), screenHeight - line * 4)

    -- Ask the dialog what it will actually measure, and centre on that.
    if ISModalDialog.CalcSize ~= nil then
        local ok, w, h = pcall(ISModalDialog.CalcSize, width, height, wrapped)
        if ok then
            if type(w) == "number" and w > 0 then width = w end
            if type(h) == "number" and h > 0 then height = h end
        end
    end

    local modal = ISModalDialog:new(
        math.max(0, math.floor((screenWidth - width) / 2)),
        math.max(0, math.floor((screenHeight - height) / 2)),
        width, height, wrapped, false, nil, onClose)
    modal:initialise()
    modal:addToUIManager()
end

---@param text string
local function showBlockNotice(text)
    if booting then return end
    booting = true

    -- Dead centre: this one is a disconnect warning shown on a fresh spawn,
    -- with no death screen behind it to compete with.
    showNotice(text, onDialogClosed)

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
            showNotice(text("IGUI_PermadeathLock_BlockedKilled"), nil)
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
            showNotice(text, nil)
        end
    elseif command == "tokenSpent" then
        -- Arrives at the moment of death, so it has to be a modal, and low.
        showNotice(text("IGUI_PermadeathLock_TokenSpent"), nil)
    elseif command == "fateSealed" then
        -- The other half of the same moment: died with no token, and the lock
        -- has closed. Says so now instead of leaving them to discover it by
        -- being thrown off the server on their next character.
        showNotice(text("IGUI_PermadeathLock_FateSealed"), nil)
    elseif command == "returnTo" then
        -- The server has a bind waiting and cannot make it stick from its side.
        -- Place the character here, then report back what actually happened -
        -- the server logs both views, so "the client moved and the server did
        -- not see it" is a distinguishable outcome rather than a mystery.
        local x, y, z = tonumber(args and args.x), tonumber(args and args.y),
            tonumber(args and args.z)
        if x ~= nil and y ~= nil then
            local moved = placeAt(x, y, z or 0)
            local player = getPlayer()
            if player ~= nil then
                sendClientCommand(player, MODULE, "bindMoved", {
                    moved = moved,
                    x = player:getX(),
                    y = player:getY(),
                })
            end
        end
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
            -- And on the panel, if it is open: it covers the chat window, so
            -- anything said to an admin while they are looking at it is said
            -- into a box they cannot see.
            if PermadeathLockUI ~= nil and PermadeathLockUI.instance ~= nil then
                PermadeathLockUI.instance:setStatus(text)
            end
        end
    end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnServerCommand.Add(onServerCommand)
