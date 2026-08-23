--[[
    Permadeath Lock - /fate chat commands.

    The game has no hook for adding server-side chat commands, so the client
    intercepts the typed line and forwards it. Anyone can type it; the server
    checks the sender's access level before doing anything, so this file grants
    no privilege by itself.
]]

if not PermadeathLock.isClientSide() then return end

local PL = PermadeathLock

-- /fate is the one to type; the rest are kept working on purpose.
--
-- /permadeath was the command for every release up to now, and it is in every
-- server's admin notes and every screenshot anyone has taken. Dropping it to
-- tidy up the naming would break all of that for no gain to anybody - an alias
-- costs one line.
local PREFIXES = {
    ["/fate"] = true,
    ["/permadeath"] = true,
    ["/pd"] = true,
}

---@param text string
---@return string[]
local function words(text)
    local out = {}
    for word in string.gmatch(text, "%S+") do
        out[#out + 1] = word
    end
    return out
end

--- Everything after the subcommand, as one username.
---
--- Project Zomboid allows spaces in usernames, and people quote them. Taking
--- parts[3] on its own got both wrong, in its own way each time:
---
---     /fate pardon Willy Guggenheim    -> a player called "Willy"
---     /fate pardon "Willy Guggenheim"  -> a player called '"Willy'
---
--- Both answered "X is not on the death list", which reads as the death list
--- being wrong rather than the name never having arrived.
---@param parts string[]
---@return string? target
local function targetFrom(parts)
    if parts[3] == nil then return nil end

    local rest = {}
    for i = 3, #parts do rest[#rest + 1] = parts[i] end
    local target = table.concat(rest, " ")

    -- One matching pair of surrounding quotes, if they typed them.
    local unquoted = string.match(target, '^"(.*)"$') or string.match(target, "^'(.*)'$")
    return unquoted or target
end

local originalOnCommandEntered = ISChat.onCommandEntered

function ISChat:onCommandEntered()
    local instance = ISChat.instance
    local entry = instance and instance.textEntry
    local text = entry and entry:getInternalText() or ""
    local parts = words(text)

    if parts[1] == nil or not PREFIXES[string.lower(parts[1])] then
        return originalOnCommandEntered(self)
    end

    local player = getPlayer()
    if player ~= nil then
        local sub = parts[2] and string.lower(parts[2]) or nil

        if sub == "ui" then
            -- Opened here rather than round-tripped through the server. The
            -- panel is a view: it asks the server for the list the moment it
            -- opens, and the server refuses a non-admin, so nothing is granted
            -- by letting the client open its own window.
            --
            -- This interception went missing in 1.3.0, and the symptom was
            -- confusing: the server has no 'ui' subcommand, so the forwarded
            -- word fell through to the help text and the panel never appeared.
            if PermadeathLockUI ~= nil then
                PermadeathLockUI.open()
            end
        else
            sendClientCommand(player, PL.MODULE, "admin", {
                sub = parts[2],
                target = targetFrom(parts),
            })
        end
    end

    instance:logChatCommand(text)
    entry:clear()
    instance:unfocus()
end
