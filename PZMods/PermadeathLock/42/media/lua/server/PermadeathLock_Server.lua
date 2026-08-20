--[[
    Permadeath Lock - server enforcement and admin commands.

    Runs on a dedicated server, and on the host of a co-op game (who runs the
    server in-process). Single player is left alone.

    Two paths record and enforce a death, because neither is sufficient alone:

      * The client reports its own death and asks for its status when it spawns.
        This is the fast, polite path: the player gets an explanation and their
        client disconnects itself.

      * A sweep over getOnlinePlayers() every in-game minute. The game exposes no
        server-side "player connected" event and no kick function to Lua, so this
        is the only enforcement a modified client cannot opt out of.

    Sandbox option EnforceKill decides what happens to a locked-out player whose
    client ignored the disconnect request: by default they are killed again, which
    is the strongest action available to server Lua.
]]

if not PermadeathLock.isServerSide() then return end

local PL = PermadeathLock
local Store = PL.Store
local MODULE = PL.MODULE

-- How many sweeps a locked-out player has survived since we asked them to leave.
---@type table<string, integer>
local strikes = {}

-- Players an admin has taken off the list while their character was still lying
-- dead in the world.
--
-- The sweep records any dead player it finds who has no record, so without this
-- a pardon is quietly undone about a minute after it is given: the corpse is
-- still standing there, the sweep sees a dead player with no record, and puts
-- them straight back on the list. The player then makes a new character and is
-- blocked by a lock they were told had been lifted.
--
-- The flag is dropped the moment they are seen alive again - that is their new
-- character, and any death after it counts normally.
---@type table<string, boolean>
local forgiven = {}

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

---@param player IsoPlayer
---@param text string
local function tell(player, text)
    sendServerCommand(player, MODULE, "message", { text = text })
end

---@param player IsoPlayer
---@param record table?
local function sendBlocked(player, record)
    sendServerCommand(player, MODULE, "blocked", {
        username = player:getUsername(),
        time = record and record.time or 0,
    })
end

---@param username string?
---@return IsoPlayer?
local function findOnline(username)
    local key = PL.key(username)
    if key == nil then return nil end

    local players = getOnlinePlayers()
    if players == nil then return nil end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player ~= nil and PL.key(player:getUsername()) == key then
            return player
        end
    end
    return nil
end

---@param timestamp integer?
---@return string
local function describeAge(timestamp)
    if timestamp == nil or timestamp == 0 then return "unknown" end
    local hours = math.floor((getTimestamp() - timestamp) / 3600)
    if hours < 1 then return "under an hour ago" end
    if hours < 48 then return hours .. "h ago" end
    return math.floor(hours / 24) .. "d ago"
end

--------------------------------------------------------------------------------
-- fate tokens
--------------------------------------------------------------------------------

-- Whether each player was carrying a token when last seen ALIVE. A death is
-- often only noticed by the sweep a second or two after the fact, by which time
-- the corpse has taken the inventory and the token is no longer reachable from
-- the player. Without this, a token that was definitely being carried finds
-- nothing and the player is wrongly locked out.
---@type table<string, boolean>
local carriedToken = {}

-- The admin waiting to see the result of a token they handed out or took back,
-- keyed by the target's username. A grant is carried out by the target's own
-- client, so the answer comes back a moment later and the panel that asked has
-- to be told to redraw then rather than immediately.
---@type table<string, string>
local tokenWatchers = {}

--- Note whether a LIVING player is carrying a token. Never called for the dead:
--- their inventory has usually moved to the corpse, and recording "no token"
--- then would erase what we learned while they were alive.
---@param player IsoPlayer
local function rememberToken(player)
    if player:isDead() then return end

    local key = PL.key(player:getUsername())
    if key == nil then return end
    carriedToken[key] = PL.findToken(player) ~= nil
end

--- Burn the token. Failure is not fatal: the save is already earned, and the
--- corpse keeping the item is a smaller problem than denying the rescue.
---@param item InventoryItem
---@return boolean removed
local function consumeFateToken(item)
    local container = item:getContainer()
    if container == nil then return false end
    container:Remove(item)
    return true
end

