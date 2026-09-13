local Toolkit = TEST_ROUND_TOOLKIT
local actions = {toggle = 1, role = 2, health = 3, bots = 4, unbot = 5, clean = 6}

function Toolkit.Request(action, value)
    if not actions[action] then return end
    value = tonumber(value) or 0
    if value ~= value or value < 0 or value > 65535 then return end
    net.Start("TestRoundToolkit.Action")
    net.WriteUInt(actions[action], 3)
    net.WriteUInt(math.floor(value), 16)
    net.SendToServer()
end

function Toolkit.IsRoundActive()
    return GetGlobalBool("test_round_toolkit_active", false)
        and gameloop.GetRoundState() == ROUND_ACTIVE
end

-- All four pages share the same refresh rule, including when F1 stays open.
function Toolkit.WatchMenu(parent)
    local function key()
        return tostring(GetGlobalBool("test_round_toolkit_active", false))
            .. ":" .. tostring(gameloop.GetRoundState())
            .. ":" .. tostring(admin.IsAdmin(LocalPlayer()))
    end
    local previous = key()
    parent.Think = function()
        local current = key()
        if previous ~= current then
            previous = current
            vguihandler.Rebuild()
        end
    end
end

-- Remove the previous callback as well when this file is refreshed in-game.
hook.Remove("HUDPaint", "TestRoundToolkit.Status")
hook.Add("PostDrawHUD", "TestRoundToolkit.Status", function()
    if not GetGlobalBool("test_round_toolkit_active", false) then return end
    draw.SimpleTextOutlined(LANG.GetTranslation("trt_hud_short"), "Trebuchet18",
        ScrW() - 16, 24, COLOR_WHITE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, COLOR_BLACK)
end)
