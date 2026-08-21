--[[
    Permadeath Lock - admin panel.

    A window over the roster: pick a player, act on them. Opened with
    /permadeath ui.

    It lists everyone online as well as everyone on the death list, because most
    of what an admin needs to see is about people who are NOT dead - who is
    playing, who is exempt and so cannot be locked out at all, and who is
    carrying a Fate Token.

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
local HEADER_HEIGHT = 18
local STATUS_HEIGHT = 20

-- ISCollapsableWindow lays a resize strip along the whole bottom edge of the
-- frame and a grab handle in the corner. Anything placed flush to the bottom
-- ends up underneath them. The margin has to clear both, with room to spare.
local BOTTOM_MARGIN = 18

-- Frames between automatic refreshes while the window is open. The roster is
-- live data - who is online, who is holding what - and a panel showing a
-- five-minute-old picture of it is worse than no panel.
local REFRESH_FRAMES = 300

-- The window sizes itself to the screen rather than to a number picked on one
-- monitor. Five columns of text need real width, and a fixed 900px is roomy at
-- 1280 wide and cramped at 3440. The bounds stop it becoming unreadable on a
-- small screen or absurd on a very large one.
local SCREEN_FRACTION_W = 0.66
local SCREEN_FRACTION_H = 0.58
local MIN_W, MAX_W = 720, 1500
local MIN_H, MAX_H = 360, 950

---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    return math.max(low, math.min(value, high))
end

--- How big the panel should be on this screen, in pixels.
---@return number width, number height
local function preferredSize()
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()

    -- Clamped to the screen last, so a small screen wins over the minimum
    -- rather than the window hanging off the edge of it.
    local width = clamp(math.floor(screenWidth * SCREEN_FRACTION_W), MIN_W, MAX_W)
    local height = clamp(math.floor(screenHeight * SCREEN_FRACTION_H), MIN_H, MAX_H)

    return math.min(width, screenWidth - 40), math.min(height, screenHeight - 40)
end

-- Column positions as fractions of the list's width, so they hold together when
-- the window is resized. Fixed pixel offsets assumed short text, and "under an
-- hour ago" ran straight into the state beside it.
local COLUMNS = {
    { key = "name",   title = "Player",      at = 0.00 },
    { key = "state",  title = "State",       at = 0.28 },
    { key = "age",    title = "Died",        at = 0.52 },
    { key = "skills", title = "Skills held", at = 0.68 },
    { key = "tokens", title = "Tokens",      at = 0.85 },
}

---@param width number the list's width
---@param key string
---@return number
local function columnX(width, key)
    for _, column in ipairs(COLUMNS) do
        if column.key == key then
            return 8 + math.floor((width - 16) * column.at)
        end
    end
    return 8
end

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

    self.status = ISLabel:new(PAD, 0, 18, "Loading...", 1, 1, 1, 1, UIFont.Small, true)
    self.status:initialise()
    self:addChild(self.status)

    self.list = ISScrollingListBox:new(PAD, 0, 10, 10)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = ROW_HEIGHT
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = PermadeathLockUI.drawRow
    self:addChild(self.list)

    self.pardonBtn = self:makeButton("Pardon", "onPardon")
    self.reviveBtn = self:makeButton("Revive", "onRevive")
    self.giveBtn = self:makeButton("Give token", "onGiveToken")
    self.takeBtn = self:makeButton("Take token", "onTakeToken")
    self.refreshBtn = self:makeButton("Refresh", "onRefresh")
    self.clearBtn = self:makeButton("Clear all", "onClearAll")

    self:layout()
end

---@param label string
---@param handler string
---@return ISButton
function PermadeathLockUI:makeButton(label, handler)
    local button = ISButton:new(0, 0, 10, BUTTON_HEIGHT, label, self, PermadeathLockUI[handler])
    button:initialise()
    button:instantiate()
    button.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self:addChild(button)
    return button
end

--- Place everything. Called once when the window is built and again whenever it
--- is dragged to a new size: children are positioned in absolute pixels and do
--- not follow the frame on their own.
function PermadeathLockUI:layout()
    if self.list == nil then return end

    -- Top down: title bar, a gap, the status line, a gap, the column titles,
    -- then the list. Each band gets its own space instead of sharing one
    -- number, which is how the status line and the column titles ended up
    -- almost touching.
    local statusY = self:titleBarHeight() + PAD
    local headerY = statusY + STATUS_HEIGHT + PAD
    local listTop = headerY + HEADER_HEIGHT

    -- Bottom up: the buttons anchor to the bottom of the frame and the list
    -- takes whatever is left between them, rather than the list being sized
    -- first and the buttons landing wherever that leaves them. That ordering
    -- is what pushed the second row two pixels past the bottom edge in 1.4.0,
    -- underneath the resize strip.
    local secondRow = self.height - BOTTOM_MARGIN - BUTTON_HEIGHT
    local firstRow = secondRow - BUTTON_HEIGHT - PAD
    local listHeight = math.max(ROW_HEIGHT * 2, firstRow - PAD - listTop)

    self.status:setX(PAD)
    self.status:setY(statusY)

    -- Remembered for prerender, which draws the column titles.
    self.headerY = headerY

    self.list:setX(PAD)
    self.list:setY(listTop)
    self.list:setWidth(self.width - (PAD * 2))
    self.list:setHeight(listHeight)

    -- Four columns of buttons. The destructive one sits alone in the far corner
    -- of the second row rather than next to Refresh, so a misclick on "refresh
    -- the list" cannot land on "wipe the list".
    local slotWidth = (self.width - (PAD * 5)) / 4

    local function place(button, column, y)
        button:setX(PAD + (column - 1) * (slotWidth + PAD))
        button:setY(y)
        button:setWidth(slotWidth)
    end

    place(self.pardonBtn, 1, firstRow)
    place(self.reviveBtn, 2, firstRow)
    place(self.giveBtn, 3, firstRow)
    place(self.takeBtn, 4, firstRow)
    place(self.refreshBtn, 1, secondRow)
    place(self.clearBtn, 4, secondRow)
end

function PermadeathLockUI:onResize()
    if ISCollapsableWindow.onResize ~= nil then
        ISCollapsableWindow.onResize(self)
    end
    self:layout()
end

--- Column titles, drawn above the list rather than inside it so they do not
--- scroll away with the rows. Also where the periodic refresh is driven from,
--- since it only needs to happen while the window is actually on screen.
function PermadeathLockUI:prerender()
    ISCollapsableWindow.prerender(self)

    self.sinceRefresh = (self.sinceRefresh or 0) + 1
    if self.sinceRefresh >= REFRESH_FRAMES then
        self.sinceRefresh = 0
        -- Only for admins. The server answers a non-admin with a refusal in
        -- chat, and doing that every few seconds would be its own bug.
        local player = getPlayer()
        if player ~= nil and player:isAccessLevel("admin") then
            send("listData", nil)
        end
    end

    local list = self.list
    if list == nil then return end

    local y = self.headerY or (list:getY() - HEADER_HEIGHT)
    for _, column in ipairs(COLUMNS) do
        self:drawText(column.title,
            list:getX() + columnX(list:getWidth(), column.key),
            y, 0.6, 0.6, 0.6, 1, UIFont.Small)
    end
end

--------------------------------------------------------------------------------
-- rows
--------------------------------------------------------------------------------

--- What to call this player's situation, and what colour to say it in.
---@param row table
---@return string, number, number, number
local function describeState(row)
    if row.locked then return "LOCKED OUT", 0.95, 0.40, 0.40 end
    if row.pendingRestore then return "awaiting restore", 0.55, 0.85, 0.55 end
    if not row.online then return "offline", 0.55, 0.55, 0.55 end
    -- Dead and not on the list: either the sweep has not caught up yet, or an
    -- admin has pardoned them and the corpse is still lying where it fell.
    if row.dead then return "dead, not listed", 0.95, 0.75, 0.35 end
    -- Worth calling out. An exempt admin cannot be locked out at all, and that
    -- reads as the mod being broken to anyone who has forgotten the setting.
    if row.exempt then return "alive (exempt)", 0.60, 0.75, 0.95 end
    return "alive", 0.85, 0.85, 0.85
end

--- One row: who they are, how they stand, and what they are holding.
function PermadeathLockUI:drawRow(y, item, alt)
    local row = item.item
    if row == nil then return y + self.itemheight end

    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.7, 0.35, 0.15)
    end
    self:drawRectBorder(0, y, self:getWidth(), self.itemheight, 0.5, 0.5, 0.5, 0.5)

    local state, r, g, b = describeState(row)

    local name = row.username
    if not row.online then name = name .. " *" end

    -- Skills are only held for someone on the death list, and a token count is
    -- only knowable for someone online. A dash means "not applicable", which is
    -- a different thing from zero and should not be dressed up as one.
    local skills = row.listed and tostring(row.skills or 0) or "-"
    local tokens = row.online and tostring(row.tokens or 0) or "-"
    local carrying = (row.tokens or 0) > 0

    local width = self:getWidth()
    self:drawText(name, columnX(width, "name"), y + 3, 1, 1, 1, 1, self.font)
    self:drawText(state, columnX(width, "state"), y + 3, r, g, b, 1, self.font)
    self:drawText(row.age or "", columnX(width, "age"), y + 3, 0.7, 0.7, 0.7, 1, self.font)
    self:drawText(skills, columnX(width, "skills"), y + 3, 0.7, 0.7, 0.7, 1, self.font)
    self:drawText(tokens, columnX(width, "tokens"), y + 3,
        carrying and 0.95 or 0.7, carrying and 0.85 or 0.7, carrying and 0.45 or 0.7, 1, self.font)

    return y + self.itemheight
end

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

---@param data table
function PermadeathLockUI:setData(data)
    local rows = data.rows or {}

    -- Keep the selected player selected across a refresh. The roster reorders
    -- itself as people's states change, and acting on whoever happened to slide
    -- into the highlighted row is exactly the wrong thing.
    local wanted = self:selectedUsername()

    self.list:clear()
    for index, row in ipairs(rows) do
        self.list:addItem(row.username, row)
        if wanted ~= nil and row.username == wanted then
            self.list.selected = index
        end
    end

    local locked, online = 0, 0
    for _, row in ipairs(rows) do
        if row.locked then locked = locked + 1 end
        if row.online then online = online + 1 end
    end

    self.status:setName(string.format(
        "Permadeath Lock %s  -  lock %s, Fate Tokens %s  -  %d online, %d locked out   (* = offline)",
        data.version or "?",
        data.enabled and "ON" or "OFF",
        data.tokens and "on" or "off",
        online,
        locked))
end

---@return string? username
function PermadeathLockUI:selectedUsername()
    local item = self.list.items[self.list.selected]
    return item and item.item and item.item.username or nil
end

--- Act on the selected row, or explain that there isn't one.
---@param sub string
---@param serverWillRefresh boolean? true when the server pushes the new roster
function PermadeathLockUI:actOnSelection(sub, serverWillRefresh)
    local username = self:selectedUsername()
    if username == nil then
        self.status:setName("Select a player first.")
        return
    end

    send(sub, username)
    if not serverWillRefresh then
        -- The server answers the action, then we ask for the roster again so
        -- the window shows what actually happened, not what we assumed.
        send("listData", nil)
    end
end

--------------------------------------------------------------------------------
-- buttons
--------------------------------------------------------------------------------

function PermadeathLockUI:onPardon() self:actOnSelection("pardon") end
function PermadeathLockUI:onRevive() self:actOnSelection("revive") end

-- Handing a token over is done by the target's own client, so the server pushes
-- a fresh roster once that has actually happened. Asking for one here would
-- only fetch the count from before the change.
function PermadeathLockUI:onGiveToken() self:actOnSelection("give", true) end
function PermadeathLockUI:onTakeToken() self:actOnSelection("take", true) end

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

    local width, height = preferredSize()
    local x = (getCore():getScreenWidth() - width) / 2
    local y = (getCore():getScreenHeight() - height) / 2

    local window = PermadeathLockUI:new(x, y, width, height)
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    PermadeathLockUI.instance = window
    -- A freshly built window asked the server for nothing and sat on "Loading..."
    -- until someone pressed Refresh.
    send("listData", nil)
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
    -- Below this the five columns start colliding. Drag it wider whenever you
    -- like; layout() re-runs and the columns follow.
    window.minimumWidth = 640
    window.minimumHeight = 320
    return window
end