---@param player IsoPlayer
---@param reason string
local function recordDeath(player, reason)
    if not PL.isEnabled() then return end
    if PL.isExempt(player) then return end
    -- Already on the list: the token was either spent or not needed.
    if Store.get(player:getUsername()) ~= nil then return end

    local key = PL.key(player:getUsername())
    local token, remembered = nil, false
    if PL.getOption("FateTokenEnabled", true) then
        token = PL.findToken(player)
        remembered = carriedToken[key] == true
    end

    if token == nil and not remembered then
        local record = Store.record(player, reason)
        if record ~= nil then
            -- Tell them what just happened. Without this the only sign that the
            -- lock has closed is being thrown off the server when they try to
            -- make a new character, which reads as a crash rather than a rule.
            sendServerCommand(player, MODULE, "fateSealed", {})
            print("[PermadeathLock] " .. record.username .. " died (" .. reason
                .. ") and is locked out. No Fate Token on the body or in their last living inventory.")
        end
        carriedToken[key] = nil
        return
    end

    local burned = false
    if token ~= nil and PL.getOption("FateTokenConsume", true) then
        burned = consumeFateToken(token)
    end

    local record = Store.record(player, PL.REASON_TOKEN, true)
    if record ~= nil then
        -- A modal, not a chat line: this lands as the player dies, and the chat
        -- window is not on screen behind the death UI.
        sendServerCommand(player, MODULE, "tokenSpent", {})

        local how
        if token == nil then
            how = " Found in their last living inventory, not on the body, so it could not be removed."
        elseif burned then
            how = " Token consumed."
        else
            how = " WARNING: the token could not be removed from the body."
        end
        print("[PermadeathLock] " .. record.username .. " died holding a Fate Token; not locked out." .. how)
    end
    carriedToken[key] = nil
end

--- Hand a revived player's queued skills to the character they are now playing.
---@param player IsoPlayer
---@param record table
local function applyRestore(player, record)
    local restored, missing = 0, {}
    if PL.getOption("RestoreSkillsOnRevive", true) then
        restored, missing = Store.applySkills(player, record.skills)
    end
    Store.finishRestore(record.username)
    strikes[PL.key(record.username)] = nil
    forgiven[PL.key(record.username)] = nil

    local source = "An admin brought you back."
    if record.reason == PL.REASON_TOKEN then
        source = "Your Fate Token paid for this life."
    end

    if restored > 0 then
        tell(player, source .. " " .. restored .. " skill(s) restored from your last character.")
    else
        tell(player, source .. " Try to stay alive this time.")
    end

    print("[PermadeathLock] Restored " .. record.username .. " (" .. restored .. " skills).")
    -- Loud on purpose. A perk in the snapshot that the game no longer knows
    -- about - a mod removed since the death, or a renamed vanilla perk - is
    -- silently dropped, and the player is the last person who should have to
    -- work that out.
    if #missing > 0 then
        print("[PermadeathLock] WARNING: " .. #missing .. " perk(s) in "
            .. record.username .. "'s snapshot no longer exist and were skipped: "
            .. table.concat(missing, ", "))
    end
end

--------------------------------------------------------------------------------
-- enforcement sweep
--------------------------------------------------------------------------------

---@param player IsoPlayer
local function checkPlayer(player)
    local username = player:getUsername()
    if PL.key(username) == nil then return end

    local record = Store.get(username)

    -- Alive, and an admin has cleared them: this is the new character. Checked
    -- before the exemption, because a queued restore is owed to the player
    -- whatever their access level - an admin who becomes exempt after being
    -- revived should still get their skills back.
    if record ~= nil and record.pendingRestore and not player:isDead() then
        applyRestore(player, record)
        return
    end

    if PL.isExempt(player) then return end

    local key = PL.key(username)

    if player:isDead() then
        -- Pardoned since they died: leave the corpse alone rather than putting
        -- them back on the list they were just taken off.
        if not forgiven[key] then recordDeath(player, "died") end
        return
    end

    -- Alive: this is a new character, so an earlier pardon has done its job.
    forgiven[key] = nil

    -- Note whether they are carrying a token, so a death spotted after the
    -- corpse has taken the inventory still counts.
    rememberToken(player)

    if record == nil or not record.locked then return end

    -- Alive while locked out means they made a new character. Ask once, then act.
    strikes[key] = (strikes[key] or 0) + 1

    if strikes[key] == 1 then
        sendBlocked(player, record)
        print("[PermadeathLock] " .. username .. " rejoined after death; asked to disconnect.")
    elseif PL.getOption("EnforceKill", true) then
        player:Kill(player)
        print("[PermadeathLock] " .. username .. " ignored the block; new character killed.")
    end
