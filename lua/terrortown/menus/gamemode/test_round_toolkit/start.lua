CLGAMEMODESUBMENU.base = "base_gamemodesubmenu"
CLGAMEMODESUBMENU.title = "trt_page_start"
CLGAMEMODESUBMENU.priority = 100

function CLGAMEMODESUBMENU:Populate(parent)
    local toolkit = TEST_ROUND_TOOLKIT
    toolkit.WatchMenu(parent)
    local requested = GetGlobalBool("test_round_toolkit_active", false)
    local form = vgui.CreateTTT2Form(parent, "trt_page_start")
    form:MakeHelp({label = "trt_round_help"})
    if not requested then form:MakeHelp({label = "trt_no_session"}) end
    local isAdmin = admin.IsAdmin(LocalPlayer())
    if isAdmin then
        form:MakeButton({
            label = "trt_round",
            buttonLabel = requested and "trt_stop" or "trt_start",
            OnClick = function() toolkit.Request("toggle") end
        })
    end
    if isAdmin and toolkit.IsRoundActive() then
        form:MakeHelp({label = "trt_cleanup_help"})
        form:MakeButton({
            label = "trt_world", buttonLabel = "trt_cleanup",
            OnClick = function() toolkit.Request("clean") end
        })
    end
    local help = vgui.CreateTTT2Form(parent, "trt_shortcuts")
    help:MakeHelp({label = "trt_shortcuts_help"})
end
