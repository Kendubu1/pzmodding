--[[
    Nuke Strike - the /nuke chat command.

    The game gives server Lua no way to register a chat command, so the client
    intercepts the typed line and forwards the intent. Anyone can type it; the
    server decides whether they are allowed to be listened to, so this file
    grants no privilege by itself.
]]

if not NukeStrike.isClientSide() then return end

local NS = NukeStrike

local PREFIXES = {
    ["/nuke"] = true,
    ["/nukestrike"] = true,
}

local HELP = {
    "Nuke Strike " .. NS.VERSION .. ":",
    "  /nuke <x> <y> [radius]   call a strike on a map coordinate",
    "  /nuke here [radius]      call one on where you are standing",
    "  /nuke player <name>      call one on a player",
    "  /nuke roll <target>      roll a d6, and only detonate on a six",
    "  /nuke now <target>       skip the warning countdown",
    "  /nuke status             what is inbound and what is still glowing",
    "  /nuke coords             print your own coordinates",
    "  /nuke abort              call back an inbound strike",
    "  /nuke clear              forget every strike, and clear the haze",
}

---@param text string
local function say(text)
    processGeneralMessage(text)
end

--- Answer the two questions that need no server: what the commands are, and
--- where you are standing. Everything else is the server's business.
---@param intent table
---@return boolean handled
local function handleLocally(intent)
    if intent.err ~= nil then
        say("Nuke Strike: " .. intent.err)
        say("Try /nuke help.")
        return true
    end

    if intent.sub == "help" then
        for _, line in ipairs(HELP) do say(line) end
        return true
    end

    if intent.sub == "coords" then
        local player = getPlayer()
        if player == nil then return true end
        say(string.format("You are at %d, %d (level %d).",
            math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())))
        return true
    end

    return false
end

local originalOnCommandEntered = ISChat.onCommandEntered

function ISChat:onCommandEntered()
    local instance = ISChat.instance
    local entry = instance and instance.textEntry
    local text = entry and entry:getInternalText() or ""
    local parts = NS.words(text)

    if parts[1] == nil or not PREFIXES[string.lower(parts[1])] then
        return originalOnCommandEntered(self)
    end

    table.remove(parts, 1)
    local intent = NS.parseCommand(parts)

    if not handleLocally(intent) then
        NS.toHost(intent.sub, intent)
    end

    instance:logChatCommand(text)
    entry:clear()
    instance:unfocus()
end
