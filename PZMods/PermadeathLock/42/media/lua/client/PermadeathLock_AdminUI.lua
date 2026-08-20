--[[
    Permadeath Lock - admin panel.

    A window over the death list: pick a player, act on them. Opened with
    /permadeath ui.

    It is a view, not an authority. Every button sends the same client command
    the chat equivalent does, and the server re-checks the sender's access level
    before acting. A non-admin who forces this window open sees an empty list and
    gets refused on every click.
]]

if not PermadeathLock.isClientSide() then return end

local PL = PermadeathLock

PermadeathLockUI = ISCollapsableWindow:derive("PermadeathLockUI")
PermadeathLockUI.instance = nil

local ROW_HEIGHT = 22
local PAD = 10
local BUTTON_HEIGHT = 24

--------------------------------------------------------------------------------
-- talking to the server
--------------------------------------------------------------------------------

---@param sub string
---@param target string?
local function send(sub, target)
    local player = getPlayer()
    if player == nil then return end
    sendClientCommand(player, PL.MODULE, "admin", { sub = sub, target = target })
end

--------------------------------------------------------------------------------
-- window
--------------------------------------------------------------------------------

function PermadeathLockUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local top = self:titleBarHeight() + PAD
    local listHeight = self.height - top - (BUTTON_HEIGHT * 2) - (PAD * 4)

    self.status = ISLabel:new(PAD, top, 18, "Loading...", 1, 1, 1, 1, UIFont.Small, true)
    self.status:initialise()
    self:addChild(self.status)

    self.list = ISScrollingListBox:new(PAD, top + 22, self.width - (PAD * 2), listHeight)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_HEIGHT
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = PermadeathLockUI.drawRow
    self:addChild(self.list)

    local buttonY = top + 22 + listHeight + PAD
    local buttonWidth = (self.width - (PAD * 3)) / 2

    self.pardonBtn = self:makeButton(PAD, buttonY, buttonWidth, "Pardon", "onPardon")
    self.reviveBtn = self:makeButton(PAD * 2 + buttonWidth, buttonY, buttonWidth, "Revive", "onRevive")

    local secondRow = buttonY + BUTTON_HEIGHT + PAD
    self.refreshBtn = self:makeButton(PAD, secondRow, buttonWidth, "Refresh", "onRefresh")
    self.clearBtn = self:makeButton(PAD * 2 + buttonWidth, secondRow, buttonWidth, "Clear all", "onClearAll")
end

---@param x number
---@param y number
---@param width number
---@param label string
---@param handler string
---@return ISButton
function PermadeathLockUI:makeButton(x, y, width, label, handler)
    local button = ISButton:new(x, y, width, BUTTON_HEIGHT, label, self, PermadeathLockUI[handler])
    button:initialise()
    button:instantiate()
    button.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self:addChild(button)
    return button
end

--- One row: name, how long ago, and what state they are in.
function PermadeathLockUI:drawRow(y, item, alt)
    local row = item.item
    if row == nil then return y + self.itemheight end

    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.7, 0.35, 0.15)
    end
    self:drawRectBorder(0, y, self:getWidth(), self.itemheight, 0.5, 0.5, 0.5, 0.5)

    local state, r, g, b
    if row.pendingRestore then
        state, r, g, b = "awaiting restore", 0.55, 0.85, 0.55
    else
        state, r, g, b = "locked", 0.9, 0.45, 0.45
    end

    local name = row.username
    if row.online then name = name .. " (online)" end

    -- Columns as fractions of the actual width, not fixed pixel offsets. The
    -- old numbers assumed short text and "under an hour ago" ran straight into
    -- the state beside it.
    local width = self:getWidth()
    local nameX = 8
    local ageX = math.floor(width * 0.34)
    local stateX = math.floor(width * 0.60)
    local skillX = math.floor(width * 0.82)

    self:drawText(name, nameX, y + 3, 1, 1, 1, 1, self.font)
    self:drawText(row.age or "", ageX, y + 3, 0.7, 0.7, 0.7, 1, self.font)
    self:drawText(state, stateX, y + 3, r, g, b, 1, self.font)
    self:drawText(row.skills .. " skills", skillX, y + 3, 0.7, 0.7, 0.7, 1, self.font)

    return y + self.itemheight
end

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

---@param data table
function PermadeathLockUI:setData(data)
    self.list:clear()
    for _, row in ipairs(data.rows or {}) do
        self.list:addItem(row.username, row)
    end

    local locked = 0
    for _, row in ipairs(data.rows or {}) do
        if row.locked then locked = locked + 1 end
    end

    self.status:setName(string.format("Permadeath Lock %s  -  %s  -  %d locked, %d total  -  Fate Tokens %s",
        data.version or "?",
        data.enabled and "ON" or "OFF",
        locked,
        #(data.rows or {}),
        data.tokens and "on" or "off"))
end

---@return string? username
function PermadeathLockUI:selectedUsername()
    local item = self.list.items[self.list.selected]
    return item and item.item and item.item.username or nil
end

--- Act on the selected row, or explain that there isn't one.
---@param sub string
function PermadeathLockUI:actOnSelection(sub)
    local username = self:selectedUsername()
    if username == nil then
        self.status:setName("Select a player first.")
        return
    end
    send(sub, username)
    -- The server answers the action, then we ask for the list again so the
    -- window reflects what actually happened rather than what we assumed.
    send("listData", nil)
end

--------------------------------------------------------------------------------
-- buttons
--------------------------------------------------------------------------------

function PermadeathLockUI:onPardon() self:actOnSelection("pardon") end
function PermadeathLockUI:onRevive() self:actOnSelection("revive") end

function PermadeathLockUI:onRefresh()
    self.status:setName("Refreshing...")
    send("listData", nil)
end

--- Wiping the list is the one action here that cannot be undone, so it asks.
--- Both this and onRefresh were referenced by createChildren but never defined,
--- which left the panel's whole second row of buttons dead.
function PermadeathLockUI:onClearAll()
    local width, height = 340, 150
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local modal = ISModalDialog:new(x, y, width, height,
        "Wipe the entire death list? Everyone on it may return with a new character.",
        true, self, PermadeathLockUI.onClearAllConfirm)
    modal:initialise()
    modal:addToUIManager()
end

---@param button ISButton
function PermadeathLockUI:onClearAllConfirm(button)
    if button.internal ~= "YES" then return end
    send("clear", "confirm")
    send("listData", nil)
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

function PermadeathLockUI.open()
    if PermadeathLockUI.instance ~= nil then
        PermadeathLockUI.instance:setVisible(true)
        PermadeathLockUI.instance:addToUIManager()
        send("listData", nil)
        return PermadeathLockUI.instance
    end

    local width, height = 820, 440
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local window = PermadeathLockUI:new(x, y, width, height)
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    PermadeathLockUI.instance = window
    return window
end

function PermadeathLockUI:close()
    ISCollapsableWindow.close(self)
    self:setVisible(false)
    self:removeFromUIManager()
end

---@return PermadeathLockUI
function PermadeathLockUI:new(x, y, width, height)
    local window = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(window, self)
    self.__index = self
    window:setTitle("Permadeath Lock")
    window:setResizable(true)
    window.minimumWidth = 520
    window.minimumHeight = 300
    return window
end
