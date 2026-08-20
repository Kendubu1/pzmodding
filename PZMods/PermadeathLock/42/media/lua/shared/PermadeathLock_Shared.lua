--[[
    Permadeath Lock - shared definitions.

    Loaded on both the client and the server. Holds the network module name, the
    sandbox option accessors and the username handling that both sides must agree
    on, so a lookup done on the server matches a name typed by an admin.
]]

PermadeathLock = PermadeathLock or {}
local PL = PermadeathLock

PL.VERSION = "1.0.0"

-- Module name used by sendClientCommand / sendServerCommand.
PL.MODULE = "PermadeathLock"

-- Death list, written to Zomboid/Lua/ on the server. Plain text so an admin can
-- read or edit it with the server down, then use /permadeath reload.
PL.DEATH_FILE = "PermadeathLock_deaths.txt"

--- Read a sandbox option, falling back to a default if the options failed to load.
---@param name string
---@param default any
---@return any
function PL.getOption(name, default)
    local vars = SandboxVars and SandboxVars.PermadeathLock
    if vars == nil then return default end
    local value = vars[name]
    if value == nil then return default end
    return value
end

---@return boolean
function PL.isEnabled()
    return PL.getOption("Enabled", true) == true
end

--- Normalise a username into the key used by the death list.
--- Usernames are matched case-insensitively so an admin does not have to
--- reproduce the exact capitalisation when pardoning someone.
---@param username string?
---@return string? key nil when the username is missing or blank
function PL.key(username)
    if username == nil then return nil end
    local trimmed = tostring(username):match("^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" then return nil end
    return string.lower(trimmed)
end

--- Players the lock never applies to.
---@param player IsoPlayer?
---@return boolean
function PL.isExempt(player)
    if player == nil then return true end
    if PL.getOption("ExemptAdmins", true) and player:isAccessLevel("admin") then
        return true
    end
    return false
end
