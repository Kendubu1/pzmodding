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

-- Every band in this window is sized from the height of the font the game is
-- actually drawing with, never from a pixel count.
--
-- The UI Scaling setting changes the size of every glyph on screen. Constants
-- that look right at 1x collapse at 2x: a 20px status band holding 28px text
-- bleeds into the column titles, those bleed into the first row, and the bottom
-- row of buttons has its labels cut off by the frame. All three happened.
local FALLBACK_TEXT_HEIGHT = 14

---@return integer
local function textHeight()
    if getTextManager == nil then return FALLBACK_TEXT_HEIGHT end
    local manager = getTextManager()
    if manager == nil then return FALLBACK_TEXT_HEIGHT end

    local height = manager:getFontHeight(UIFont.Small)
    if height == nil or height <= 0 then return FALLBACK_TEXT_HEIGHT end
    return height
end

-- Recomputed only when the font height changes, so prerender is not allocating
-- a table every frame, and a UI Scaling change mid-session is still picked up.
local cachedMetrics = nil

--- Band heights for the font currently in use.
---@return table
local function metrics()
    local text = textHeight()
    if cachedMetrics ~= nil and cachedMetrics.text == text then
        return cachedMetrics
    end

    cachedMetrics = {
        text = text,
        pad = math.max(10, math.floor(text * 0.7)),
        row = text + 8,
        status = text + 6,
        header = text + 6,
        button = text + 14,
        -- ISCollapsableWindow lays a resize strip along the whole bottom edge
        -- of the frame and a grab handle in the corner. Anything placed flush
        -- to the bottom ends up underneath them.
        bottom = math.max(18, text + 6),
    }
    return cachedMetrics
end

--- The smallest the window can usefully be at the current font: every band at
--- its natural height, with room for three rows of list.
---@return number width, number height
local function minimumSize()
    local m = metrics()
    local height = (m.text + 2) + m.pad + m.status + m.pad + m.header
        + (m.row * 3) + m.pad + (m.button * 2) + m.pad + m.bottom
    return math.max(720, m.text * 54), height
end

-- Frames between automatic refreshes while the window is open. The roster is
-- live data - who is online, who is holding what - and a panel showing a
-- five-minute-old picture of it is worse than no panel.
local REFRESH_FRAMES = 300

-- The window sizes itself to the screen rather than to a number picked on one
-- monitor. Six columns of text need real width, and a fixed 900px is roomy at
-- 1280 wide and cramped at 3440. The bounds stop it becoming unreadable on a
-- small screen or absurd on a very large one.
local SCREEN_FRACTION_W = 0.66
local SCREEN_FRACTION_H = 0.58
local MAX_W, MAX_H = 1500, 950

--- Clamp, with the low bound winning. The minimums scale with the font, so at a
--- large UI scale they can exceed the fixed maximums; a window too small to
--- read is a worse outcome than one bigger than intended.
---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    return math.max(low, math.min(value, math.max(low, high)))
end

--- How big the panel should be on this screen, in pixels.
---@return number width, number height
local function preferredSize()
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()

    -- Clamped to the screen last, so a small screen wins over the minimum
    -- rather than the window hanging off the edge of it.
    local minWidth, minHeight = minimumSize()
    local width = clamp(math.floor(screenWidth * SCREEN_FRACTION_W), minWidth, MAX_W)
    local height = clamp(math.floor(screenHeight * SCREEN_FRACTION_H), minHeight, MAX_H)

    return math.min(width, screenWidth - 40), math.min(height, screenHeight - 40)
end

