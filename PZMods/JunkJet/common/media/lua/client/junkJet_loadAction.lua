--[[
    Stuffing one thing down the hopper, as a timed action.

    It used to happen the instant you clicked, which was two problems wearing
    one coat. It was a balance change - forty items became forty rounds in the
    middle of a horde, with no time cost at all, where crafting a round took ten
    seconds. And it felt like nothing had happened: no bar, no sound, no reason
    to believe the game had noticed.

    One action per item rather than one for the lot, so a stack of thirty reads
    as thirty loads you can watch and walk away from. Queued actions cancel when
    the player moves, which is the whole point: you cannot cram a bag of junk
    into the gun while being chased.
]]

require "TimedActions/ISBaseTimedAction"
require "junkJet_ammoRule"

JunkJetLoadAction = ISBaseTimedAction:derive("JunkJetLoadAction")

-- About half a second. Long enough to be interruptible and to feel deliberate,
-- short enough that loading a stack is not a chore. Deliberately far quicker
-- than crafting a round, which is ten seconds: the field option should be the
-- convenient one, just not free.
local LOAD_TICKS = 30

function JunkJetLoadAction:isValid()
    if self.weapon == nil or self.item == nil then return false end

    -- Re-checked rather than trusted from when the menu was built. Between then
    -- and now the item may have been dropped, eaten, or loaded by the action
    -- queued ahead of this one.
    local inventory = self.character:getInventory()
    if inventory == nil or not inventory:contains(self.item) then return false end

    return true
end

function JunkJetLoadAction:start()
    self:setActionAnim("Loot")
    self.sound = self.character:playSound("PZ_ClickButton")
end

function JunkJetLoadAction:update()
    self.character:faceThisObject(self.weapon)
end

function JunkJetLoadAction:stop()
    ISBaseTimedAction.stop(self)
end

function JunkJetLoadAction:perform()
    local inventory = self.character:getInventory()

    if inventory ~= nil and inventory:contains(self.item) then
        -- Read before the item is destroyed. This is the only moment the gun
        -- can learn what it is loaded with.
        local fullType = self.item:getFullType()

        inventory:Remove(self.item)
        self.weapon:setCurrentAmmoCount((self.weapon:getCurrentAmmoCount() or 0) + 1)
        JunkJetAmmo.push(self.weapon, fullType)

        -- The count lives on the weapon item, so the change has to be broadcast
        -- or only this machine knows about it.
        if syncItemFields ~= nil then syncItemFields(self.character, self.weapon) end
    end

    ISBaseTimedAction.perform(self)
end

---@param character IsoGameCharacter
---@param weapon InventoryItem
---@param item InventoryItem
function JunkJetLoadAction:new(character, weapon, item)
    local o = ISBaseTimedAction.new(self, character)
    o.weapon = weapon
    o.item = item
    o.maxTime = LOAD_TICKS
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end
