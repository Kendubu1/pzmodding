-- Harness: the client half - the /permadeath chat command parser, and the text
-- of the notices players are shown.
--
-- It exists for one reason. Project Zomboid allows spaces in usernames, and the
-- parser took only the first word after the subcommand: "/permadeath pardon
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

local shown = {}
ISModalDialog = {}
function ISModalDialog:new(_x, _y, _w, _h, message)
    shown[#shown + 1] = message
    return { initialise = function() end, addToUIManager = function() end }
end

function getSpecificPlayer() return getPlayer() end

function getCore()
    return { getScreenWidth = function() return 1920 end,
             getScreenHeight = function() return 1080 end }
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

-- Both the live character and its descriptor record what was written to them,
-- because writing only the live one looks right until the model is rebuilt.
local written = { live = nil, descriptor = nil }

local function visualHolder(slot)
    return {
        getHumanVisual = function()
            return { loadLastStandString = function(_, str) written[slot] = str end }
        end,
    }
end

local modelReset = 0
local thePlayer = {
    getUsername = function() return "Tester" end,
    getHumanVisual = visualHolder("live").getHumanVisual,
    getDescriptor = function() return visualHolder("descriptor") end,
    resetModelNextFrame = function() modelReset = modelReset + 1 end,
}
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

local args = enter("/permadeath pardon Willy Guggenheim")
check("the whole name is sent, not the first word", args and args.target, "Willy Guggenheim")
check("and the subcommand is right", args and args.sub, "pardon")

args = enter("/pd revive Mary Jane Watson")
check("however many words it runs to", args and args.target, "Mary Jane Watson")

args = enter("/permadeath status Willy Guggenheim")
check("status takes a target too", args and args.target, "Willy Guggenheim")

io.write("\n-- quoted names, which is how people actually type them --\n")

args = enter('/permadeath pardon "Willy Guggenheim"')
check("double quotes are stripped", args and args.target, "Willy Guggenheim")

args = enter("/pd revive 'Willy Guggenheim'")
check("single quotes too", args and args.target, "Willy Guggenheim")

args = enter('/permadeath give "Bob"')
check("even round a one-word name", args and args.target, "Bob")

args = enter('/permadeath add Bob"s Friend')
check("a quote in the middle is left alone", args and args.target, 'Bob"s Friend')

io.write("\n-- the ordinary shapes --\n")

args = enter("/permadeath status")
check("no target is nil, not empty", args and args.target, nil)
check("bare status still sends", args and args.sub, "status")

args = enter("/permadeath clear confirm")
check("the confirm word survives", args and args.target, "confirm")

args = enter("/pd give Bob")
check("the short prefix works", args and args.sub, "give")
check("with a one-word name", args and args.target, "Bob")

args = enter("/permadeath   pardon   Willy   Guggenheim  ")
check("extra spacing is collapsed", args and args.target, "Willy Guggenheim")

io.write("\n-- the panel and other traffic --\n")

typed = "/permadeath ui"
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

io.write("\n-- coming back with the old face --\n")

written = { live = nil, descriptor = nil }
modelReset = 0
onServerCommand(PermadeathLock.MODULE, "restoreLook", { visual = "FACE-DATA" })

check("the face is written to the live character", written.live, "FACE-DATA")
-- REGRESSION: writing only the live visual looked right until the first thing
-- that rebuilt the model - a tick of damage does it - and then the game
-- re-derived the model from the descriptor and the old face came back.
check("and to the descriptor it is rebuilt from", written.descriptor, "FACE-DATA")
check("and the model is refreshed", modelReset, 1)

written = { live = nil, descriptor = nil }
onServerCommand(PermadeathLock.MODULE, "restoreLook", { visual = "" })
check("an empty face is ignored", written.descriptor, nil)

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
