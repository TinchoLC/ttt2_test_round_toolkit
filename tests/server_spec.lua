-- Run with Lua 5.3 / Fengari from the addon root. No game process required.
-- Focus: security boundaries and lifecycle; TTT2/GMod calls are mocked.
local passed = 0
local function check(value, label)
    assert(value, label)
    passed = passed + 1
    print("PASS " .. label)
end
local clock, state, globals = 0, 3, {}
ROUND_WAIT, ROUND_PREP, ROUND_ACTIVE, ROUND_POST = 1, 2, 3, 4
ROLE_INNOCENT, ROLE_TRAITOR, ROLE_DETECTIVE = 0, 1, 2
WIN_NONE, MSG_CHAT_PLAIN = 0, 5
TEST_ROUND_TOOLKIT = {}
function CurTime() return clock end
function IsValid(value) return type(value) == "table" and not value.invalid end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function SetGlobalBool(k, v) globals[k] = v end
function GetGlobalBool(k, fallback) if globals[k] == nil then return fallback end return globals[k] end
function string.Trim(s) return s:match("^%s*(.-)%s*$") end
math.Round = function(n) return math.floor(n + 0.5) end
local callbacks, timers, nextTick = {}, {}, {}
hook = {Add = function(event, id, fn) callbacks[event] = fn end, Run = function() end}
timer = {
    Simple = function(_, fn) nextTick[#nextTick + 1] = fn end,
    Create = function(id, _, _, fn) timers[id] = fn end,
    Remove = function(id) timers[id] = nil end
}
util = {AddNetworkString = function() end}
local receiver, weaponReceiver, ammoReceiver, wire
net = {
    Receive = function(name, fn)
        if name == "TestRoundToolkit.Action" then
            receiver = fn
        elseif name == "TestRoundToolkit.Weapon" then
            weaponReceiver = fn
        else
            ammoReceiver = fn
        end
    end,
    ReadString = function() return table.remove(wire, 1) end,
    ReadUInt = function() return table.remove(wire, 1) end
}
local console
concommand = {Add = function(_, fn) console = fn end}
local messages = {}
LANG = {Msg = function(...) messages[#messages + 1] = {...} end}
local karma = {value = 1}
function karma:GetInt() return self.value end
function karma:SetInt(v) self.value = v end
local minimum = {value = 2, GetInt = karma.GetInt, SetInt = karma.SetInt}
function GetConVar(name)
    if name == "ttt_minimum_players" then return minimum end
    assert(name == "ttt_karma", name)
    return karma
end
KARMA = {Remember = function(p) p.remembered = p.live end}
roles = {NONE = {index = -1}}
local roleList = {
    [0] = {index = 0, name = "innocent"},
    [1] = {index = 1, name = "traitor"},
    [2] = {index = 2, name = "detective"},
    [7] = {index = 7, name = "custom_role"}
}
roles.GetByIndex = function(id) return roleList[id] or roles.NONE end
roles.GetByName = function(name)
    for _, role in pairs(roleList) do if role.name == name then return role end end
    return roles.NONE
end

local players = {}
local Player = {}
Player.__index = Player
local function newPlayer(id, adminAccess, forced, bot)
    local p = setmetatable({
        id = id, admin = adminAccess, forced = forced, bot = bot,
        ready = true, alive = true, spec = false, role = 0,
        base = 800, live = 850, damage = 0.8, clean = false,
        frags = 11, deaths = 4, hp = 100, credits = 0
    }, Player)
    players[#players + 1] = p
    return p
end
function Player:IsPlayer() return true end
function Player:IsReady() return self.ready end
function Player:IsBot() return self.bot end
function Player:SteamID64() return self.id end
function Player:Nick() return "same nickname" end
function Player:GetForceSpec() return self.forced end
function Player:IsTerror() return not self.spec end
function Player:IsSpec() return self.spec end
function Player:Alive() return self.alive end
function Player:GetBaseKarma() return self.base end
function Player:SetBaseKarma(v) self.base = v end
function Player:GetLiveKarma() return self.live end
function Player:SetLiveKarma(v) self.live = v end
function Player:GetDamageFactor() return self.damage end
function Player:SetDamageFactor(v) self.damage = v end
function Player:GetCleanRound() return self.clean end
function Player:SetCleanRound(v) self.clean = v end
function Player:Frags() return self.frags end
function Player:SetFrags(v) self.frags = v end
function Player:Deaths() return self.deaths end
function Player:SetDeaths(v) self.deaths = v end
function Player:GetSubRole() return self.role end
function Player:GetWeapons() return {} end
function Player:ResetEquipment() end
function Player:ResetBought() end
function Player:SetDefaultCredits() self.credits = self:IsShopper() and 2 or 0 end
function Player:IsShopper() return self.role ~= 0 end
function Player:GetCredits() return self.credits end
function Player:AddCredits(v) self.credits = self.credits + v end
function Player:SpawnForRound()
    self.alive, self.spec = true, false
    self.spawns = (self.spawns or 0) + 1
end
function Player:Kick()
    callbacks.PlayerDisconnected(self)
    self.invalid = true
    for i, p in ipairs(players) do if self == p then table.remove(players, i) break end end
end
player = {
    GetAll = function() return players end,
    GetBots = function()
        local result = {}
        for _, p in ipairs(players) do if p.bot then result[#result + 1] = p end end
        return result
    end
}
local restarts, botsCreated, slots = 0, 0, 16
game = {MaxPlayers = function() return slots end}
function RunConsoleCommand(cmd)
    assert(cmd == "bot")
    botsCreated = botsCreated + 1
    newPlayer("bot", false, false, true)
end
local winChecks = true
local begins = 0
gameloop = {
    WaitingForPlayersChecker = function() end,
    Begin = function()
        begins = begins + 1
        if #players < minimum:GetInt() then state = ROUND_WAIT return end
        state = ROUND_ACTIVE
        callbacks.TTTBeginRound()
    end,
    GetRoundState = function() return state end,
    StopWinChecks = function() winChecks = false end,
    StartWinChecks = function() winChecks = true end,
    GetPhaseEnd = function() return 0 end,
    SetPhaseEnd = function() end,
    IsHasteMode = function() return true end,
    SetHasteEnd = function() end
}
admin = {
    IsAdmin = function(p) return p.admin end,
    PlayerForceRole = function(p, role) p.role = role end,
    PlayerSetHealth = function(p, hp) p.hp = hp end,
    RoundRestart = function()
        restarts = restarts + 1
        -- Cleanup remains pending, matching the native 0.25-second delay.
    end
}
local registeredWeapons = {
    weapon_pistol = {id = "weapon_pistol", Kind = 1,
        material = "vgui/ttt/icon_id", model = "models/weapons/w_bugbait.mdl"},
    weapon_invalid = {},
    weapon_testbase = {id = "weapon_testbase", Kind = 1}
}
weapons = {
    GetStored = function() error("Raw weapon tables must not be used for inventory checks") end,
    Get = function(class) return registeredWeapons[class] end
}
local registeredAmmo = {
    item_ammo_pistol_ttt = {
        ClassName = "item_ammo_pistol_ttt", Base = "base_ammo_ttt", AutoSpawnable = true,
        AmmoType = "Pistol", AmmoAmount = 20, AmmoMax = 60
    },
    item_ammo_disabled_ttt = {
        ClassName = "item_ammo_disabled_ttt", Base = "base_ammo_ttt", AutoSpawnable = false,
        AmmoType = "Pistol", AmmoAmount = 20, AmmoMax = 60
    }
}
scripted_ents = {
    Get = function(class) return registeredAmmo[class] end,
    IsBasedOn = function(class, base)
        local ammo = registeredAmmo[class]
        return ammo ~= nil and ammo.Base == base
    end
}
SWITCHMODE_PICKUP, SWITCHMODE_SWITCH, SWITCHMODE_FULLINV, SWITCHMODE_NOSPACE = 0, 1, 2, 3
function GetBlockingWeapon(ply, weapon)
    assert(weapon.Kind == 1, "inherited inventory Kind must be passed")
    if ply.noDropSpace then return nil, false, SWITCHMODE_NOSPACE end
    if ply.blocking and ply.blocking.AllowDrop then return ply.blocking, false, SWITCHMODE_SWITCH end
    return nil, false, SWITCHMODE_FULLINV
end
function Player:SafeDropWeapon(weapon)
    if self.dropFails then return false end
    weapon.dropped = true
    self.drops = (self.drops or 0) + 1
    self.slotFull = false
    return true
end
function Player:CanCarryWeapon(weapon) return weapon.Kind ~= nil and not self.slotFull end
function Player:Give(class) self.given = class; return {} end
function Player:HasWeapon(class) return self.given == class end
function Player:GetAmmoCount(kind) return (self.ammo and self.ammo[kind]) or 0 end
function Player:GiveAmmo(amount, kind)
    self.ammo = self.ammo or {}
    self.ammo[kind] = (self.ammo[kind] or 0) + amount
    self.lastAmmo = {amount = amount, kind = kind}
    return amount
end
dofile("lua/test_round_toolkit/sv_toolkit.lua")
local owner = newPlayer("1", true)
local user = newPlayer("2", false)
user.base, user.live = 900, 950
local spectator = newPlayer("3", false, true)
spectator.alive, spectator.spec = false, true
local function dispatch(p, action, value)
    clock = clock + 3
    TEST_ROUND_TOOLKIT.Dispatch(p, action, value)
end
local function maintain() timers["TestRoundToolkit.Maintenance"]() end

dispatch(user, "toggle")
check(not globals.test_round_toolkit_active, "ordinary player cannot start")
dispatch(user, "clean")
check(restarts == 0, "cleanup denied outside session")
newPlayer("bot", false, false, true)
dispatch(user, "unbot")
check(#player.GetBots() == 1, "bot removal denied outside session")
dispatch(owner, "toggle")
check(globals.test_round_toolkit_active and not winChecks and karma.value == 0, "start protects active round")
check(owner.role == 1 and user.role == 1, "participants start as traitors")
check(not spectator.spawns and spectator.role == 0, "forced spectator is left alone")
check(owner.credits == 101, "shop credits replenish by 99")
dispatch(user, "role", 65535)
check(user.role == 1, "unknown role rejected despite roles.NONE fallback")
dispatch(user, "role", 7)
check(user.role == 7, "registered custom role accepted")
clock = clock + 3
callbacks.PlayerSay(user, "!custom_role")
check(user.role == 7, "custom role chat names allow underscores")
dispatch(user, "health", 1234)
check(user.hp == 1234, "personal health remains available")
for _, bad in ipairs({0, -1, 65536, 1.5, "123", math.huge}) do
    dispatch(user, "health", bad)
end
check(user.hp == 1234, "invalid health rejected")
dispatch(user, "bots", 3)
check(botsCreated == 0, "ordinary player cannot create bots")
dispatch(owner, "bots", 0)
check(botsCreated == 0, "zero creates zero bots")
dispatch(owner, "bots", 2)
check(botsCreated == 2, "requested bot count is exact")
slots = #players + 1
dispatch(owner, "bots", 63)
check(botsCreated == 3, "bot count bounded by free slots")
dispatch(owner, "bots", 1)
check(botsCreated == 3, "full server does not create bots")
dispatch(owner, "bots", nil)
check(botsCreated == 3, "missing bot count rejected")
clock = clock + 3
wire = {3, 500}
receiver(18, user)
check(user.hp == 1234 and #wire == 2, "truncated packet rejected before reading")
wire = {3, 500}
receiver(19, user)
check(user.hp == 500, "valid wire request accepted")
wire = {3, 600}
receiver(19, user)
check(user.hp == 500, "request spam rate limited")
clock = clock + 3
wire = {7, 0}
receiver(19, user)
check(user.hp == 500, "unknown action ignored")
user.alive, user.spec = false, true
maintain()
check(user.alive and user.role == 7 and user.spawns == 1, "respawn preserves selected custom role")
user.role = 2
maintain()
check(user.role == 2, "custom role transitions are not overwritten")
dispatch(owner, "clean")
state = ROUND_PREP
callbacks.TTT2PostCleanupMap()
check(state == ROUND_PREP and globals.test_round_toolkit_active, "native cleanup preserves session")
user.role = 0
state = ROUND_ACTIVE
callbacks.TTTBeginRound()
check(user.role == 2 and not winChecks, "selection reapplied after native round begin")
local late = newPlayer("4", false)
callbacks.TTT2PlayerReady(late)
check(late.role == 1 and late.base == 1000, "late joiner enters test")
callbacks.PlayerDisconnected(user)
check(user.base == 900 and user.live == 950 and user.remembered == 950, "disconnect restores original karma before persistence")
for i, p in ipairs(players) do if p == user then table.remove(players, i) break end end
user.invalid = true
local reconnect = newPlayer("2", false)
callbacks.TTT2PlayerReady(reconnect)
dispatch(owner, "toggle")
check(karma.value == 0, "karma remains protected while native cleanup is pending")
state = ROUND_PREP
callbacks.TTT2PostCleanupMap()
check(not globals.test_round_toolkit_active and karma.value == 1, "stop restores karma configuration")
check(owner.base == 800 and owner.live == 850 and owner.damage == 0.8 and owner.clean == false, "all original karma fields restored")
check(reconnect.base == 900 and reconnect.live == 950, "reconnect retains original identity snapshot")
check(owner.frags == 11 and owner.deaths == 4 and reconnect.frags == 11, "score restoration independent of duplicate nicknames")
check(#player.GetBots() == 0 and state == ROUND_PREP, "stop removes all bots and restarts active round")
state = ROUND_WAIT
dispatch(owner, "toggle")
check(globals.test_round_toolkit_active and owner.role == 1, "waiting session queues without forcing round start")
dispatch(owner, "health", 12)
check(owner.hp == 100, "personal actions denied while waiting")
state = ROUND_ACTIVE
callbacks.TTTBeginRound()
state = ROUND_POST
owner.frags, owner.deaths = 123, 123 -- native score update happens before TTTEndRound
callbacks.TTTEndRound()
check(not globals.test_round_toolkit_active and owner.frags == 11 and karma.value == 1, "external round end restores after native scoring")
state = ROUND_ACTIVE
karma.value = 0
dispatch(owner, "toggle")
dispatch(owner, "toggle")
state = ROUND_PREP
callbacks.TTT2PostCleanupMap()
check(karma.value == 0, "original disabled karma remains disabled")
check(not timers["TestRoundToolkit.Maintenance"], "no maintenance timer remains after stop")
console({invalid = true})
check(not globals.test_round_toolkit_active, "non-player console safely rejected")
-- Regression: requesting a test in preparation begins exactly once immediately.
players = {owner}
state = ROUND_PREP
karma.value = 1
minimum.value = 2
timers.prep2begin = function() error("Old preparation timer should be removed") end
local unrelatedTimer = function() end
timers.unrelated = unrelatedTimer
local beforeBegin = begins
dispatch(owner, "toggle")
check(minimum.value == 1, "test permits a single participant")
check(state == ROUND_ACTIVE and begins == beforeBegin + 1, "preparation is skipped via native Begin")
check(not timers.prep2begin and timers.unrelated == unrelatedTimer, "only native preparation transition is removed")
check(karma.value == 0 and timers["TestRoundToolkit.Maintenance"], "immediate round activates test protection")
callbacks.TTTPrepareRound()
local repeatBegin = table.remove(nextTick, 1)
repeatBegin()
check(begins == beforeBegin + 1, "late preparation callback cannot start twice")
dispatch(owner, "toggle")
callbacks.TTT2PostCleanupMap()
check(minimum.value == 2, "stopping restores normal player minimum")
state = ROUND_WAIT
dispatch(owner, "toggle")
callbacks.TTTPrepareRound()
local cancelled = table.remove(nextTick, 1)
dispatch(owner, "toggle")
state = ROUND_PREP
cancelled()
check(begins == beforeBegin + 1, "cancelled session cannot begin in deferred preparation callback")
check(minimum.value == 2 and karma.value == 1, "cancelling restores minimum without changing karma")
minimum.value = 0
state = ROUND_WAIT
dispatch(owner, "toggle")
dispatch(owner, "toggle")
check(minimum.value == 0, "existing zero minimum is preserved")
state = ROUND_ACTIVE
dispatch(owner, "toggle")
local ordinary = newPlayer("ordinary", false)
dispatch(ordinary, "weapon", "weapon_pistol")
check(ordinary.given == "weapon_pistol", "server-side placeholder metadata does not reject registered weapon")
ordinary.given = nil
for _, class in ipairs({"weapon_invalid", "weapon_testbase", "prop_physics", "../bad", string.rep("x", 129)}) do
    dispatch(ordinary, "weapon", class)
end
check(not ordinary.given, "unregistered, base and malformed weapon classes rejected")
ordinary.slotFull = true
dispatch(ordinary, "weapon", "weapon_pistol")
check(not ordinary.given, "native inventory capacity enforced")
ordinary.blocking = {AllowDrop = true, Kind = 1}
local oldWeapon = ordinary.blocking
dispatch(ordinary, "weapon", "weapon_pistol")
check(ordinary.given == "weapon_pistol" and oldWeapon.dropped and not oldWeapon.invalid,
    "full slot drops blocking weapon into world and gives replacement")
local dropsBefore = ordinary.drops
ordinary.given = nil
dispatch(ordinary, "weapon", "weapon_pistol")
check(ordinary.drops == dropsBefore, "free slot does not drop any weapon")
ordinary.given = nil
ordinary.slotFull, ordinary.noDropSpace = true, true
dispatch(ordinary, "weapon", "weapon_pistol")
check(not ordinary.given and ordinary.drops == dropsBefore, "no drop space prevents giving or dropping")
ordinary.noDropSpace, ordinary.dropFails = false, true
dispatch(ordinary, "weapon", "weapon_pistol")
check(not ordinary.given and ordinary.drops == dropsBefore, "failed native drop does not give replacement")
ordinary.dropFails = false
ordinary.blocking.AllowDrop = false
dispatch(ordinary, "weapon", "weapon_pistol")
check(not ordinary.given and ordinary.drops == dropsBefore, "non-droppable blocking weapon is preserved")
ordinary.slotFull = false
clock = clock + 3
wire = {"weapon_pistol"}
weaponReceiver(2000, ordinary)
check(#wire == 1, "oversize weapon packet rejected before reading")
weaponReceiver(8 * 14, ordinary)
check(ordinary.given == "weapon_pistol", "bounded weapon net request works")
clock = clock + 3
wire = {"item_ammo_pistol_ttt"}
ammoReceiver(2000, ordinary)
check(#wire == 1, "oversize ammo packet rejected before reading")
ammoReceiver(8 * 24, ordinary)
check(ordinary:GetAmmoCount("Pistol") == 20 and ordinary.lastAmmo.amount == 20,
    "ammo request grants one registered ammo box")
clock = clock + 3
ordinary.ammo.Pistol = 55
wire = {"item_ammo_pistol_ttt"}
ammoReceiver(8 * 24, ordinary)
check(ordinary:GetAmmoCount("Pistol") == 60 and ordinary.lastAmmo.amount == 5,
    "ammo request respects the native ammo maximum")
clock = clock + 3
ordinary.lastAmmo = nil
wire = {"item_ammo_disabled_ttt"}
ammoReceiver(8 * 26, ordinary)
check(not ordinary.lastAmmo, "non-spawnable ammo entity rejected")
local restartsBefore = restarts
dispatch(ordinary, "clean")
check(restarts == restartsBefore, "ordinary player cannot clean during test")
clock = clock + 3
wire = {6, 0}
receiver(19, ordinary)
check(restarts == restartsBefore, "manual cleanup packet cannot bypass permissions")
local protectedBot = newPlayer("protected_bot", false, false, true)
local botsBefore = #player.GetBots()
dispatch(ordinary, "unbot")
check(#player.GetBots() == botsBefore and not protectedBot.invalid, "ordinary player cannot remove bots during test")
clock = clock + 3
wire = {5, 0}
receiver(19, ordinary)
check(#player.GetBots() == botsBefore, "manual bot removal packet cannot bypass permissions")
dispatch(owner, "unbot")
check(#player.GetBots() == 0, "administrator may still remove bots")
local countBefore = botsCreated
dispatch(ordinary, "bots", 1)
check(botsCreated == countBefore, "adding bots still requires administration")
dispatch(ordinary, "toggle")
check(globals.test_round_toolkit_active, "ordinary player cannot stop a test")
clock = clock + 3
wire = {1, 0}
receiver(19, ordinary)
check(globals.test_round_toolkit_active, "manual stop packet cannot bypass permissions")
dispatch(owner, "toggle")
callbacks.TTT2PostCleanupMap()
check(not globals.test_round_toolkit_active, "administrator can still stop a test")
ordinary.given = nil
dispatch(ordinary, "weapon", "weapon_pistol")
check(not ordinary.given, "weapon giving blocked outside test")
clock = clock + 3
ordinary.ammo.Pistol, ordinary.lastAmmo = 0, nil
wire = {"item_ammo_pistol_ttt"}
ammoReceiver(8 * 24, ordinary)
check(ordinary:GetAmmoCount("Pistol") == 0 and not ordinary.lastAmmo, "ammo giving blocked outside test")
dispatch(ordinary, "toggle")
check(not globals.test_round_toolkit_active, "ordinary player still cannot start a test")
print(string.format("%d checks passed", passed))
