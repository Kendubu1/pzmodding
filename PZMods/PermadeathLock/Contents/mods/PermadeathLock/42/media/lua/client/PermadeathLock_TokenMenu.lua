--[[
    Permadeath Lock - the Fate Token's right-click menu.

    One entry, on the token itself: bind your fate to where you are standing.
    Die carrying a token afterwards and you come back there instead of at a
    spawn point the game picks.

    Putting it on the item rather than on the ground is deliberate. A world
    context menu entry is offered to every player on every right-click whether
    they own a token or not, and an error raised while the game builds a context
    menu takes the WHOLE menu down - right-click stops working for doors,
    corpses, inventory, everything. This mod has watched that happen to a
    neighbouring mod in the same repo. On the item, the entry only exists where
    it means something, and the builder is wrapped besides.
]]

if not PermadeathLock.isClientSide() then return end

local PL = PermadeathLock

--- Send the bind. The server re-checks that a token is really in hand.
---@param player IsoPlayer
local function bindHere(player)
    if player == nil then return end
    sendClientCommand(player, PL.MODULE, "bind", {
        x = math.floor(player:getX()),
        y = math.floor(player:getY()),
        z = math.floor(player:getZ()),
    })
end

--- Is one item a Fate Token?
---
--- Probed by field rather than by type. The entries the game passes are Java
--- objects, so "is it a table" happens to distinguish them from stacks in the
--- real game and not at all anywhere else - a test double is a table too, and
--- so is anything another mod might put in the list.
---@param item any
---@return boolean
local function isToken(item)
    if item == nil or item.getFullType == nil then return false end
    return item:getFullType() == PL.FATE_TOKEN
end

--- Is any of what the player right-clicked a Fate Token?
---
--- The list is a mix of bare items and stacks; a stack keeps its contents in
--- .items and is otherwise indistinguishable.
---@param items table
---@return boolean
local function holdingToken(items)
    for _, entry in ipairs(items or {}) do
        if entry ~= nil then
            if entry.items ~= nil then
                for _, inner in ipairs(entry.items) do
                    if isToken(inner) then return true end
                end
            elseif isToken(entry) then
                return true
            end
        end
    end
    return false
end

---@param playerIndex integer
---@param context ISContextMenu
---@param items table
local function build(playerIndex, context, items)
    if not PL.getOption("FateBinding", true) then return end
    if not holdingToken(items) then return end

    local player = getSpecificPlayer(playerIndex)
    if player == nil then return end

    context:addOption("Bind your fate here", player, bindHere)
end

---@param playerIndex integer
---@param context ISContextMenu
---@param items table
local function onFillInventoryObjectContextMenu(playerIndex, context, items)
    -- Wrapped, and the whole builder is one guarded unit. An error escaping
    -- here does not cost this one entry, it costs the entire context menu.
    local ok, err = pcall(build, playerIndex, context, items)
    if not ok then
        print("[PermadeathLock] ERROR building the Fate Token menu: " .. tostring(err))
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)
