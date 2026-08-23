-- Harness: the key ring hook.
--
-- The mod adds the Fate Token to what a key ring will accept, by wrapping
-- vanilla's AcceptItemFunction.KeyRing rather than by retyping the item as a
-- key. Two things have to hold for that to be a good citizen: our item gets on,
-- and every other answer is still vanilla's.

next = nil   -- Kahlua has no `next`; see MODDING-NOTES section 4

function isServer() return true end
function isClient() return false end
function isCoopHost() return false end
function getTimestamp() return 1700000000 end
function print() end

SandboxVars = { PermadeathLock = {} }

local booted = {}
Events = setmetatable({}, { __index = function(t, name)
    local slot = { Add = function(fn) booted[name] = booted[name] or {}
                       table.insert(booted[name], fn) end }
    rawset(t, name, slot)
    return slot
end })

-- Vanilla's own check, near enough: keys, and a short list of other things that
-- are allowed on a ring.
local vanillaCalls = 0
local EXTRAS = { ["Base.Whistle"] = true }
AcceptItemFunction = {
    KeyRing = function(_, item)
        vanillaCalls = vanillaCalls + 1
        if item == nil then return false end
        return item.category == "Key" or EXTRAS[item.fullType] == true
    end,
}

dofile("PZMods/PermadeathLock/42/media/lua/shared/PermadeathLock_Shared.lua")

local failures = 0
local function check(label, got, want)
    if got ~= want then
        failures = failures + 1
        io.write(string.format("FAIL  %-54s got=%s want=%s\n", label, tostring(got), tostring(want)))
    else
        io.write(string.format("ok    %-54s %s\n", label, tostring(got)))
    end
end

local function item(fullType, category)
    return { fullType = fullType, category = category,
             getFullType = function(self) return self.fullType end }
end

local ring = {}
local function accepts(it) return AcceptItemFunction.KeyRing(ring, it) == true end

--------------------------------------------------------------------------------
io.write("-- what a key ring takes --\n")

check("a Fate Token goes on the ring", accepts(item("Base.FateToken", "Item")), true)
check("a house key still does", accepts(item("Base.Key1", "Key")), true)
check("so does vanilla's whistle", accepts(item("Base.Whistle", "Item")), true)
check("a hammer still does not", accepts(item("Base.Hammer", "Item")), false)
check("and nil is not a crash", accepts(nil), false)

--------------------------------------------------------------------------------
io.write("\n-- and it is a good citizen --\n")

-- Vanilla decides everything except our own item. Answering for anything else
-- would quietly undo any other mod that hooks the same function.
vanillaCalls = 0
accepts(item("Base.Hammer", "Item"))
accepts(item("Base.Key1", "Key"))
check("vanilla is still asked about other items", vanillaCalls, 2)

vanillaCalls = 0
accepts(item("Base.FateToken", "Item"))
check("but not about ours", vanillaCalls, 0)

--------------------------------------------------------------------------------
io.write("\n-- wrapping twice would double vanilla's work --\n")

-- A co-op Host runs two Lua states in one process. Within one of them the hook
-- must be idempotent, or vanilla's check runs once per wrap.
PermadeathLock.allowOnKeyRings()
PermadeathLock.allowOnKeyRings()
for _, fn in ipairs(booted["OnGameBoot"] or {}) do fn() end

vanillaCalls = 0
accepts(item("Base.Hammer", "Item"))
check("vanilla is still asked exactly once", vanillaCalls, 1)
check("and the token still gets on", accepts(item("Base.FateToken", "Item")), true)

io.write("\n")
if failures == 0 then
    io.write("all checks passed\n")
else
    io.write(failures .. " check(s) FAILED\n")
    os.exit(1)
end
