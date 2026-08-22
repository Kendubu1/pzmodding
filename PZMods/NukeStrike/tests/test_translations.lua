-- Translation keys, which fail silently and in public.
--
-- getText("IGUI_Foo") returns the string "IGUI_Foo" when it cannot find the key,
-- so a misfiled entry does not error, log, or crash - it just puts a raw key on
-- the player's screen. That is exactly how IGUI_NukeStrike_Haze shipped: the
-- keys were IGUI_*, but they were sitting in a table called UI_EN, and nothing
-- anywhere said so.
--
-- The filename decides the table name, and the table name decides the prefix:
--
--     IG_UI_EN.txt    ->  IGUI_EN     ->  IGUI_*
--     UI_EN.txt       ->  UI_EN       ->  UI_*
--     Sandbox_EN.txt  ->  Sandbox_EN  ->  Sandbox_*
--
-- Note IG_UI_EN.txt, with the underscore. IGUI_EN.txt is not read.
--
--     lua5.1 PZMods/NukeStrike/tests/test_translations.lua

local stubs = dofile("PZMods/NukeStrike/tests/stubs.lua")
local check, isTrue = stubs.check, stubs.checkTrue

local MOD = "PZMods/NukeStrike/42/"
local TRANSLATE = MOD .. "media/lua/shared/Translate/EN/"

-- What each translation file must call its table, and what its keys must be
-- prefixed with. The prefix is the half that matters: IGUI_ keys sitting in a
-- table called UI_EN look perfectly reasonable in a diff, load without
-- complaint, and are invisible to getText. That was the bug.
local TABLE_FOR = {
    ["IG_UI_EN.txt"] = "IGUI_EN",
    ["UI_EN.txt"] = "UI_EN",
    ["Sandbox_EN.txt"] = "Sandbox_EN",
    ["ItemName_EN.txt"] = "ItemName_EN",
    ["Tooltip_EN.txt"] = "Tooltip_EN",
    ["ContextMenu_EN.txt"] = "ContextMenu_EN",
    ["Recipe_EN.txt"] = "Recipe_EN",
}

local PREFIX_FOR = {
    IGUI_EN = "IGUI_",
    UI_EN = "UI_",
    Sandbox_EN = "Sandbox_",
    ItemName_EN = "ItemName_",
    Tooltip_EN = "Tooltip_",
    ContextMenu_EN = "ContextMenu_",
    Recipe_EN = "Recipe_",
}

---@param path string
---@return string?
local function read(path)
    local handle = io.open(path, "r")
    if handle == nil then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

---@param command string
---@return string[]
local function shell(command)
    local out = {}
    local pipe = io.popen(command)
    if pipe == nil then return out end
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
    return out
end

--------------------------------------------------------------------------------
-- load every translation file
--------------------------------------------------------------------------------

local defined = {}   -- key -> file it came from
local files = shell("ls " .. TRANSLATE .. " 2>/dev/null")

isTrue("there are translation files at all", #files > 0)

for _, name in ipairs(files) do
    local wanted = TABLE_FOR[name]
    isTrue(name .. " is a filename the game reads", wanted ~= nil)

    if wanted ~= nil then
        local content = read(TRANSLATE .. name)
        local chunk, err = loadstring(content, name)
        isTrue(name .. " is valid Lua", chunk ~= nil)

        if chunk ~= nil then
            local env = {}
            setfenv(chunk, env)
            chunk()

            -- The trap: the right keys inside the wrong table name are invisible
            -- to getText, and nothing complains.
            local names = {}
            for k in pairs(env) do names[#names + 1] = k end
            check(name .. " defines exactly one table", #names, 1)
            check(name .. " calls its table " .. wanted, names[1], wanted)

            local prefix = PREFIX_FOR[wanted]
            for key, value in pairs(env[wanted] or {}) do
                isTrue(key .. " has a non-empty value", type(value) == "string" and value ~= "")

                -- The key has to belong to the table it is sitting in, or the
                -- game will never find it.
                local belongs = string.sub(key, 1, string.len(prefix)) == prefix
                isTrue(key .. " belongs in " .. wanted .. " (needs the " .. prefix .. " prefix)",
                    belongs)

                -- Only count it as findable if it is actually findable.
                if belongs then defined[key] = name end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- every key the mod asks for must exist
--------------------------------------------------------------------------------

local asked = {}
for _, line in ipairs(shell('grep -rho \'getText("[^"]*")\' ' .. MOD .. 'media/lua/ | sort -u')) do
    local key = string.match(line, 'getText%("([^"]*)"%)')
    if key ~= nil then asked[key] = true end
end

isTrue("the mod asks for at least one translated string", next(asked) ~= nil)

for key in pairs(asked) do
    isTrue("getText(" .. key .. ") has somewhere to find it", defined[key] ~= nil)
end

--------------------------------------------------------------------------------
-- and so must every sandbox option's label
--------------------------------------------------------------------------------

-- A sandbox option whose translation is missing shows the raw key in the options
-- menu, which is the same failure in a place people look at before they play.
local options = read(MOD .. "media/sandbox-options.txt") or ""

local pages, translations = {}, {}
for page in string.gmatch(options, "page%s*=%s*([%w_]+)") do pages[page] = true end
for name in string.gmatch(options, "translation%s*=%s*([%w_]+)") do translations[name] = true end

isTrue("the sandbox file names a page", next(pages) ~= nil)
isTrue("and some options", next(translations) ~= nil)

for page in pairs(pages) do
    isTrue("the options page Sandbox_" .. page .. " is named",
        defined["Sandbox_" .. page] ~= nil)
end

for name in pairs(translations) do
    isTrue("the option Sandbox_" .. name .. " is named", defined["Sandbox_" .. name] ~= nil)
    isTrue("and Sandbox_" .. name .. " has a tooltip",
        defined["Sandbox_" .. name .. "_tooltip"] ~= nil)
end

--------------------------------------------------------------------------------
-- nothing left over
--------------------------------------------------------------------------------

-- A key nobody asks for is usually one that was renamed and half-updated.
for key, file in pairs(defined) do
    local used = asked[key]
        or string.match(key, "^Sandbox_")   -- reached through sandbox-options.txt
    isTrue(key .. " in " .. file .. " is actually used", used ~= nil and used ~= false)
end

stubs.finish("test_translations")
