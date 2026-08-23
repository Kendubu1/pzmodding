-- Harness: builds the admin panel against stubbed Project Zomboid UI classes
-- and checks that nothing lands on top of anything else.
--
-- This exists because the geometry was wrong twice. In 1.4.0 the second row of
-- buttons was placed two pixels PAST the bottom of the frame, on top of the
-- resize strip ISCollapsableWindow draws there; the status line and the column
-- titles were four pixels apart. Neither is visible from reading the code, and
-- neither is caught by a syntax check.

next = nil  -- as in the other harnesses: Kahlua does not provide it

function isServer() return false end
function isClient() return true end
function isCoopHost() return false end

SandboxVars = { PermadeathLock = {} }

local SCREEN_W, SCREEN_H = 1920, 1080
function getCore()
    return {
        getScreenWidth = function() return SCREEN_W end,
        getScreenHeight = function() return SCREEN_H end,
    }
end

function getPlayer() return nil end
function sendClientCommand() end

UIFont = { Small = "small" }

-- The height of a line of UIFont.Small. The game's UI Scaling setting moves
-- this, and every band in the panel is supposed to be sized from it, so the
-- whole matrix below is run at several values. At 2x scale a panel built
-- around fixed pixel constants has its status line, column titles and first
-- row drawn on top of each other and its bottom buttons cut off by the frame.
local TEXT_HEIGHT = 14
function getTextManager()
    return {
        getFontHeight = function() return TEXT_HEIGHT end,
        -- Close enough to a proportional font for layout arithmetic: the panel
        -- only ever asks how wide a string is relative to the space it has.
        MeasureStringX = function(_, _, text)
            return math.floor(#tostring(text) * TEXT_HEIGHT * 0.5)
        end,
    }
end

--------------------------------------------------------------------------------
-- the smallest ISUIElement that the panel can be laid out against
--------------------------------------------------------------------------------

local function element(x, y, width, height)
    local self = { x = x or 0, y = y or 0, width = width or 0, height = height or 0 }
    function self:setX(v) self.x = v end
    function self:setY(v) self.y = v end
    function self:setWidth(v) self.width = v end
    function self:setHeight(v) self.height = v end
    function self:getX() return self.x end
    function self:getY() return self.y end
    function self:getWidth() return self.width end
    function self:getHeight() return self.height end
    function self:setName(v) self.name = v end
    return self
end

--- A widget the panel calls initialise/instantiate on. Kept separate from the
--- window, which inherits those from ISCollapsableWindow: putting them on the
--- instance would shadow the base class and the window would never build its
--- children.
local function widget(x, y, width, height)
    local self = element(x, y, width, height)
    function self:initialise() end
    function self:instantiate() end
    return self
end

ISLabel = {}
function ISLabel:new(x, y, height, name)
    local label = widget(x, y, 0, height)
    label.name = name
    return label
end

ISButton = {}
function ISButton:new(x, y, width, height, label)
    local button = widget(x, y, width, height)
    button.label = label
    return button
end

ISScrollingListBox = {}
function ISScrollingListBox:new(x, y, width, height)
    local list = widget(x, y, width, height)
    list.items = {}
    list.selected = 0
    list.itemheight = 24

    function list:clear() self.items = {} end
    function list:addItem(text, item)
        self.items[#self.items + 1] = { text = text, item = item }
        return self.items[#self.items]
    end

    -- The real one builds its scrollbar here, sized and positioned from
    -- whatever the box measures at this instant, and never moves it again. A
    -- box built at 10x10 therefore gets a 10px bar at x = -7 and rows that do
    -- not appear until the window is dragged to a new size. Recording the
    -- measurements taken at this moment is what makes that visible offline.
    function list:initialise()
        self.builtAtWidth = self.width
        self.builtAtHeight = self.height
        self.vscroll = widget(self.width - 17, 0, 17, self.height)
    end

    return list
end

ISCollapsableWindow = {}
ISCollapsableWindow.__index = ISCollapsableWindow

function ISCollapsableWindow:derive(name)
    local derived = setmetatable({}, self)
    self.__index = self
    derived.Type = name
    return derived
end

function ISCollapsableWindow:new(x, y, width, height)
    local window = setmetatable(element(x, y, width, height), self)
    self.__index = self
    window.children = {}
    return window
end

-- The real one is max(16, FONT_HGT_SMALL + 1), so it scales too.
function ISCollapsableWindow:titleBarHeight() return math.max(16, TEXT_HEIGHT + 1) end
function ISCollapsableWindow:createChildren() end
function ISCollapsableWindow:initialise() self:createChildren() end
function ISCollapsableWindow:instantiate() end
function ISCollapsableWindow:addChild(child) self.children[#self.children + 1] = child end
function ISCollapsableWindow:setTitle(title) self.title = title end
function ISCollapsableWindow:setResizable() end
function ISCollapsableWindow:setVisible() end
function ISCollapsableWindow:addToUIManager() end
function ISCollapsableWindow:removeFromUIManager() end
function ISCollapsableWindow:close() end
function ISCollapsableWindow:prerender() end
function ISCollapsableWindow:onResize() end
function ISCollapsableWindow:drawText() end
function ISCollapsableWindow:drawRect() end
function ISCollapsableWindow:drawRectBorder() end

--------------------------------------------------------------------------------

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
dofile("PZMods/PermadeathLock/42/media/lua/client/PermadeathLock_AdminUI.lua")

local failures = 0
local function check(label, ok, detail)
    if ok then
        io.write(string.format("ok    %s\n", label))
    else
        failures = failures + 1
        io.write(string.format("FAIL  %-56s %s\n", label, detail or ""))
    end
end

--- Every geometric promise the panel makes, checked against one built window.
---@param width integer
---@param height integer
local function checkLayout(width, height)
    local window = PermadeathLockUI:new(0, 0, width, height)
    window:initialise()

    local label = string.format("%dx%d", width, height)
    local status, list = window.status, window.list
    local first, second = window.pardonBtn, window.refreshBtn

    local function below(name, upper, upperBottom, lower, lowerTop)
        check(label .. ": " .. name,
            lowerTop >= upperBottom,
            string.format("%s ends at %d, %s starts at %d", upper, upperBottom, lower, lowerTop))
    end

    below("status clears the title bar", "title bar", window:titleBarHeight(), "status", status.y)
    -- Guarded so a panel with no column titles still gets measured rather than
    -- taking the harness down before the interesting checks below it run.
    if window.headerY ~= nil then
        below("column titles clear the status line", "status", status.y + status.height,
            "titles", window.headerY)
        below("the list clears the column titles", "titles", window.headerY, "list", list.y)
    else
        below("the list clears the status line", "status", status.y + status.height,
            "list", list.y)
    end
    below("the buttons clear the list", "list", list.y + list.height, "buttons", first.y)
    below("the second row clears the first", "row 1", first.y + first.height, "row 2", second.y)

    -- ISCollapsableWindow draws a 6px resize strip along the bottom edge and a
    -- 10px grab handle in the corner. Anything reaching into either is under it.
    check(label .. ": the last row clears the resize strip",
        second.y + second.height <= height - 6,
        string.format("row 2 ends at %d, frame is %d", second.y + second.height, height))
    check(label .. ": the corner button clears the grab handle",
        window.clearBtn.x + window.clearBtn.width <= width - 6,
        string.format("button ends at %d, frame is %d", window.clearBtn.x + window.clearBtn.width, width))

    check(label .. ": the list fits the frame",
        list.x >= 0 and list.x + list.width <= width,
        string.format("list spans %d..%d of %d", list.x, list.x + list.width, width))
    check(label .. ": the list has room for rows",
        list.height >= list.itemheight * 2,
        "list height " .. list.height .. ", rows are " .. tostring(list.itemheight))

    -- The bands must be tall enough for the text inside them. This is the whole
    -- point: at a large UI scale, glyphs drawn in a band shorter than they are
    -- spill into whatever is above and below.
    check(label .. ": the status band holds its text",
        status.height >= TEXT_HEIGHT,
        "band " .. status.height .. ", text " .. TEXT_HEIGHT)
    check(label .. ": a list row holds its text",
        (list.itemheight or 0) >= TEXT_HEIGHT,
        "row " .. tostring(list.itemheight) .. ", text " .. TEXT_HEIGHT)
    check(label .. ": a button holds its text",
        first.height >= TEXT_HEIGHT,
        "button " .. first.height .. ", text " .. TEXT_HEIGHT)
    if window.headerY ~= nil then
        check(label .. ": the column titles hold their text",
            list.y - window.headerY >= TEXT_HEIGHT,
            "band " .. (list.y - window.headerY) .. ", text " .. TEXT_HEIGHT)
    end

    -- REGRESSION: the list used to be built at a 10x10 placeholder and resized
    -- afterwards. ISScrollingListBox lays its scrollbar out when it is built,
    -- so the bar ended up as a sliver off the left edge and the rows were not
    -- reachable until the window was resized by hand.
    check(label .. ": the list is built at its real size",
        list.builtAtWidth == list.width and list.builtAtHeight == list.height,
        string.format("built %sx%s, now %dx%d",
            tostring(list.builtAtWidth), tostring(list.builtAtHeight), list.width, list.height))

    local bar = list.vscroll
    check(label .. ": the scrollbar sits on the list's right edge",
        bar ~= nil and bar.x + bar.width == list.width,
        bar and ("bar ends at " .. (bar.x + bar.width) .. ", list is " .. list.width) or "no bar")
    check(label .. ": the scrollbar spans the list",
        bar ~= nil and bar.height == list.height,
        bar and ("bar " .. bar.height .. ", list " .. list.height) or "no bar")

    -- Buttons must not overlap each other along a row.
    local row = { window.pardonBtn, window.reviveBtn, window.giveBtn, window.takeBtn }
    local clear = true
    for i = 2, #row do
        if row[i].x < row[i - 1].x + row[i - 1].width then clear = false end
    end
    check(label .. ": buttons in a row do not overlap", clear)

    return window
end

--- The whole matrix at one UI scale, starting from the size the panel picks
--- for itself so the defaults are covered as well as the extremes.
---@param textHeight integer
local function checkScale(textHeight)
    TEXT_HEIGHT = textHeight
    io.write(string.format("\n-- UI text %dpx --\n", textHeight))

    local window = PermadeathLockUI.open()
    checkLayout(window.width, window.height)
    PermadeathLockUI.instance = nil

    checkLayout(window.minimumWidth or 640, window.minimumHeight or 320)
    checkLayout(1500, 950)
end

io.write("-- freshly opened, at a range of UI scales --\n")
checkScale(12)   -- smallest sensible
checkScale(14)   -- 1x
checkScale(20)
checkScale(28)   -- roughly 2x, which is what broke it
checkScale(40)

TEXT_HEIGHT = 28
io.write("\n-- after being dragged to a new size --\n")
local dragged = checkLayout(900, 700)
dragged.width, dragged.height = 1400, 900
dragged:onResize()
check("dragged: the list follows the frame",
    dragged.list.x + dragged.list.width <= 1400 and dragged.list.width > 1000,
    "list width " .. dragged.list.width)
check("dragged: the buttons follow the frame",
    dragged.refreshBtn.y + dragged.refreshBtn.height <= 900 - 6,
    "row 2 ends at " .. (dragged.refreshBtn.y + dragged.refreshBtn.height))
check("dragged: the corner button follows the frame",
    dragged.clearBtn.x + dragged.clearBtn.width <= 1400 - 6,
    "button ends at " .. (dragged.clearBtn.x + dragged.clearBtn.width))

--------------------------------------------------------------------------------
io.write("\n-- columns give themselves up as the window narrows --\n")

TEXT_HEIGHT = 14

---@param width number
---@return table<string, boolean> shown, number count
local function shownAt(width)
    local shown = {}
    local columns = PermadeathLockUI.columnsFor(width)
    for _, column in ipairs(columns) do shown[column.key] = true end
    return shown, #columns
end

local _, wideCount = shownAt(1400)
check("everything is shown when there is room", wideCount, 6)

-- The point of the exercise: dragging it narrow must lose columns, not squash
-- them into each other.
local _, midCount = shownAt(560)
local _, tightCount = shownAt(380)
check("a narrower panel shows fewer", midCount < wideCount, true)
check("a narrow one fewer still", tightCount < midCount, true)

-- Whatever else goes, these two stay: a roster with no names is not a roster,
-- and the state is the whole reason an admin opened it.
local tight = shownAt(380)
check("the name survives to the narrowest width", tight.name, true)
check("and so does the state", tight.state, true)

-- Least useful first, and in a stable order - a column must not reappear as
-- the window gets smaller.
local previous = select(2, shownAt(1400))
local ok = true
for width = 1400, 360, -20 do
    local _, count = shownAt(width)
    if count > previous then ok = false end
    previous = count
end
check("columns only ever drop as it shrinks", ok, true)

-- And nothing collides at any width: each column starts after the one before.
local ordered = true
for width = 1400, 360, -20 do
    local last = -1
    for _, column in ipairs(PermadeathLockUI.columnsFor(width)) do
        if column.x <= last then ordered = false end
        last = column.x
    end
end
check("columns stay in order and apart", ordered, true)

-- The panel's own floor must be a width the columns can actually cope with.
local floor = PermadeathLockUI:new(0, 0, 100, 100).minimumWidth
local atFloor, floorCount = shownAt(floor)
check("the minimum width still shows the name", atFloor.name, true)
check("and shows something beside it", floorCount > 1, true)

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
