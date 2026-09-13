-- Use Edit Equipment's cache, with both explicit spawn type and native Kind mapping.
function TEST_ROUND_TOOLKIT.GetWeaponGroups()
    local groups, byKey, seen = {}, {}, {}
    local types = entspawnscript.GetEntTypeList(SPAWN_TYPE_WEAPON, {})
    local knownTypes = {}
    for _, spawnType in ipairs(types) do knownTypes[spawnType] = true end

    local function add(key, title, class, name)
        if not byKey[key] then
            byKey[key] = {title = title, choices = {}, classes = {}}
            groups[#groups + 1] = byKey[key]
        end
        local group = byKey[key]
        if group.classes[class] then return end
        group.classes[class] = true
        group.choices[#group.choices + 1] = {
            title = LANG.TryTranslation(name) .. " [" .. class .. "]", value = class
        }
    end

    local function addType(spawnType, class, name)
        if not knownTypes[spawnType] then return false end
        local title = spawnType == WEAPON_TYPE_HEAVY and "trt_weapons_heavy"
            or entspawnscript.GetLangIdentifierFromSpawnType(SPAWN_TYPE_WEAPON, spawnType)
        add("spawn_" .. spawnType, title, class, name)
        return true
    end

    for _, equipment in ipairs(ShopEditor.GetEquipmentForRoleAll()) do
        if not items.IsItem(equipment) then
            local class = WEPS.GetClass(equipment)
            if class and not seen[class] then
                seen[class] = true
                local weapon = weapons.Get(class) or equipment
                local name = equipment.EquipMenuData and equipment.EquipMenuData.name
                name = name or equipment.PrintName or class
                if not weapon.AutoSpawnable and weapon.notBuyable then
                    -- This is the only exclusive category.
                    add("neither", "trt_weapons_neither", class, name)
                else
                    if not weapon.AutoSpawnable then
                        add("no_spawn", "trt_weapons_no_spawn", class, name)
                    end
                    local explicit = addType(weapon.spawnType, class, name)
                    local byKind = addType(entspawnscript.GetSpawnTypeFromKind(weapon.Kind), class, name)
                    if not explicit and not byKind then
                        add("other", "trt_weapons_other", class, name)
                    end
                end
            end
        end
    end

    table.sort(groups, function(a, b)
        return LANG.TryTranslation(a.title) < LANG.TryTranslation(b.title)
    end)
    for _, group in ipairs(groups) do
        table.sort(group.choices, function(a, b) return a.title < b.title end)
    end
    return groups
end

function TEST_ROUND_TOOLKIT.RequestWeapon(class)
    if not isstring(class) or #class == 0 or #class > 128 then return end
    net.Start("TestRoundToolkit.Weapon")
    net.WriteString(class)
    net.SendToServer()
end

function TEST_ROUND_TOOLKIT.GetAmmoChoices()
    local _, ammoList = WEPS.GetAmmoForSpawnTypes()
    local choices, seen = {}, {}

    for _, rawAmmo in ipairs(ammoList) do
        local class = rawAmmo.ClassName
        local ammo = class and scripted_ents.Get(class) or rawAmmo

        if class and ammo and ammo.AutoSpawnable and not seen[class] then
            seen[class] = true
            local typeName = ammo.spawnType
                and entspawnscript.GetLangIdentifierFromSpawnType(SPAWN_TYPE_AMMO, ammo.spawnType)
                or "trt_ammo_other"
            choices[#choices + 1] = {
                title = LANG.TryTranslation(typeName) .. " [" .. class .. "]",
                value = class
            }
        end
    end

    table.sort(choices, function(a, b) return a.title < b.title end)

    return choices
end

function TEST_ROUND_TOOLKIT.RequestAmmo(class)
    if not isstring(class) or #class == 0 or #class > 128 then return end
    net.Start("TestRoundToolkit.Ammo")
    net.WriteString(class)
    net.SendToServer()
end
