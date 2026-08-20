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

--- Whether to bother showing the menu to this player.
---@param player IsoPlayer?
---@return boolean
local function mayCall(player)
    if player == nil then return false end
    if NS.isSingle() then return true end
    if NS.getOption("AdminOnly", true) ~= true then return true end

    local ok, admin = pcall(function() return player:isAccessLevel("admin") end)
    if ok and admin == true then return true end

    local debugOk, debugging = pcall(function() return isDebugEnabled() end)
    return debugOk and debugging == true
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
        local ok, square = pcall(function() return object:getSquare() end)
        if ok and square ~= nil then return square end
    end
    return nil
end

---@param playerIndex integer
---@param context ISContextMenu
---@param worldobjects table
---@param test boolean
local function onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
    if test then return end
    if not NS.isEnabled() then return end

    local player = getSpecificPlayer(playerIndex)
    if not mayCall(player) then return end

    local square = squareUnder(worldobjects)
    if square == nil then return end

    local x, y = math.floor(square:getX()), math.floor(square:getY())
    local target = { x = x, y = y }

    local parent = context:addOption("Nuke Strike", nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, menu)

    menu:addOption(string.format("Call a strike on %d, %d", x, y), target, call, false, false)
    menu:addOption(string.format("Roll the die for %d, %d", x, y), target, call, true, false)
    menu:addOption("Call one with no warning", target, call, false, true)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