-- Column positions as fractions of the list's width, so they hold together when
-- the window is resized. Fixed pixel offsets assumed short text, and "under an
-- hour ago" ran straight into the state beside it.
local COLUMNS = {
    { key = "name",   title = "Player",      at = 0.00 },
    { key = "state",  title = "State",       at = 0.22 },
    { key = "age",    title = "Died",        at = 0.42 },
    { key = "skills", title = "Skills held", at = 0.55 },
    { key = "tokens", title = "Tokens",      at = 0.70 },
    { key = "bind",   title = "Bind",        at = 0.85 },
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

--- Where every band goes at the current frame size.
---
--- The single source of geometry: createChildren builds children at these
--- positions, and layout() puts them back after a resize. Both go through here
--- so the window a player opens is laid out identically to one they have
--- dragged, which it was not.
---@return table
function PermadeathLockUI:bands()
    local m = metrics()

    -- Top down: title bar, a gap, the status line, a gap, the column titles,
    -- then the list. Each band gets its own space, tall enough for the text it
    -- holds, instead of sharing one number that only fits at one UI scale.
    local statusY = self:titleBarHeight() + m.pad
    local headerY = statusY + m.status + m.pad
    local listTop = headerY + m.header

    -- Bottom up: the buttons anchor to the bottom of the frame and the list
    -- takes whatever is left between them, rather than the list being sized
    -- first and the buttons landing wherever that leaves them. That ordering
    -- is what pushed the second row two pixels past the bottom edge in 1.4.0,
    -- underneath the resize strip.
    local secondRow = self.height - m.bottom - m.button
    local firstRow = secondRow - m.button - m.pad

    return {
        m = m,
        statusY = statusY,
        headerY = headerY,
        listTop = listTop,
        listWidth = self.width - (m.pad * 2),
        listHeight = math.max(m.row * 2, firstRow - m.pad - listTop),
        firstRow = firstRow,
        secondRow = secondRow,
        -- Four columns of buttons. The destructive one sits alone in the far
        -- corner of the second row rather than next to Refresh, so a misclick
        -- on "refresh the list" cannot land on "wipe the list".
        slotWidth = (self.width - (m.pad * 5)) / 4,
    }
end

function PermadeathLockUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local b = self:bands()

    self.status = ISLabel:new(b.m.pad, b.statusY, b.m.status, "Loading...",
        1, 1, 1, 1, UIFont.Small, true)
    self.status:initialise()
    self:addChild(self.status)

    -- Built at its real size, never at a placeholder that layout() corrects a
    -- moment later. ISScrollingListBox lays out its scrollbar in
    -- createChildren, from whatever size the box has at that instant: born
    -- 10x10, it put the bar at x = 10 - 17, a sliver hanging off the left edge,
    -- and the rows did not appear until the window was dragged to a new size.
    self.list = ISScrollingListBox:new(b.m.pad, b.listTop, b.listWidth, b.listHeight)
    self.list.itemheight = b.m.row
    self.list.font = UIFont.Small
    self.list:initialise()
    self.list:instantiate()
    self.list.drawBorder = true
    self.list.doDrawItem = PermadeathLockUI.drawRow
    self:addChild(self.list)

    local function button(label, handler, column, y)
        return self:makeButton(label, handler,
            b.m.pad + (column - 1) * (b.slotWidth + b.m.pad), y, b.slotWidth, b.m.button)
    end

    self.pardonBtn = button("Pardon", "onPardon", 1, b.firstRow)
    self.reviveBtn = button("Revive", "onRevive", 2, b.firstRow)
    self.giveBtn = button("Give token", "onGiveToken", 3, b.firstRow)
    self.takeBtn = button("Take token", "onTakeToken", 4, b.firstRow)
    self.refreshBtn = button("Refresh", "onRefresh", 1, b.secondRow)
    self.clearBtn = button("Clear all", "onClearAll", 4, b.secondRow)

    self:layout()
end

---@param label string
---@param handler string
---@param x number
---@param y number
---@param width number
---@param height number
---@return ISButton
function PermadeathLockUI:makeButton(label, handler, x, y, width, height)
    local button = ISButton:new(x, y, width, height, label, self, PermadeathLockUI[handler])
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

    local b = self:bands()

    self.status:setX(b.m.pad)
    self.status:setY(b.statusY)
    self.status:setHeight(b.m.status)

    -- Remembered for prerender, which draws the column titles.
    self.headerY = b.headerY

    self.list:setX(b.m.pad)
    self.list:setY(b.listTop)
    self.list:setWidth(b.listWidth)
    self.list:setHeight(b.listHeight)
    self.list.itemheight = b.m.row
    -- drawRow runs with the list as self, so it reads the text height from here.
    self.list.textHeight = b.m.text

    -- The scrollbar is a child of the list and was placed once, when the list
    -- was built. Resizing the box does not move it, so put it back against the
    -- right edge at the new height.
    local bar = self.list.vscroll
    if bar ~= nil then
        bar:setX(b.listWidth - bar:getWidth())
        bar:setY(0)
        bar:setHeight(b.listHeight)
    end

    local function place(button, column, y)
        button:setX(b.m.pad + (column - 1) * (b.slotWidth + b.m.pad))
        button:setY(y)
        button:setWidth(b.slotWidth)
        button:setHeight(b.m.button)
    end

    place(self.pardonBtn, 1, b.firstRow)
    place(self.reviveBtn, 2, b.firstRow)
    place(self.giveBtn, 3, b.firstRow)
    place(self.takeBtn, 4, b.firstRow)
    place(self.refreshBtn, 1, b.secondRow)
    place(self.clearBtn, 4, b.secondRow)
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

    local y = self.headerY or (list:getY() - metrics().header)
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

--- A coordinate an admin can act on: the two numbers they would type into a
--- teleport, and the floor only when it is not the ground one.
---@param at table? {x, y, z}
---@return string
local function describePoint(at)
    if at == nil then return "-" end
    local text = math.floor(at.x or 0) .. "," .. math.floor(at.y or 0)
    if (at.z or 0) ~= 0 then text = text .. " z" .. math.floor(at.z) end
    return text
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
    local carrying = (row.tokens or 0) > 0

    -- "3 (1 bound)" rather than "3". Each token carries its own return point,
    -- so how many of them have one is the thing an admin actually wants.
    local tokens = "-"
    if row.online then
        tokens = tostring(row.tokens or 0)
        if (row.bound or 0) > 0 then tokens = tokens .. " (" .. row.bound .. " bound)" end
    end

    -- Where a Fate Token would put them. An owed restore is shown with an
    -- arrow and in front of anything still in their pocket: that coordinate is
    -- the one about to be used, and it is the one an admin is asking about when
    -- someone says they came back in the wrong place.
    local bind, bindBright = "-", false
    if row.returnTo ~= nil then
        bind = "-> " .. describePoint(row.returnTo)
        bindBright = true
    elseif row.bind ~= nil then
        bind = describePoint(row.bind)
        -- More than one bound token: only the first has room to be shown.
        if (row.bound or 0) > 1 then bind = bind .. " +" .. (row.bound - 1) end
        bindBright = true
    end

    -- Centred in the row rather than a fixed three pixels down, which only
    -- looked right while the row height was a fixed number too.
    local width = self:getWidth()
    local textY = y + math.floor((self.itemheight - (self.textHeight or 14)) / 2)

    self:drawText(name, columnX(width, "name"), textY, 1, 1, 1, 1, self.font)
    self:drawText(state, columnX(width, "state"), textY, r, g, b, 1, self.font)
    self:drawText(row.age or "", columnX(width, "age"), textY, 0.7, 0.7, 0.7, 1, self.font)
    self:drawText(skills, columnX(width, "skills"), textY, 0.7, 0.7, 0.7, 1, self.font)
    self:drawText(tokens, columnX(width, "tokens"), textY,
        carrying and 0.95 or 0.7, carrying and 0.85 or 0.7, carrying and 0.45 or 0.7, 1, self.font)
    self:drawText(bind, columnX(width, "bind"), textY,
        bindBright and 0.55 or 0.7, bindBright and 0.85 or 0.7, bindBright and 0.95 or 0.7,
        1, self.font)

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

    -- Bound tokens are counted from the registry, not from this list: a token
    -- lying in a crate has a place on record and no row here to show it on.
    local binds = ""
    if (data.binds or 0) > 0 then
        binds = string.format(", %d bound (/permadeath binds)", data.binds)
    end

    self.status:setName(string.format(
        "Permadeath Lock %s  -  lock %s, Fate Tokens %s  -  %d online, %d locked out%s   (* = offline)",
        data.version or "?",
        data.enabled and "ON" or "OFF",
        data.tokens and "on" or "off",
        online,
        locked,
        binds))
end

--- Put a line in the panel's status bar.
---
--- Every refusal this mod can give an admin - not online, no token to take, not
--- on the death list - is written to chat, and the panel sits on top of the
--- chat. A refused action was therefore indistinguishable from a button that
--- does nothing, which is exactly how it was reported.
---@param message string
function PermadeathLockUI:setStatus(message)
    if self.status ~= nil then self.status:setName(message) end
end

---@return table? row
function PermadeathLockUI:selectedRow()
    local item = self.list.items[self.list.selected]
    return item and item.item or nil
end

---@return string? username
function PermadeathLockUI:selectedUsername()
    local row = self:selectedRow()
    return row and row.username or nil
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

--- Pardon and Revive only mean anything for someone on the death list, and the
--- roster shows everyone who is playing as well. Answered here rather than
--- sending a command whose only possible reply is "X is not on the death list"
--- three times over in chat.
---@param sub string
function PermadeathLockUI:actOnListed(sub)
    local row = self:selectedRow()
    if row ~= nil and not row.listed then
        self.status:setName(row.username .. " is not on the death list - nothing to " .. sub .. ".")
        return
    end
    self:actOnSelection(sub)
end

function PermadeathLockUI:onPardon() self:actOnListed("pardon") end
function PermadeathLockUI:onRevive() self:actOnListed("revive") end

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
    -- Below this the six columns start colliding and the bands stop fitting.
    -- Both scale with the font. Drag it larger whenever you like; layout()
    -- re-runs and everything follows.
    window.minimumWidth, window.minimumHeight = minimumSize()
    return window
end