end

local function sweep()
    if not PL.isEnabled() then return end

    local players = getOnlinePlayers()
    if players == nil then return end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player ~= nil then checkPlayer(player) end
    end
end

Events.EveryOneMinute.Add(sweep)

--------------------------------------------------------------------------------
-- admin commands
--------------------------------------------------------------------------------

local HELP = {
    "/permadeath status            - is the lock on, and how many are locked out",
    "/permadeath list              - show the death list",
    "/permadeath ui                - open the admin panel",
    "/permadeath give <user>       - hand a player a Fate Token",
    "/permadeath take <user>       - take a Fate Token back",
    "/permadeath revive <user>     - bring a player back, keeping their skills",
    "/permadeath pardon <user>     - let a player back in, from scratch",
    "/permadeath add <user>        - lock a player out by hand",
    "/permadeath clear confirm     - wipe the whole death list",
    "/permadeath reload            - re-read the death list from disk",
}

---@param player IsoPlayer
local function sendHelp(player)
    tell(player, "Permadeath Lock " .. PL.VERSION .. " commands:")
    for _, line in ipairs(HELP) do tell(player, line) end
end

---@param admin IsoPlayer
---@param target string?
local function commandRevive(admin, target)
    if target == nil then
        tell(admin, "Usage: /permadeath revive <username>")
        return
    end

    local record = Store.revive(target)
    if record == nil then
        tell(admin, target .. " is not on the death list.")
        return
    end
    strikes[PL.key(record.username)] = nil

    local online = findOnline(record.username)
    if online == nil then
        tell(admin, record.username .. " revived. Their skills will be restored when they next log in.")
    elseif online:isDead() then
        -- The game exposes no way to un-kill a character, so the body stays dead.
        tell(admin, record.username .. " revived, but their current character is already dead - the game gives no way")
        tell(admin, "to undo that. Tell them to reconnect; their skills will be restored to the new character.")
    else
        applyRestore(online, record)
        online:getBodyDamage():RestoreToFullHealth()
        tell(admin, record.username .. " revived, healed, and their skills restored.")
    end
    print("[PermadeathLock] " .. admin:getUsername() .. " revived " .. record.username .. ".")
end

---@param admin IsoPlayer
---@param target string?
local function commandPardon(admin, target)
    if target == nil then
        tell(admin, "Usage: /permadeath pardon <username>")
        return
    end

    if not Store.pardon(target) then
        tell(admin, target .. " is not on the death list.")
        return
    end
    local key = PL.key(target)
    strikes[key] = nil

    tell(admin, target .. " pardoned. They may rejoin with a fresh character.")

    -- Only flagged when they are online AND dead right now, which is the case
    -- the flag exists for. Setting it for an offline player would also excuse a
    -- fresh death in the minute after they reconnect.
    local online = findOnline(target)
    if online ~= nil and online:isDead() then
        forgiven[key] = true
        -- Worth saying out loud: a pardon does not stand their character back
        -- up, and an admin watching the corpse not move assumes it did nothing.
        tell(admin, "Their current character is still dead - the game gives no way to undo that. They")
        tell(admin, "need to reconnect and make a new one; they will not be blocked.")
    end

    print("[PermadeathLock] " .. admin:getUsername() .. " pardoned " .. target .. ".")
end

