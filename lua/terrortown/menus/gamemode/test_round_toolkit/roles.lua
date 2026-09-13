CLGAMEMODESUBMENU.base = "base_gamemodesubmenu"
CLGAMEMODESUBMENU.title = "trt_page_roles"
CLGAMEMODESUBMENU.priority = 90

function CLGAMEMODESUBMENU:ShouldShow()
    return true
end

function CLGAMEMODESUBMENU:Populate(parent)
    local toolkit = TEST_ROUND_TOOLKIT
    toolkit.WatchMenu(parent)
    local form = vgui.CreateTTT2Form(parent, "trt_page_roles")
    if not toolkit.IsRoundActive() then
        form:MakeHelp({label = "trt_wrong_state"})
        return
    end
    form:MakeHelp({label = "trt_personal_help"})
    local choices = {}
    for _, role in ipairs(roles.GetSortedRoles()) do
        if role ~= roles.NONE and not role.isAbstract then
            choices[#choices + 1] = {title = role.name, value = role.index}
        end
    end
    local selector = form:MakeComboBox({label = "trt_role", choices = choices})
    form:MakeButton({
        label = "trt_role", buttonLabel = "trt_apply", master = selector,
        OnClick = function()
            local role = selector:GetSelected()
            if isnumber(role) then toolkit.Request("role", role) end
        end
    })
    local health = form:MakeSlider({
        label = "trt_health", min = 1, max = 65535, decimal = 0, initial = 100
    })
    form:MakeButton({
        label = "trt_health", buttonLabel = "trt_apply",
        OnClick = function() toolkit.Request("health", health:GetValue()) end
    })
end
