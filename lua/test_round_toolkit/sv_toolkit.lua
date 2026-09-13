local Toolkit = TEST_ROUND_TOOLKIT
local NET = "TestRoundToolkit.Action"
local TIMER = "TestRoundToolkit.Maintenance"
local session
local cooldowns = {}
local damageCooldowns = {}
local nextGlobalAction = 0

util.AddNetworkString(NET)
util.AddNetworkString("TestRoundToolkit.Weapon")
util.AddNetworkString("TestRoundToolkit.Ammo")
SetGlobalBool("test_round_toolkit_active", false)

local function message(ply, key, params)
    LANG.Msg(ply, key, params, MSG_CHAT_PLAIN)
end

local function validPlayer(ply)
    return IsValid(ply) and ply:IsPlayer()
end

local function identity(ply)
    -- Bots share SteamID64; their entity is their session identity.
    return ply:IsBot() and ply or ply:SteamID64()
end

local function validRole(index)
    if not isnumber(index) or index % 1 ~= 0 then return false end
    local role = roles.GetByIndex(index)
    -- GetByIndex returns roles.NONE for unknown IDs, not nil.
    return role ~= roles.NONE and role.index == index and not role.isAbstract
end

local function eligible(ply)
    return validPlayer(ply) and ply:IsReady() and not ply:GetForceSpec()
end

local function snapshot(ply)
    local key = identity(ply)
    if not session.players[key] then
        session.players[key] = {
            base = ply:GetBaseKarma(),
            live = ply:GetLiveKarma(),
            damage = ply:GetDamageFactor(),
            clean = ply:GetCleanRound(),
            frags = ply:Frags(),
            deaths = ply:Deaths()
        }
        if eligible(ply) then
            ply:SetFrags(0)
            ply:SetDeaths(0)
        end
    end
end

local function restorePlayer(ply, saved)
    if not validPlayer(ply) or not saved then return end
    ply:SetBaseKarma(saved.base)
    ply:SetLiveKarma(saved.live)
    ply:SetDamageFactor(saved.damage)
    ply:SetCleanRound(saved.clean)
    ply:SetFrags(saved.frags)
    ply:SetDeaths(saved.deaths)
    KARMA.Remember(ply)
end

local function neutralKarma(ply)
    ply:SetBaseKarma(1000)
    ply:SetLiveKarma(1000)
    ply:SetDamageFactor(1)
end

local function setRole(ply, index)
    if not eligible(ply) or not ply:IsTerror() or not ply:Alive() or not validRole(index) then
        return false
    end
    if ply:GetSubRole() ~= index then
        -- Remove shop weapons from the previous role, retaining ordinary map weapons.
        for _, weapon in ipairs(ply:GetWeapons()) do
            if IsValid(weapon) and istable(weapon.CanBuy) then
                ply:StripWeapon(weapon:GetClass())
            end
        end
        ply:ResetEquipment()
        ply:ResetBought()
        admin.PlayerForceRole(ply, index)
    end
    ply:SetDefaultCredits()
    session.roles[identity(ply)] = index
    return true
end

local function replenish(ply)
    if ply:IsShopper() and ply:GetCredits() < 10 then
        ply:AddCredits(99)
    end
end

local function maintain()
    if not session or not session.running or session.stopping then return end
    if gameloop.GetRoundState() ~= ROUND_ACTIVE then return end

    gameloop.StopWinChecks()
    if gameloop.GetPhaseEnd() < CurTime() + 500 then
        gameloop.SetPhaseEnd(CurTime() + 1000)
        if gameloop.IsHasteMode() then
            gameloop.SetHasteEnd(CurTime() + 1000)
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        if ply:IsReady() then
            snapshot(ply)
            if eligible(ply) then
                neutralKarma(ply)
                local key = identity(ply)
                local role = session.roles[key]
                if not role then role = ROLE_TRAITOR end
                if not validRole(role) then role = ROLE_INNOCENT end
                local needsSpawn = not ply:Alive() or ply:IsSpec()
                if needsSpawn then ply:SpawnForRound(true) end
                if ply:Alive() and ply:IsTerror() then
                    if not session.roles[key] or needsSpawn then
                        setRole(ply, role)
                    else
                        -- Keep legitimate role changes made by custom roles/addons.
                        session.roles[key] = ply:GetSubRole()
                    end
                    replenish(ply)
                end
            end
        end
    end
end

local function removeBots()
    for _, bot in ipairs(player.GetBots()) do
        bot:Kick("Test Round Toolkit")
    end
end

