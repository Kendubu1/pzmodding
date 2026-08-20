--[[
    Permadeath Lock - /permadeath chat commands.

    The game has no hook for adding server-side chat commands, so the client
    intercepts the typed line and forwards it. Anyone can type it; the server
    checks the sender's access level before doing anything, so this file grants
    no privilege by itself.
]]

if not PermadeathLock.isClientSide() then return end

local PL = PermadeathLock

local PREFIXES = {
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
                target = parts[3],
            })
        end
    end

    instance:logChatCommand(text)
    entry:clear()
    instance:unfocus()
end
