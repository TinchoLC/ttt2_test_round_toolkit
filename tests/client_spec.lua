local passed = 0
local function check(value, label)
    assert(value, label)
    passed = passed + 1
    print("PASS " .. label)
end
local texts = {}
LANG = {CreateLanguage = function() return texts end}
dofile("lua/terrortown/lang/en/test_round_toolkit.lua")
LANG.GetTranslation = function(key) assert(texts[key], key); return texts[key] end
LANG.TryTranslation = function(key) return texts[key] or key end
local hooks = {}
hook = {
    Add = function(event, _, fn) hooks[event] = fn end,
    Remove = function(event) hooks[event] = nil end
}
local requested, state, isAdmin = false, 3, false
ROUND_ACTIVE = 3
function GetGlobalBool() return requested end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function Material(path) return path end
function ScrW() return 1920 end
function LocalPlayer() return {} end
gameloop = {GetRoundState = function() return state end}
admin = {IsAdmin = function() return isAdmin end}
local rebuilds = 0
vguihandler = {Rebuild = function() rebuilds = rebuilds + 1 end}
COLOR_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = {}, 1, 2
local drawn, payload
draw = {SimpleTextOutlined = function(...) drawn = {...} end}
net = {
    Start = function(name) payload = {name = name} end,
    WriteUInt = function(value, bits) payload[#payload + 1] = {value, bits} end,
    WriteString = function(value) payload.class = value end,
    SendToServer = function() payload.sent = true end
}
TEST_ROUND_TOOLKIT = {}
dofile("lua/test_round_toolkit/cl_toolkit.lua")
local equipment = {
    {class = "shotgun", AutoSpawnable = true, spawnType = 1, Kind = 3, PrintName = "Shotgun"},
    {class = "pistol", AutoSpawnable = true, notBuyable = true, spawnType = 2, Kind = 2},
    {class = "shop_only", AutoSpawnable = false, notBuyable = false, spawnType = 1},
    {class = "neither", AutoSpawnable = false, notBuyable = true, spawnType = 1, Kind = 3},
    {class = "unknown", AutoSpawnable = true, spawnType = 99},
    {class = "item", isItem = true}
}
equipment[#equipment + 1] = equipment[1]
ShopEditor = {GetEquipmentForRoleAll = function() return equipment end}
items = {IsItem = function(item) return item.isItem end}
local ammoEntities = {
    item_ammo_pistol_ttt = {ClassName = "item_ammo_pistol_ttt", AutoSpawnable = true, spawnType = 11},
    item_box_buckshot_ttt = {ClassName = "item_box_buckshot_ttt", AutoSpawnable = true, spawnType = 12}
}
WEPS = {
    GetClass = function(weapon) return weapon.class end,
    GetAmmoForSpawnTypes = function()
        return {}, {ammoEntities.item_ammo_pistol_ttt, ammoEntities.item_box_buckshot_ttt,
            ammoEntities.item_ammo_pistol_ttt}
    end
}
scripted_ents = {Get = function(class) return ammoEntities[class] end}
weapons = {
    GetStored = function() error("Expected inherited weapon definition") end,
    Get = function() end
}
SPAWN_TYPE_WEAPON = 1
SPAWN_TYPE_AMMO = 2
WEAPON_TYPE_HEAVY = 3
entspawnscript = {
    GetSpawnTypeFromKind = function(kind) return kind end,
    GetEntTypeList = function(_, excludeTypes)
        -- Match the real API: the exclusions argument is mandatory.
        local result = {}
        for _, id in ipairs({1, 2, 3}) do
            if not excludeTypes[id] then result[#result + 1] = id end
        end
        return result
    end,
    GetLangIdentifierFromSpawnType = function(_, id) return "spawn_type_" .. id end
}
dofile("lua/test_round_toolkit/cl_weapons.lua")
local groups = TEST_ROUND_TOOLKIT.GetWeaponGroups()
local mapping = {}
for _, group in ipairs(groups) do
    local unique = {}
    for _, choice in ipairs(group.choices) do
        check(not unique[choice.value], "no duplicate within " .. group.title .. ": " .. choice.value)
        unique[choice.value] = true
        mapping[choice.value] = mapping[choice.value] or {}
        mapping[choice.value][group.title] = true
    end
end
check(not mapping.item and mapping.unknown, "equipment items excluded; uncategorized weapons retained")
check(mapping.shotgun.spawn_type_1 and mapping.shotgun.trt_weapons_heavy, "shotgun appears under spawn type and heavy Kind")
check(mapping.pistol.spawn_type_2, "matching Kind and spawnType share one entry")
check(mapping.shop_only.trt_weapons_no_spawn and mapping.shop_only.spawn_type_1,
    "non-spawnable buyable weapons also appear under their types")
local neitherCount = 0
for _ in pairs(mapping.neither) do neitherCount = neitherCount + 1 end
check(neitherCount == 1 and mapping.neither.trt_weapons_neither, "neither group remains strictly exclusive despite matching types")
local ammoChoices = TEST_ROUND_TOOLKIT.GetAmmoChoices()
check(#ammoChoices == 2 and ammoChoices[1].value ~= ammoChoices[2].value,
    "ammo choices use native registry and remove duplicate classes")
CLGAMEMODEMENU = {}
dofile("lua/terrortown/menus/gamemode/test_round_toolkit.lua")
check(not CLGAMEMODEMENU:IsAdminMenu(), "F1 card visible to normal players")
roles = {NONE = {}}
roles.GetSortedRoles = function() return {{name = "custom", index = 9}} end
local buttons, combos, helps = {}, {}, {}
local form = {}
function form:MakeHelp(data) helps[data.label] = true end
function form:MakeButton(data) buttons[data.buttonLabel] = data; return {} end
function form:MakeSlider(data) return {GetValue = function() return data.initial end} end
function form:MakeComboBox(data)
    local combo = {choices = data.choices}
    function combo:GetSelected() return self.choices[1] and self.choices[1].value end
    combos[data.label] = combo
    return combo
end
vgui = {CreateTTT2Form = function() return form end}
local pages = {}
for _, name in ipairs({"start", "roles", "weapons", "bots"}) do
    CLGAMEMODESUBMENU = {}
    dofile("lua/terrortown/menus/gamemode/test_round_toolkit/" .. name .. ".lua")
    pages[name] = CLGAMEMODESUBMENU
end
local function populate(name)
    buttons, combos, helps = {}, {}, {}
    local parent = {}
    pages[name]:Populate(parent)
    return parent
end
check(pages.start.title == "trt_page_start" and pages.roles.title == "trt_page_roles"
    and pages.weapons.title == "trt_page_weapons" and pages.bots.title == "trt_page_bots",
    "four independent native sidebar pages")
local parent = populate("start")
check(helps.trt_no_session and next(buttons) == nil, "idle ordinary user sees no test round message")
check(pages.roles:ShouldShow() and pages.weapons:ShouldShow() and pages.bots:ShouldShow(),
    "three tool pages always visible without active test")
isAdmin = true
populate("start")
check(buttons.trt_start ~= nil, "idle admin can start")
requested, state, isAdmin = true, 2, false
check(pages.roles:ShouldShow(), "role page remains visible during preparation")
state = ROUND_ACTIVE
parent = populate("start")
check(not buttons.trt_stop and not buttons.trt_cleanup, "ordinary user cannot see stop or cleanup controls")
check(pages.roles:ShouldShow() and pages.weapons:ShouldShow() and pages.bots:ShouldShow(),
    "three tool pages shown in active test")
populate("roles")
check(combos.trt_role and buttons.trt_apply and not buttons.trt_give_weapon, "role and health controls have their own page")
populate("weapons")
check(combos.trt_weapons_neither and combos.trt_weapons_no_spawn, "exclusive weapon groups have their own page")
buttons.trt_give_weapon.OnClick()
check(payload.name == "TestRoundToolkit.Weapon" and type(payload.class) == "string", "weapon button sends class")
check(combos.trt_ammo_type and buttons.trt_give_ammo and helps.trt_ammo_help,
    "ammo selector is embedded in the weapon page")
buttons.trt_give_ammo.OnClick()
check(payload.name == "TestRoundToolkit.Ammo" and type(payload.class) == "string", "ammo button sends entity class")
populate("bots")
check(not buttons.trt_add_bots and not buttons.trt_remove_bots, "ordinary user sees neither add nor remove bots")
isAdmin = true
populate("bots")
check(buttons.trt_add_bots and buttons.trt_remove_bots, "admin retains both bot controls")
populate("start")
buttons.trt_stop.OnClick()
check(payload[1][1] == 1 and payload.sent, "stop request wired")
requested = false
parent.Think(parent)
check(rebuilds == 1, "open F1 rebuilds sidebar when session changes")
requested = true
check(hooks.HUDPaint == nil and hooks.PostDrawHUD ~= nil, "status drawn after HUD and old callback removed")
hooks.PostDrawHUD()
check(drawn[3] == 1904 and drawn[6] == TEXT_ALIGN_RIGHT and drawn[1] == texts.trt_hud_short,
    "status always uses short text at right edge")
print(passed .. " checks passed")
