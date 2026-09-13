CLGAMEMODESUBMENU.base = "base_gamemodesubmenu"
CLGAMEMODESUBMENU.title = "trt_page_bots"
CLGAMEMODESUBMENU.priority = 70

function CLGAMEMODESUBMENU:ShouldShow()
    return true
end

function CLGAMEMODESUBMENU:Populate(parent)
    local toolkit = TEST_ROUND_TOOLKIT
    toolkit.WatchMenu(parent)
    local form = vgui.CreateTTT2Form(parent, "trt_page_bots")
    if not toolkit.IsRoundActive() then
        form:MakeHelp({label = "trt_wrong_state"})
        return
    end
    if admin.IsAdmin(LocalPlayer()) then
        local count = form:MakeSlider({
            label = "trt_bots", min = 0, max = 63, decimal = 0, initial = 1
        })
        form:MakeButton({
            label = "trt_bots", buttonLabel = "trt_add_bots",
            OnClick = function() toolkit.Request("bots", count:GetValue()) end
        })
    else
        form:MakeHelp({label = "trt_bots_admin"})
        return
    end
    form:MakeButton({
        label = "trt_bots", buttonLabel = "trt_remove_bots",
        OnClick = function() toolkit.Request("unbot") end
    })
end
