-- Shared stubs for the offline tests.
--
-- Enough of the game's globals to let the mod files load and run outside Project
-- Zomboid. Anything the tests actually assert against is a real implementation;
-- everything else is just present so `dofile` does not fall over.

local stubs = {}

--- Install the globals. `flags` picks the game mode: {server=, client=, coop=}.
---@param flags table
---@return table registry of hooked event names, and the sandbox table
function stubs.install(flags)
    flags = flags or {}

    function isServer() return flags.server == true end
    function isClient() return flags.client == true end
    function isCoopHost() return flags.coop == true end

    function getTimestamp() return 1700000000 end
    function getTimestampMs() return 1700000000000 end

    -- Deterministic, so a test that rolls a die gets the same answer twice.
    math.randomseed(4)
    function ZombRand(n) return math.random(0, n - 1) end

    SandboxVars = { NukeStrike = {} }

    stubs.hours = 0
    function getGameTime()
        return { getWorldAgeHours = function() return stubs.hours end }
    end

    stubs.modData = {}
    ModData = {
        getOrCreate = function(key)
            stubs.modData[key] = stubs.modData[key] or {}
            return stubs.modData[key]
        end,
        transmit = function() end,
    }

    stubs.printed = {}
    local realPrint = print
    function print(text) stubs.printed[#stubs.printed + 1] = tostring(text) end
    stubs.realPrint = realPrint

    stubs.registered = {}
    Events = setmetatable({}, {
        __index = function(t, name)
            local slot = {
                Add = function(_, fn)
                    stubs.registered[name] = stubs.registered[name] or {}
                    table.insert(stubs.registered[name], fn)
                end,
                Remove = function() end,
            }
            -- Events.X.Add(fn) passes fn as the first argument, not self.
            slot.Add = function(fn)
                stubs.registered[name] = stubs.registered[name] or {}
                table.insert(stubs.registered[name], fn)
            end
            rawset(t, name, slot)
            return slot
        end,
    })

    -- Client-side furniture.
    ISChat = { onCommandEntered = function() end, instance = nil }
    ISUIElement = {
        derive = function(_, name)
            local class = {}
            class.__index = class
            class.name = name
            return class
        end,
        new = function(_, x, y, w, h) return { x = x, y = y, width = w, height = h } end,
    }
    function getCore()
        return { getScreenWidth = function() return 1920 end,
                 getScreenHeight = function() return 1080 end }
    end
    function getText(key) return key end
    function getPlayer() return stubs.player end
    function getSpecificPlayer() return stubs.player end
    function isDebugEnabled() return stubs.debug == true end

    -- A context menu that records what was added to it.
    function stubs.newContextMenu()
        local menu = { options = {} }
        function menu:addOption(name, target, onClick, a, b)
            local entry = { name = name, target = target, onClick = onClick, a = a, b = b }
            table.insert(self.options, entry)
            return entry
        end
        function menu:addSubMenu(option, sub) option.sub = sub end
        return menu
    end
    ISContextMenu = { getNew = function() return stubs.newContextMenu() end }
    -- No world: every square is "not loaded", which is exactly the case the
    -- blast engine has to survive without complaining.
    function getCell() return stubs.cell end
    function getOnlinePlayers() return nil end
    function getSoundManager() return nil end
    function processGeneralMessage() end
    function instanceof() return false end
    UIFont = { Large = 1, Small = 2, Medium = 3 }
    BodyPartType = { Torso_Upper = 1 }

    return stubs
end

--- Load the mod, in the order the game loads it: shared first, then each folder
--- alphabetically.
---@param base string? path to the lua folder
function stubs.loadMod(base)
    base = base or "PZMods/NukeStrike/42/media/lua/"
    dofile(base .. "shared/NukeStrike_Shared.lua")
    dofile(base .. "server/NukeStrike_Blast.lua")
    dofile(base .. "server/NukeStrike_Server.lua")
    dofile(base .. "server/NukeStrike_Zones.lua")
    dofile(base .. "client/NukeStrike_Client.lua")
    dofile(base .. "client/NukeStrike_Commands.lua")
    dofile(base .. "client/NukeStrike_ContextMenu.lua")
end

--------------------------------------------------------------------------------
-- assertions
--------------------------------------------------------------------------------

local failures = 0
local checks = 0

function stubs.check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL %s: got %s, wanted %s\n",
            label, tostring(got), tostring(want)))
    end
end

function stubs.checkNear(label, got, want, tolerance)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > (tolerance or 1e-6) then
        failures = failures + 1
        io.write(string.format("FAIL %s: got %s, wanted about %s\n",
            label, tostring(got), tostring(want)))
    end
end

function stubs.checkTrue(label, got)
    stubs.check(label, got and true or false, true)
end

--- Print the tally and exit non-zero if anything failed.
---@param name string
function stubs.finish(name)
    if failures == 0 then
        io.write(string.format("%s: %d checks passed\n", name, checks))
        os.exit(0)
    end
    io.write(string.format("%s: %d of %d checks FAILED\n", name, failures, checks))
    os.exit(1)
end

return stubs
