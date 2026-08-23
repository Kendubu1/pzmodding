-- Harness: the translation files, checked as data rather than as text.
--
-- Every failure this catches shows up in game the same way: a raw key on the
-- screen where a sentence should be. That is invisible from the repo and
-- obvious to a player, which is the worst combination, and it has cost this mod
-- three separate releases:
--
--   * an IGUI_EN table in a file named IGUI_EN.txt, which the game never reads
--     (it has to be IG_UI_EN.txt)
--   * a key with a dot in it written bare - ItemName_Base.FateToken = "..." -
--     which is not valid table syntax and takes the whole file down with it
--   * a sandbox option pointing at a translation key nobody wrote
--
-- Each of those is now a failing test instead of a screenshot.

local ROOT = "PZMods/PermadeathLock/"
-- Three roots, because which one the Java translator reads is not the same
-- question as which one the Lua loader reads, and getting it wrong is silent:
-- the game shows the key instead of the sentence and says nothing. Identical
-- copies in all three cost a few kilobytes; the checks below keep them in step.
local COMMON = ROOT .. "common/media/lua/shared/Translate/EN/"
local VERSIONED = ROOT .. "42/media/lua/shared/Translate/EN/"
local BARE = ROOT .. "media/lua/shared/Translate/EN/"

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-54s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-54s %s\n", label, tostring(got)))
    end
end

local function read(path)
    local handle = io.open(path, "r")
    if handle == nil then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

--- The same, with any probe marker removed.
---
--- tools/translation_probe.py stamps a different tag into each copy so that one
--- boot of the game reveals which folder it actually reads. The copies are then
--- deliberately NOT identical, and the identity checks below still have to mean
--- something in that state.
---@param path string
---@return string?
local function readUnstamped(path)
    local text = read(path)
    if text == nil then return nil end
    return (string.gsub(text, " ?%[[a-z0-9]+%] ?", " "))
end

--- Load one translation file and hand back the table it declares.
---@param path string
---@param name string the global it assigns, e.g. "Sandbox_EN"
---@return table? entries, string? err
local function load(path, name)
    local text = read(path)
    if text == nil then return nil, "missing" end

    -- The game reads these with its own parser, but the syntax it accepts is
    -- Lua's. Anything real Lua rejects is a file the game will not read either.
    local chunk, err = loadstring(text .. "\nreturn " .. name)
    if chunk == nil then return nil, err end

    local ok, result = pcall(chunk)
    if not ok then return nil, tostring(result) end
    return result
end

local FILES = {
    { file = "Sandbox_EN.txt",  table = "Sandbox_EN" },
    { file = "IG_UI_EN.txt",    table = "IGUI_EN" },
    { file = "ItemName_EN.txt", table = "ItemName_EN" },
    { file = "Tooltip_EN.txt",  table = "Tooltip_EN" },
}

--------------------------------------------------------------------------------
io.write("-- every file parses, and declares the table the game looks for --\n")

local loaded = {}
for _, spec in ipairs(FILES) do
    local entries, err = load(COMMON .. spec.file, spec.table)
    check(spec.file .. " parses", entries ~= nil, true)
    if entries == nil then io.write("        " .. tostring(err) .. "\n") end
    loaded[spec.table] = entries
end

-- The one that is only ever wrong by being spelled the obvious way.
check("the IGUI table lives in IG_UI_EN.txt", read(COMMON .. "IG_UI_EN.txt") ~= nil, true)
check("and there is no IGUI_EN.txt to be ignored", read(COMMON .. "IGUI_EN.txt"), nil)

--------------------------------------------------------------------------------
io.write("\n-- shipped in both places the game might look --\n")

-- Nothing here can settle which root the game actually reads, and being wrong
-- looks like a raw key on a player's screen. All three are shipped; this keeps
-- them from drifting apart.
for _, spec in ipairs(FILES) do
    check(spec.file .. " matches the 42/ copy",
        readUnstamped(VERSIONED .. spec.file), readUnstamped(COMMON .. spec.file))
    check(spec.file .. " matches the mod-root copy",
        readUnstamped(BARE .. spec.file), readUnstamped(COMMON .. spec.file))
end

--------------------------------------------------------------------------------
io.write("\n-- every sandbox option has a label and a tooltip --\n")

local options = read(ROOT .. "42/media/sandbox-options.txt") or ""
local sandbox = loaded["Sandbox_EN"] or {}

check("the options page itself is named", sandbox["Sandbox_PermadeathLock"] ~= nil, true)

local count = 0
for key in string.gmatch(options, "translation%s*=%s*([A-Za-z_]+)") do
    count = count + 1
    check(key .. " has a label", sandbox["Sandbox_" .. key] ~= nil, true)
    check(key .. " has a tooltip", sandbox["Sandbox_" .. key .. "_tooltip"] ~= nil, true)
end
check("options were actually found to check", count > 0, true)

-- An enum renders one entry per value, numbered from 1. A missing one shows the
-- raw key in the dropdown.
for name, values in string.gmatch(options, "valueTranslation%s*=%s*([A-Za-z_]+)[^}]-numValues%s*=%s*(%d+)") do
    for i = 1, tonumber(values) do
        check(name .. i .. " is named", sandbox["Sandbox_" .. name .. i] ~= nil, true)
    end
end
-- numValues usually precedes valueTranslation, so match that order too.
for values, name in string.gmatch(options, "numValues%s*=%s*(%d+)[^}]-valueTranslation%s*=%s*([A-Za-z_]+)") do
    for i = 1, tonumber(values) do
        check(name .. i .. " is named", sandbox["Sandbox_" .. name .. i] ~= nil, true)
    end
end

--------------------------------------------------------------------------------
io.write("\n-- every key the Lua asks for exists --\n")

local igui = loaded["IGUI_EN"] or {}
local used = {}
local function scan(path)
    local text = read(path)
    if text == nil then return end
    for key in string.gmatch(text, "(IGUI_PermadeathLock_[A-Za-z_]+)") do used[key] = true end
end
for _, file in ipairs({
    "42/media/lua/client/PermadeathLock_Client.lua",
    "42/media/lua/client/PermadeathLock_AdminUI.lua",
    "42/media/lua/client/PermadeathLock_TokenMenu.lua",
    "42/media/lua/server/PermadeathLock_Server.lua",
}) do scan(ROOT .. file) end

local checked = 0
for key in pairs(used) do
    checked = checked + 1
    check(key .. " is declared", igui[key] ~= nil, true)
end
check("keys were actually found to check", checked > 0, true)

--------------------------------------------------------------------------------
io.write("\n-- the item's own strings --\n")

local items = read(ROOT .. "42/media/scripts/PermadeathLock_items.txt") or ""
local tooltip = string.match(items, "Tooltip%s*=%s*([A-Za-z_]+)")
check("the item declares a tooltip", tooltip ~= nil, true)
check("and it is written", (loaded["Tooltip_EN"] or {})[tooltip or ""] ~= nil, true)

-- A dotted key has to be bracketed or it takes the whole file down with it.
check("the item name is keyed by full type",
    (loaded["ItemName_EN"] or {})["ItemName_Base.FateToken"], "Fate Token")

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
