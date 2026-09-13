CLGAMEMODESUBMENU.base = "base_gamemodesubmenu"
CLGAMEMODESUBMENU.title = "trt_page_weapons"
CLGAMEMODESUBMENU.priority = 80

function CLGAMEMODESUBMENU:ShouldShow()
    return true
end

function CLGAMEMODESUBMENU:Populate(parent)
    local toolkit = TEST_ROUND_TOOLKIT
    toolkit.WatchMenu(parent)
    local form = vgui.CreateTTT2Form(parent, "trt_page_weapons")
    if not toolkit.IsRoundActive() then
        form:MakeHelp({label = "trt_wrong_state"})
        return
    end
    form:MakeHelp({label = "trt_weapons_help"})
    local groups = toolkit.GetWeaponGroups()
    if #groups == 0 then form:MakeHelp({label = "trt_weapons_empty"}) end
    for _, group in ipairs(groups) do
        local selector = form:MakeComboBox({label = group.title, choices = group.choices})
        form:MakeButton({
            label = group.title, buttonLabel = "trt_give_weapon", master = selector,
            OnClick = function()
                local class = selector:GetSelected()
                if isstring(class) then toolkit.RequestWeapon(class) end
            end
        })
    end

    local ammoChoices = toolkit.GetAmmoChoices()
    if #ammoChoices == 0 then
        form:MakeHelp({label = "trt_ammo_empty"})
        return
    end

    form:MakeHelp({label = "trt_ammo_help"})
    local ammoSelector = form:MakeComboBox({
        label = "trt_ammo_type",
        choices = ammoChoices
    })
    form:MakeButton({
        label = "trt_ammo_type",
        buttonLabel = "trt_give_ammo",
        master = ammoSelector,
        OnClick = function()
            local class = ammoSelector:GetSelected()
            if isstring(class) then toolkit.RequestAmmo(class) end
        end
    })
end
