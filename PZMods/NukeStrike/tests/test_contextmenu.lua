-- The right-click way in: who is offered it, what it offers, and what it sends.
--
--     lua5.1 PZMods/NukeStrike/tests/test_contextmenu.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")

-- A connected client: the half that builds menus is live and the half that acts
-- on them is not, so every command has to go over the wire and can be captured.
stubs.install({ server = false, client = true, coop = false })

local sent = {}
function sendClientCommand(_, module, command, args)
    sent[#sent + 1] = { module = module, command = command, args = args }
end

local admin = true
stubs.player = {
    isAccessLevel = function(_, level) return admin and level == "admin" end,
    getX = function() return 0 end,
    getY = function() return 0 end,
}

dofile("PZMods/NukeStrike/42/media/lua/shared/NukeStrike_Shared.lua")
dofile("PZMods/NukeStrike/42/media/lua/client/NukeStrike_ContextMenu.lua")

local NS = NukeStrike
local check, isTrue = stubs.check, stubs.checkTrue

SandboxVars.NukeStrike.Enabled = true
SandboxVars.NukeStrike.AdminOnly = true

local fill = stubs.registered["OnFillWorldObjectContextMenu"][1]

--- A patch of ground with something standing on it, as the menu is built from.
local function ground(x, y)
    local square = { getX = function() return x end, getY = function() return y end }
    return { { getSquare = function() return square end } }
end

--- Build the menu and hand back the Nuke Strike submenu, if there is one.
local function build(objects, test)
    local context = stubs.newContextMenu()
    fill(0, context, objects, test == true)

    for _, option in ipairs(context.options) do
        if option.name == "Nuke Strike" then return option.sub, context end
    end
    return nil, context
end

--------------------------------------------------------------------------------
-- who sees it
--------------------------------------------------------------------------------

isTrue("an admin gets the menu", build(ground(10500, 9500)) ~= nil)

admin = false
check("a plain player does not", build(ground(10500, 9500)), nil)

stubs.debug = true
isTrue("but debug mode does", build(ground(10500, 9500)) ~= nil)
stubs.debug = false

SandboxVars.NukeStrike.AdminOnly = false
isTrue("and so does turning admin-only off", build(ground(10500, 9500)) ~= nil)
SandboxVars.NukeStrike.AdminOnly = true
admin = true

SandboxVars.NukeStrike.Enabled = false
check("a disabled mod offers nothing", build(ground(10500, 9500)), nil)
SandboxVars.NukeStrike.Enabled = true

--------------------------------------------------------------------------------
-- when it is offered
--------------------------------------------------------------------------------

check("the dry run that measures the menu adds nothing",
    build(ground(10500, 9500), true), nil)
check("empty ground offers nothing", build({}), nil)
check("an object with no square offers nothing",
    build({ { getSquare = function() return nil end } }), nil)

--------------------------------------------------------------------------------
-- what it offers
--------------------------------------------------------------------------------

local menu = build(ground(10500, 9500))
check("three ways to use it", #menu.options, 3)
isTrue("the coordinates are on the label",
    string.find(menu.options[1].name, "10500, 9500", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- what it sends
--------------------------------------------------------------------------------

local function click(option)
    sent = {}
    option.onClick(option.target, option.a, option.b)
    return sent[1]
end

local plain = click(menu.options[1])
check("the module", plain.module, NS.MODULE)
check("the command", plain.command, "detonate")
check("the x it clicked", plain.args.x, 10500)
check("the y it clicked", plain.args.y, 9500)
check("no die is rolled", plain.args.roll, false)
check("and the sirens still run", plain.args.immediate, false)

check("the second option rolls for it", click(menu.options[2]).args.roll, true)
check("the third skips the warning", click(menu.options[3]).args.immediate, true)

--------------------------------------------------------------------------------
-- when the menu system itself misbehaves
--
-- Right-click is shared ground. A handler that throws part-way through, or that
-- leaves a parent option pointing at a submenu that never arrived, takes the
-- context menu out for EVERY mod. These check that this one cannot.
--------------------------------------------------------------------------------

--- Build against a context whose submenu creation fails.
local function buildWithBrokenSubmenu()
    local realGetNew = ISContextMenu.getNew
    ISContextMenu.getNew = function() return nil end
    local context = stubs.newContextMenu()
    local ok, err = pcall(fill, 0, context, ground(1, 2), false)
    ISContextMenu.getNew = realGetNew
    return ok, err, context
end

local ok, err, context = buildWithBrokenSubmenu()
isTrue("a submenu that cannot be created does not throw", ok)
if not ok then print("   error was: " .. tostring(err)) end
for _, option in ipairs(context.options) do
    if option.name == "Nuke Strike" then
        isTrue("and the option it left behind is disabled, not dangling",
            option.sub == nil and option.notAvailable == true)
    end
end

--- Build against a context that throws the moment it is touched.
local function buildWithBrokenContext()
    local context = stubs.newContextMenu()
    context.addOption = function() error("the menu system said no") end
    return pcall(fill, 0, context, ground(3, 4), false)
end

isTrue("a context that throws does not take the handler with it",
    (buildWithBrokenContext()))

-- NS.try gives up on a call after it fails once, so the damage is bounded to
-- the first right-click rather than repeating for every one after it.
isTrue("and the mod stops trying after that", NS.isDead("world context menu"))

local afterFailure = stubs.newContextMenu()
fill(0, afterFailure, ground(5, 6), false)
check("so later menus are left completely alone", #afterFailure.options, 0)

stubs.finish("test_contextmenu")
