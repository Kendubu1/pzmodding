--[[
    Nuke Strike - the right-click way in.

    Typing /nuke is the way you call a strike on coordinates you read off a map.
    This is the other way: right-click a spot on screen and call one on it,
    without needing a chat window to be open, or to exist. Single player has no
    reliable chat box, so without this the mod would be unreachable there.

    The menu only appears for people who could call a strike anyway. That is a
    courtesy, not a lock - the server checks again when the command arrives, and
    it is the server's answer that counts.
]]

if not NukeStrike.isClientSide() then return end

local NS = NukeStrike

-- Retire this one after a single failure, unlike the per-object calls in the
-- blast, which get several goes because retrying them costs nothing. Retrying
-- here is not free: every failed attempt is another right-click the player does
-- not get. One bad menu is a bug worth bounding to one bad menu.
NS.ALLOWANCE["world context menu"] = 1

--- Whether to bother showing the menu to this player.
---@param player IsoPlayer?
---@return boolean
local function mayCall(player)
    if player == nil then return false end
    if NS.isSingle() then return true end
    if NS.getOption("AdminOnly", true) ~= true then return true end

    -- NS.try rather than a bare pcall: in Kahlua a caught error still prints its
    -- whole stack trace, so a bare pcall in a right-click handler floods the log
    -- every time anyone right-clicks anything. NS.try complains once, then stops
    -- asking.
    if NS.try("isAccessLevel", function() return player:isAccessLevel("admin") end) == true then
        return true
    end
    return NS.try("isDebugEnabled", function() return isDebugEnabled() end) == true
end

---@param target table {x, y}
---@param roll boolean
---@param immediate boolean
local function call(target, roll, immediate)
    NS.toHost("detonate", {
        x = target.x,
        y = target.y,
        roll = roll,
        immediate = immediate,
    })
end

--- The square under the cursor. The objects the menu was built from all sit on
--- it, so the first one that admits to having a square is the answer.
---@param worldobjects table
---@return IsoGridSquare?
local function squareUnder(worldobjects)
    for _, object in ipairs(worldobjects or {}) do
        local square = NS.try("getSquare", function() return object:getSquare() end)
        if square ~= nil then return square end
    end
    return nil
end

--- Attach the submenu. Separated out so the whole mutation can be guarded as
--- one unit, and so a half-built menu is never left behind.
---@param context ISContextMenu
---@param target table
---@param x integer
---@param y integer
---@return boolean built
local function buildMenu(context, target, x, y)
    local parent = context:addOption("Nuke Strike", nil, nil)
    if parent == nil then return false end

    local menu = ISContextMenu:getNew(context)
    if menu == nil then
        -- Greyed out beats dangling: an option pointing at a submenu that does
        -- not exist is what breaks the whole menu.
        parent.notAvailable = true
        return false
    end

    context:addSubMenu(parent, menu)
    menu:addOption(string.format("Call a strike on %d, %d", x, y), target, call, false, false)
    menu:addOption(string.format("Roll the die for %d, %d", x, y), target, call, true, false)
    menu:addOption("Call one with no warning", target, call, false, true)
    return true
end

---@param playerIndex integer
---@param context ISContextMenu
---@param worldobjects table
---@param test boolean
local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
    if test then return end
    if context == nil then return end
    if not NS.isEnabled() then return end

    local player = getSpecificPlayer(playerIndex)
    if not mayCall(player) then return end

    local square = squareUnder(worldobjects)
    if square == nil then return end

    local x, y = math.floor(square:getX()), math.floor(square:getY())
    local target = { x = x, y = y }

    -- Everything above this line only reads. The context is mutated below, all
    -- at once, and never before every value the options need already exists.
    --
    -- This matters more than it looks. A handler that adds its parent option and
    -- then fails leaves the menu holding a parent whose submenu never arrived,
    -- and the game cannot render that - so right-click stops working for every
    -- mod, not just this one. Guarded so a fault here costs this menu and
    -- nothing else.
    NS.try("world context menu", buildMenu, context, target, x, y)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