local function finish()
    if not session then return end
    local old = session
    session = nil
    timer.Remove(TIMER)
    SetGlobalBool("test_round_toolkit_active", false)
    local minimum = GetConVar("ttt_minimum_players")
    if old.minimum > 1 and minimum:GetInt() == 1 then
        minimum:SetInt(old.minimum)
    end
    -- Cancelling a queued request must not affect karma, scores or bots.
    if not old.running then return end
    for _, ply in ipairs(player.GetAll()) do
        restorePlayer(ply, old.players[identity(ply)])
    end
    -- Restore only the value owned by this session; retain deliberate external edits.
    local karma = GetConVar("ttt_karma")
    if karma:GetInt() == 0 then karma:SetInt(old.karma) end
    removeBots()
    if not old.stopping and gameloop.GetRoundState() == ROUND_ACTIVE then
        gameloop.StartWinChecks()
    end
end

local function activate()
    if not session or session.running or session.stopping then return end
    if gameloop.GetRoundState() ~= ROUND_ACTIVE then return end
    session.running = true
    session.karma = GetConVar("ttt_karma"):GetInt()
    for _, ply in ipairs(player.GetAll()) do
        if ply:IsReady() then snapshot(ply) end
    end
    -- Disabling karma also prevents round-end rewards, autokicks and persistence
    -- of temporary test karma. A low-ban toggle alone does not protect players.
    GetConVar("ttt_karma"):SetInt(0)
    timer.Create(TIMER, 3, 0, maintain)
end

local function beginPreparedRound()
    if not session or session.stopping or gameloop.GetRoundState() ~= ROUND_PREP then return end
    -- This is the exact timer installed by gameloop.Prepare in TTT2 v0.14.6b.
    -- Remove only this transition, then run the native role/spawn/round setup.
    timer.Remove("prep2begin")
    gameloop.Begin()
end

hook.Add("TTTPrepareRound", "TestRoundToolkit.SkipPreparation", function()
    if not session or session.stopping then return end
    local requestedSession = session
    -- Let gameloop.Prepare and all preparation hooks finish before beginning.
    timer.Simple(0, function()
        if session == requestedSession then beginPreparedRound() end
    end)
end)

local function start()
    local minimum = GetConVar("ttt_minimum_players")
    session = {players = {}, roles = {}, running = false, minimum = minimum:GetInt()}
    -- TTT2 checks this again when preparation expires. Keep its native lifecycle,
    -- but allow a single ready participant while the test session is requested.
    if session.minimum > 1 then minimum:SetInt(1) end
    SetGlobalBool("test_round_toolkit_active", true)
    if gameloop.GetRoundState() == ROUND_PREP then
        beginPreparedRound()
    elseif gameloop.GetRoundState() == ROUND_WAIT then
        gameloop.WaitingForPlayersChecker()
    end
    activate()
    maintain()
end

local administrative = {toggle = true, clean = true, bots = true, unbot = true}
local commands = {toggle = true, clean = true, bots = true, unbot = true, role = true, health = true, weapon = true}

