-- Harness: drives the /permadeath chat command parser against a stubbed ISChat.
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

function getPlayer() return { getUsername = function() return "Tester" end } end
function sendClientCommand(_, module, command, args)
    sentCommands[#sentCommands + 1] = { module = module, command = command, args = args }
end

PermadeathLockUI = { open = function() uiOpened = uiOpened + 1 end }

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")
dofile("PZMods/PermadeathLock/42/media/lua/client/PermadeathLock_Commands.lua")

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

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