--- The roster, for the admin panel to render. The chat `list` command sends
--- prose about the death list; this sends a row per player, and covers everyone
--- online as well as everyone listed.
---
--- The point of including the living is that most of what an admin wants to
--- know is about people who are NOT on the death list: who is playing, who is
--- exempt and therefore cannot be locked out at all, and who is carrying a Fate
--- Token. Reading that off a list of the dead was impossible.
---@param admin IsoPlayer
local function commandListData(admin)
    local byKey, order = {}, {}

    ---@param username string?
    ---@return table? row
    local function rowFor(username)
        local key = PL.key(username)
        if key == nil then return nil end
        if byKey[key] == nil then
            byKey[key] = { username = username }
            order[#order + 1] = key
        end
        return byKey[key]
    end

    for _, record in ipairs(Store.all()) do
        local row = rowFor(record.username)
        if row ~= nil then
            local count = 0
            for _ in pairs(record.skills or {}) do count = count + 1 end
            row.listed = true
            row.age = describeAge(record.time)
            row.locked = record.locked == true
            row.pendingRestore = record.pendingRestore == true
            row.skills = count
        end
    end

    local players = getOnlinePlayers()
    if players ~= nil then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player ~= nil then
                local row = rowFor(player:getUsername())
                if row ~= nil then
                    row.online = true
                    row.dead = player:isDead()
                    row.exempt = PL.isExempt(player)
                    -- Read from the server's own view of the inventory, not
                    -- reported by the client. Offline players are left with no
                    -- token count at all rather than a made-up zero.
                    row.tokens = PL.countTokens(player)
                end
            end
        end
    end

    local rows = {}
    for _, key in ipairs(order) do
        local row = byKey[key]
        row.listed = row.listed == true
        row.online = row.online == true
        row.dead = row.dead == true
        row.exempt = row.exempt == true
        row.locked = row.locked == true
        row.pendingRestore = row.pendingRestore == true
        row.skills = row.skills or 0
        row.age = row.age or ""
        rows[#rows + 1] = row
    end

    -- Trouble first: locked out, then awaiting a restore, then anyone else on
    -- the list, then everyone who is simply playing. Alphabetical inside each
    -- group. An admin opening this wants the people needing a decision on top.
    local function rank(row)
        if row.locked then return 1 end
        if row.pendingRestore then return 2 end
        if row.listed then return 3 end
        return 4
    end
    table.sort(rows, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return string.lower(a.username) < string.lower(b.username)
    end)

    sendServerCommand(admin, MODULE, "listData", {
        version = PL.VERSION,
        enabled = PL.isEnabled(),
        tokens = PL.getOption("FateTokenEnabled", true) == true,
        rows = rows,
    })
end

--- Hand a player a Fate Token, or take one back.
---
--- Carried out by the target's own client rather than by reaching into their
--- inventory from here. In Project Zomboid a player's inventory belongs to
--- their machine; an item pushed in server-side is not reliably synced back to
--- them, and one removed server-side can reappear.
---@param admin IsoPlayer
---@param target string?
---@param give boolean
local function commandToken(admin, target, give)
    local verb = give and "give" or "take"
    if target == nil then
        tell(admin, "Usage: /permadeath " .. verb .. " <username>")
        return
    end

    if not PL.getOption("FateTokenEnabled", true) then
        tell(admin, "Fate Tokens are switched off in the sandbox settings. The item can still be")
        tell(admin, "handed out, but dying with it will not save anyone.")
    end

    local player = findOnline(target)
    if player == nil then
        tell(admin, target .. " is not online. Tokens are real items, so they have to be here to hold one.")
        return
    end

    tokenWatchers[PL.key(player:getUsername())] = admin:getUsername()
    sendServerCommand(player, MODULE, give and "giveToken" or "takeToken", {})
    print("[PermadeathLock] " .. admin:getUsername() .. " asked to " .. verb
        .. " a Fate Token " .. (give and "to " or "from ") .. player:getUsername() .. ".")
end

--- The target's client has finished adding or removing a token. Tell whichever
--- admin asked, and push them a fresh roster so the count they see is the one
--- the server can actually verify.
---@param player IsoPlayer the target, not the admin
---@param args table
local function onTokenResult(player, args)
    local key = PL.key(player:getUsername())
    if key == nil then return end

    local adminName = tokenWatchers[key]
    tokenWatchers[key] = nil
    if adminName == nil then return end

    local admin = findOnline(adminName)
    if admin == nil or not admin:isAccessLevel("admin") then return end

    -- Counted here rather than trusting the number the client sent back.
    local held = PL.countTokens(player)
    local gave = args.action == "give"

    if args.ok == true then
        tell(admin, (gave and "Gave " or "Took a Fate Token from ") .. player:getUsername()
            .. (gave and " a Fate Token." or ".") .. " They now carry " .. held .. ".")
    elseif gave then
        tell(admin, "Could not give " .. player:getUsername() .. " a Fate Token.")
    else
        tell(admin, player:getUsername() .. " has no Fate Token to take.")
    end

    commandListData(admin)
end

---@param admin IsoPlayer
local function commandList(admin)
    local all = Store.all()
    if #all == 0 then
        tell(admin, "Nobody is on the death list.")
        return
    end

    tell(admin, "Death list (" .. #all .. "):")
    for _, record in ipairs(all) do
        local state = record.locked and "locked" or "awaiting restore"
        tell(admin, " - " .. record.username .. " (" .. state .. ", " .. describeAge(record.time) .. ", " .. (record.reason or "") .. ")")
    end
end

---@param player IsoPlayer
---@param args table
local function handleAdmin(player, args)
    if not player:isAccessLevel("admin") then
        tell(player, "You need admin access to use /permadeath.")
        return
    end

    local sub = string.lower(tostring(args.sub or "status"))
    local target = args.target

    if sub == "status" then
        local state = PL.isEnabled() and "ON" or "OFF"
        tell(player, "Permadeath Lock " .. PL.VERSION .. " is " .. state .. ". " .. Store.count() .. " player(s) on the death list.")
    elseif sub == "list" then
        commandList(player)
    elseif sub == "listdata" then
        commandListData(player)
    elseif sub == "ui" then
        -- Normally the client opens the panel itself without a round trip. This
        -- branch catches an older client, and keeps the help text honest.
        sendServerCommand(player, MODULE, "openUI", {})
    elseif sub == "revive" then
        commandRevive(player, target)
    elseif sub == "pardon" then
        commandPardon(player, target)
    elseif sub == "give" then
        commandToken(player, target, true)
    elseif sub == "take" then
        commandToken(player, target, false)
    elseif sub == "add" then
        if target == nil then
            tell(player, "Usage: /permadeath add <username>")
        elseif Store.addManual(target, "added by " .. player:getUsername()) then
            tell(player, target .. " added to the death list.")
        else
            tell(player, target .. " is already on the death list.")
        end
    elseif sub == "clear" then
        if target ~= "confirm" then
            tell(player, "This wipes all " .. Store.count() .. " record(s). Run: /permadeath clear confirm")
        else
            local removed = Store.clear()
            strikes = {}
            -- Same trap as a single pardon, for everyone at once: any online
            -- player currently lying dead would be re-recorded by the next
            -- sweep, undoing the wipe a minute after it happened.
            forgiven = {}
            local players = getOnlinePlayers()
            if players ~= nil then
                for i = 0, players:size() - 1 do
                    local other = players:get(i)
                    if other ~= nil and other:isDead() then
                        forgiven[PL.key(other:getUsername())] = true
                    end
                end
            end
            tell(player, "Death list cleared (" .. removed .. " record(s) removed).")
            print("[PermadeathLock] " .. player:getUsername() .. " cleared the death list.")
        end
    elseif sub == "reload" then
        Store.load()
        tell(player, "Death list reloaded: " .. Store.count() .. " record(s).")
    else
        sendHelp(player)
    end
end

--------------------------------------------------------------------------------
-- client commands
--------------------------------------------------------------------------------

---@param module string
---@param command string
---@param player IsoPlayer
---@param args table?
local function onClientCommand(module, command, player, args)
    if module ~= MODULE or player == nil then return end
    args = args or {}

    if command == "admin" then
        -- Access is re-checked here: the client asking is never trusted.
        handleAdmin(player, args)
        return
    end

    if command == "tokenResult" then
        -- Not trusted: it only says "I am done", and everything reported back to
        -- the admin is re-read from the server's own view of the inventory. The
        -- worst a forged one can do is make an admin's panel redraw.
        onTokenResult(player, args)
        return
    end

    if not PL.isEnabled() then return end

    if command == "checkStatus" then
        local record = Store.get(player:getUsername())
        if record == nil then return end
        -- As in the sweep: a queued restore is honoured even for exempt players.
        if record.pendingRestore and not player:isDead() then
            applyRestore(player, record)
        elseif record.locked and not PL.isExempt(player) then
            sendBlocked(player, record)
        end
        return
    end

    if PL.isExempt(player) then return end

    if command == "reportDeath" then
        -- The client reports the instant it dies. If the server has not caught
        -- up yet this is the last chance to see the inventory intact, so take a
        -- snapshot either way; rememberToken is a no-op once they are dead.
        rememberToken(player)
        -- Verified against the character's real state rather than taken on trust.
        if player:isDead() then recordDeath(player, "died") end
    end
end

Events.OnClientCommand.Add(onClientCommand)

print("[PermadeathLock] Server module " .. PL.VERSION .. " loaded.")
