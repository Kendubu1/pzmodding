-- Harness: the client half - the /fate chat command parser, and the text
-- of the notices players are shown.
--
-- It exists for one reason. Project Zomboid allows spaces in usernames, and the
-- parser took only the first word after the subcommand: "/fate pardon
-- Willy Guggenheim" pardoned a player called "Willy". Every command answered
-- "X is not on the death list", which reads as the death list being wrong.

next = nil   -- as in the other harnesses: Kahlua does not provide it

function isServer() return false end
function isClient() return true end
function isCoopHost() return false end

SandboxVars = { PermadeathLock = {} }

local typed = ""
local sentCommands = {}
local uiOpened = 0

-- Captured event handlers, so the notices can be triggered directly.
local handlers = {}
Events = setmetatable({}, { __index = function(t, name)
    local slot = {
        Add = function(fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
        Remove = function() end,
    }
    rawset(t, name, slot)
    return slot
end })

-- Whether the translation files loaded. When they have not, getText hands back
-- the key itself, which is how "IGUI_PermadeathLock_TokenSpent" ends up on a
-- player's screen at the moment they die.
local translationsLoaded = false
function getText(key)
    if translationsLoaded then return "translated: " .. key end
    return key
end

-- Every glyph is this wide, so the wrap is arithmetic a test can check.
local CHAR_W = 10
local FONT_H = 28
UIFont = { Small = "small" }
function getTextManager()
    return {
        getFontHeight = function() return FONT_H end,
        MeasureStringX = function(_, _font, str) return #str * CHAR_W end,
    }
end

local shown = {}
ISModalDialog = {}
--- The real one resizes itself to fit its text when it is built. Growing here
--- is what caught the centring being computed from the size passed in.
function ISModalDialog.CalcSize(w, h, _text) return w, h end
function ISModalDialog:new(x, y, w, h, message)
    shown[#shown + 1] = { x = x, y = y, w = w, h = h, text = message }
    return { initialise = function() end, addToUIManager = function() end }
end

function getSpecificPlayer() return getPlayer() end

local SCREEN_W, SCREEN_H = 1920, 1080
function getCore()
    return { getScreenWidth = function() return SCREEN_W end,
             getScreenHeight = function() return SCREEN_H end }
end
function processGeneralMessage() end
function forceDisconnect() end

ISChat = {}
ISChat.instance = {
    textEntry = {
        getInternalText = function() return typed end,
        clear = function() end,
    },
    logChatCommand = function() end,
    unfocus = function() end,
}
--- The wrapped original. Anything not addressed to us must reach it untouched.
local passedThrough = 0
function ISChat:onCommandEntered() passedThrough = passedThrough + 1 end

local thePlayer = { getUsername = function() return "Tester" end }
function getPlayer() return thePlayer end
function sendClientCommand(_, module, command, args)
    sentCommands[#sentCommands + 1] = { module = module, command = command, args = args }
end

PermadeathLockUI = { open = function() uiOpened = uiOpened + 1 end }

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
dofile("PZMods/PermadeathLock/42/media/lua/client/PermadeathLock_Client.lua")
dofile("PZMods/PermadeathLock/42/media/lua/client/PermadeathLock_Commands.lua")
dofile("PZMods/PermadeathLock/42/media/lua/client/PermadeathLock_TokenMenu.lua")

local onServerCommand = handlers["OnServerCommand"][1]

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-52s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-52s %s\n", label, tostring(got)))
    end
end

--- Type a line and press enter.
---@param text string
---@return table? args the admin command sent, if any
local function enter(text)
    typed = text
    sentCommands = {}
    ISChat:onCommandEntered()
    return sentCommands[1] and sentCommands[1].args or nil
end

io.write("-- usernames with spaces --\n")

local args = enter("/fate pardon Willy Guggenheim")
check("the whole name is sent, not the first word", args and args.target, "Willy Guggenheim")
check("and the subcommand is right", args and args.sub, "pardon")

args = enter("/pd revive Mary Jane Watson")
check("however many words it runs to", args and args.target, "Mary Jane Watson")

args = enter("/fate status Willy Guggenheim")
check("status takes a target too", args and args.target, "Willy Guggenheim")

io.write("\n-- quoted names, which is how people actually type them --\n")

args = enter('/fate pardon "Willy Guggenheim"')
check("double quotes are stripped", args and args.target, "Willy Guggenheim")

args = enter("/pd revive 'Willy Guggenheim'")
check("single quotes too", args and args.target, "Willy Guggenheim")

args = enter('/fate give "Bob"')
check("even round a one-word name", args and args.target, "Bob")

args = enter('/fate add Bob"s Friend')
check("a quote in the middle is left alone", args and args.target, 'Bob"s Friend')

io.write("\n-- the ordinary shapes --\n")

args = enter("/fate status")
check("no target is nil, not empty", args and args.target, nil)
check("bare status still sends", args and args.sub, "status")

args = enter("/fate clear confirm")
check("the confirm word survives", args and args.target, "confirm")

args = enter("/pd give Bob")
check("the short prefix works", args and args.sub, "give")
check("with a one-word name", args and args.target, "Bob")

args = enter("/fate   pardon   Willy   Guggenheim  ")
check("extra spacing is collapsed", args and args.target, "Willy Guggenheim")

io.write("\n-- the panel and other traffic --\n")

-- The old names still have to work. Every server running this before the
-- rename has /permadeath in its admin notes, and an alias that quietly stopped
-- being an alias is indistinguishable from the mod being broken.
for _, prefix in ipairs({ "/permadeath", "/pd", "/FATE", "/Fate" }) do
    local aliased = enter(prefix .. " pardon Willy Guggenheim")
    check(prefix .. " still reaches the server", aliased ~= nil and aliased.sub, "pardon")
    check(prefix .. " still carries the name", aliased ~= nil and aliased.target,
        "Willy Guggenheim")
end

-- And something that only looks like the command is left to the game.
check("an unrelated slash command is passed through", enter("/help"), nil)
check("a longer word starting with fate too", enter("/fatearrow x"), nil)

typed = "/fate ui"
sentCommands = {}
local before = uiOpened
ISChat:onCommandEntered()
check("ui opens the panel here", uiOpened, before + 1)
check("and sends the server nothing", #sentCommands, 0)

local was = passedThrough
typed = "hello everyone"
ISChat:onCommandEntered()
check("ordinary chat reaches the original", passedThrough, was + 1)

typed = "/help"
ISChat:onCommandEntered()
check("so do other commands", passedThrough, was + 2)

io.write("\n-- what a player is actually shown --\n")

--- Fire a server command and return the modal text it put on screen.
---@param command string
---@param args table?
---@return string?
local function notice(command, args)
    shown = {}
    onServerCommand(PermadeathLock.MODULE, command, args or {})
    return shown[1] and shown[1].text or nil
end

--- The box itself, rather than its text.
---@return table?
local function box(command, args)
    shown = {}
    onServerCommand(PermadeathLock.MODULE, command, args or {})
    return shown[1]
end

-- REGRESSION: getText returns the KEY when it cannot find an entry, so a
-- translation file the game has not read shows the player
-- "IGUI_PermadeathLock_TokenSpent" at the instant they die. Whether those files
-- are read has turned out to depend on things outside this mod; the sentence
-- has to survive them not being read.
translationsLoaded = false

local spent = notice("tokenSpent")
check("no raw key when the files are missing", string.find(spent or "", "IGUI_") == nil, true)
check("and it says what happened", string.find(spent or "", "Fate Token") ~= nil, true)

local sealed = notice("fateSealed")
check("the same for a tokenless death", string.find(sealed or "", "IGUI_") == nil, true)
check("naming the consequence", string.find(sealed or "", "pardon") ~= nil, true)

local killed = notice("blocked", { kill = true })
check("and for the block", string.find(killed or "", "IGUI_") == nil, true)

-- and a real translation still wins when there is one
translationsLoaded = true
local translated = notice("tokenSpent")
check("a loaded translation is preferred", translated, "translated: IGUI_PermadeathLock_TokenSpent")

io.write("\n-- the Fate Token's right-click menu --\n")

local fillMenu = handlers["OnFillInventoryObjectContextMenu"][1]

--- A stand-in context menu that records what was added to it.
local function menu()
    local added = {}
    return { added = added, addOption = function(_, label) added[#added + 1] = label end }
end

---@param fullType string
local function item(fullType)
    return { getFullType = function() return fullType end }
end

local m = menu()
fillMenu(0, m, { item("Base.FateToken") })
check("the entry appears on a Fate Token", m.added[1], "Bind your fate here")

m = menu()
fillMenu(0, m, { item("Base.Hammer") })
check("and on nothing else", #m.added, 0)

-- it is offered for a token inside a stack, which is how the game passes them
m = menu()
fillMenu(0, m, { { items = { item("Base.FateToken") } } })
check("a stacked token counts", m.added[1], "Bind your fate here")

-- REGRESSION: an error escaping a context menu builder takes down the WHOLE
-- menu - doors, corpses, inventory, everything. A neighbouring mod in this repo
-- did exactly that. Nothing here may throw.
local exploding = setmetatable({}, { __index = function() error("boom") end })
local ok = pcall(fillMenu, 0, exploding, { item("Base.FateToken") })
check("a broken menu does not escape the builder", ok, true)

io.write("\n-- the shape of the box --\n")

translationsLoaded = false
local b = box("tokenSpent")

-- REGRESSION: handed a paragraph on one line, the dialog runs it out sideways
-- instead of breaking it, and the box ends up the width of the screen.
check("the text is broken into lines", string.find(b.text, "\n") ~= nil, true)

local longest = 0
for lineText in string.gmatch(b.text .. "\n", "([^\n]*)\n") do
    longest = math.max(longest, #lineText * CHAR_W)
end
check("and no line overruns the box", longest <= b.w, true)

-- REGRESSION: centring was computed from the size passed in, while the dialog
-- resizes itself to fit - so a box that grew wider hung off to the right.
check("the box is centred across", b.x, math.floor((SCREEN_W - b.w) / 2))
check("and down", b.y, math.floor((SCREEN_H - b.h) / 2))
check("it fits on the screen", b.x >= 0 and b.x + b.w <= SCREEN_W, true)
check("top to bottom too", b.y >= 0 and b.y + b.h <= SCREEN_H, true)

-- and it grows with the font rather than staying at some 1x pixel count
local small = b.h
FONT_H = 14
local smaller = box("tokenSpent")
check("a smaller font gives a shorter box", smaller.h < small, true)
FONT_H = 28

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