function Toolkit.Dispatch(ply, action, value)
    if not validPlayer(ply) or not ply:IsReady() or not commands[action] then return end
    local now = CurTime()
    if now < (cooldowns[ply] or 0) then return end
    cooldowns[ply] = now + 0.35

    if administrative[action] and not admin.IsAdmin(ply) then
        message(ply, "trt_denied")
        return
    end

    if session and session.stopping then return end
    local state = gameloop.GetRoundState()
    if state ~= ROUND_WAIT and state ~= ROUND_PREP and state ~= ROUND_ACTIVE and state ~= ROUND_POST then
        message(ply, "trt_wrong_state")
        return
    end

    if action == "toggle" then
        if now < nextGlobalAction then return end
        nextGlobalAction = now + 2
        if session then
            if state == ROUND_ACTIVE then
                -- Post() cleans up asynchronously. Keep karma protected until
                -- cleanup completes, rather than exposing the final quarter-second.
                session.stopping = true
                timer.Remove(TIMER)
                SetGlobalBool("test_round_toolkit_active", false)
                admin.RoundRestart()
            else
                finish()
            end
            LANG.Msg("trt_stopped", {name = ply:Nick()}, MSG_CHAT_PLAIN)
        else
            start()
            LANG.Msg("trt_started", {name = ply:Nick()}, MSG_CHAT_PLAIN)
        end
        return
    end

    if not session or not session.running or state ~= ROUND_ACTIVE then
        message(ply, "trt_wrong_state")
        return
    end

    if action == "role" or action == "health" or action == "weapon" then
        if not eligible(ply) or not ply:Alive() or not ply:IsTerror() then
            message(ply, "trt_not_alive")
            return
        end
        if action == "weapon" then
            if not isstring(value) or #value == 0 or #value > 128
                or not string.match(value, "^[%w_%-]+$") then
                message(ply, "trt_invalid_weapon")
                return
            end
            local weapon = weapons.Get(value)
            -- Registered TTT2 weapons only; never accept arbitrary entities.
            local excluded = {weapon_fists = true, weapon_ttt_unarmed = true, bobs_blacklisted = true}
            hook.Run("TTT2ModifyShopEditorIgnoreEquip", excluded)
            -- Icon/model metadata can exist only on CLIENT (e.g. the stock shotgun).
            -- Do not apply the shop editor's visual-placeholder filter on the server.
            if not weapon or not weapon.id or not isnumber(weapon.Kind)
                or weapon.Duplicated or excluded[value]
                or string.find(value, "base", 1, true) or string.find(value, "event", 1, true) then
                message(ply, "trt_invalid_weapon")
                return
            end
            if ply:HasWeapon(value) then
                message(ply, "trt_weapon_owned")
                return
            end
            if not ply:CanCarryWeapon(weapon) then
                -- Match TTT2's pickup replacement logic, using the inherited Kind.
                -- Only drop a blocking weapon when the requested slot is actually full.
                local blocking, _, mode = GetBlockingWeapon(ply, weapon)
                if mode == SWITCHMODE_NOSPACE then
                    message(ply, "trt_weapon_drop_space")
                    return
                end
                if mode == SWITCHMODE_FULLINV or not IsValid(blocking) then
                    message(ply, "trt_weapon_slot")
                    return
                end
                if not ply:SafeDropWeapon(blocking, true) then
                    message(ply, "trt_weapon_drop_failed")
                    return
                end
                -- A weapon/addon can refuse or alter a drop; do not force capacity.
                if not ply:CanCarryWeapon(weapon) then
                    message(ply, "trt_weapon_slot")
                    return
                end
            end
            -- Use TTT2's Give override, without its unbounded equipment retry timer.
            local given = ply:Give(value)
            if not IsValid(given) or not ply:HasWeapon(value) then
                message(ply, "trt_weapon_failed")
            else
                given.wpickup_autoSelect = true
                message(ply, "trt_weapon_given", {name = value})
            end
        elseif action == "role" then
            if not validRole(value) then message(ply, "trt_invalid") return end
            snapshot(ply)
            setRole(ply, value)
        else
            if not isnumber(value) or value % 1 ~= 0 or value < 1 or value > 65535 then
                message(ply, "trt_invalid")
                return
            end
            admin.PlayerSetHealth(ply, value)
        end
        return
    end

    if now < nextGlobalAction then return end
    nextGlobalAction = now + 2
    if action == "clean" then
        -- TTT2 PostCleanupMap enters preparation. Preserve the test session and
        -- let the native lifecycle clean entities, spawn players and select roles.
        admin.RoundRestart()
    elseif action == "unbot" then
        removeBots()
    elseif action == "bots" then
        if not isnumber(value) or value % 1 ~= 0 or value < 0 or value > 63 then
            message(ply, "trt_invalid")
            return
        end
        local count = math.min(value, math.max(0, game.MaxPlayers() - #player.GetAll()))
        if count == 0 and value > 0 then message(ply, "trt_full") return end
        for _ = 1, count do RunConsoleCommand("bot") end
    end
end

-- Fixed-size protocol: no client-selected targets or arbitrary strings.
local actions = {"toggle", "role", "health", "bots", "unbot", "clean"}
net.Receive(NET, function(length, ply)
    if length ~= 19 then return end
    local action = actions[net.ReadUInt(3)]
    local value = net.ReadUInt(16)
    Toolkit.Dispatch(ply, action, value)
end)

net.Receive("TestRoundToolkit.Weapon", function(length, ply)
    if length < 16 or length > 129 * 8 then return end
    Toolkit.Dispatch(ply, "weapon", net.ReadString())
end)

net.Receive("TestRoundToolkit.Ammo", function(length, ply)
    if length < 16 or length > 129 * 8 then return end
    if not validPlayer(ply) or not ply:IsReady() then return end

    local now = CurTime()
    if now < (cooldowns[ply] or 0) then return end
    cooldowns[ply] = now + 0.35

    if not session or not session.running or gameloop.GetRoundState() ~= ROUND_ACTIVE
        or not eligible(ply) or not ply:Alive() or not ply:IsTerror() then
        message(ply, "trt_wrong_state")
        return
    end

    local class = net.ReadString()
    if #class == 0 or #class > 128 or not string.match(class, "^[%w_%-]+$") then
        message(ply, "trt_invalid_ammo")
        return
    end

    local ammo = scripted_ents.Get(class)
    if not ammo or not scripted_ents.IsBasedOn(class, "base_ammo_ttt")
        or not ammo.AutoSpawnable or not isstring(ammo.AmmoType)
        or ammo.AmmoType == "none" or not isnumber(ammo.AmmoAmount)
        or not isnumber(ammo.AmmoMax) then
        message(ply, "trt_invalid_ammo")
        return
    end

    local current = ply:GetAmmoCount(ammo.AmmoType)
    local amount = math.max(0, math.min(ammo.AmmoAmount, ammo.AmmoMax - current))
    if amount <= 0 then
        message(ply, "trt_ammo_full")
        return
    end

    ply:GiveAmmo(amount, ammo.AmmoType, true)
    message(ply, "trt_ammo_given", {name = ammo.AmmoType, amount = amount})
end)

concommand.Add("ttt_starttestround", function(ply)
    Toolkit.Dispatch(ply, "toggle")
end)

hook.Add("PlayerSay", "TestRoundToolkit.Chat", function(ply, text)
    local command, argument = string.match(string.lower(string.Trim(text)), "^!([%w_]+)%s*(.-)$")
    if not command then return end
    if command == "testround" and argument == "" then
        Toolkit.Dispatch(ply, "toggle")
    elseif session then
        local aliases = {health = "health", bot = "bots", unbot = "unbot", clean = "clean", cleanup = "clean"}
        if aliases[command] then
            Toolkit.Dispatch(ply, aliases[command], tonumber(argument))
        elseif argument == "" then
            local role = roles.GetByName(command)
            if role ~= roles.NONE and validRole(role.index) then
                Toolkit.Dispatch(ply, "role", role.index)
            end
        end
    end
end)

hook.Add("TTT2PostCleanupMap", "TestRoundToolkit.Restore", function()
    if session and session.stopping then finish() end
end)

hook.Add("TTTBeginRound", "TestRoundToolkit.Begin", function()
    if not session or session.stopping then return end
    activate()
    if not session.running then return end
    for _, ply in ipairs(player.GetAll()) do
        if eligible(ply) then
            snapshot(ply)
            local role = session.roles[identity(ply)] or ROLE_TRAITOR
            setRole(ply, validRole(role) and role or ROLE_INNOCENT)
        end
    end
    maintain()
end)

hook.Add("DoPlayerDeath", "TestRoundToolkit.DeathRole", function(ply)
    if session and session.running and gameloop.GetRoundState() == ROUND_ACTIVE and eligible(ply) then
        session.roles[identity(ply)] = ply:GetSubRole()
    end
end)

hook.Add("TTT2PlayerReady", "TestRoundToolkit.Ready", function(ply)
    if session and session.running and validPlayer(ply) then
        snapshot(ply)
        maintain()
    end
end)

hook.Add("PlayerDisconnected", "TestRoundToolkit.Disconnect", function(ply)
    if session then
        restorePlayer(ply, session.players[identity(ply)])
        if ply:IsBot() then
            session.players[ply] = nil
            session.roles[ply] = nil
        end
    end
    cooldowns[ply] = nil
    damageCooldowns[ply] = nil
end)

-- Another addon/admin may explicitly end the round. Its normal event scoring
-- has finished by TTTEndRound, so restoration is immediate and needs no timer.
hook.Add("TTTEndRound", "TestRoundToolkit.End", function()
    if session and session.running then
        finish()
        LANG.Msg("trt_interrupted", nil, MSG_CHAT_PLAIN)
    end
end)

hook.Add("TTT2PreWinChecker", "TestRoundToolkit.Win", function()
    if session and session.running then return WIN_NONE end
end)

hook.Add("TTTKarmaGivePenalty", "TestRoundToolkit.Karma", function()
    if session and session.running then return true end
end)

hook.Add("TTTKarmaLow", "TestRoundToolkit.KarmaLow", function()
    if session and session.running then return false end
end)

hook.Add("ShutDown", "TestRoundToolkit.Shutdown", finish)

hook.Add("PostEntityTakeDamage", "TestRoundToolkit.Damage", function(target, damage, tookDamage)
    if not session or not session.running or not tookDamage or not IsValid(target) then return end
    if not target:IsPlayer() and not target:IsNPC() then return end
    local attacker = damage:GetAttacker()
    if not validPlayer(attacker) or attacker:IsBot() or damage:GetDamage() <= 0 then return end
    -- Automatic weapons/fire cannot flood the translated chat channel.
    if CurTime() < (damageCooldowns[attacker] or 0) then return end
    damageCooldowns[attacker] = CurTime() + 0.1
    local inflictor = damage:GetInflictor()
    if damage:IsBulletDamage() then inflictor = attacker:GetActiveWeapon() end
    local weapon = IsValid(inflictor) and inflictor:GetClass() or "world"
    local victim = target:IsPlayer() and target:Nick() or target:GetClass()
    message(attacker, target == attacker and "trt_damage_self" or "trt_damage", {
        name = victim, amount = math.Round(damage:GetDamage()), weapon = weapon
    })
end)
