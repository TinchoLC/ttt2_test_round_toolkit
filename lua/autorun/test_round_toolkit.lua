if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("test_round_toolkit/cl_toolkit.lua")
    AddCSLuaFile("test_round_toolkit/cl_weapons.lua")
end

-- Autorun installs the callback; TTT2 supplies its libraries before invoking it.
hook.Add("TTT2FinishedLoading", "TestRoundToolkit.Load", function()
    if TEST_ROUND_TOOLKIT then
        -- TTT2 can reload the client without recreating the Lua state.
        if CLIENT then
            include("test_round_toolkit/cl_toolkit.lua")
            include("test_round_toolkit/cl_weapons.lua")
        end
        return
    end
    TEST_ROUND_TOOLKIT = {}
    if SERVER then
        include("test_round_toolkit/sv_toolkit.lua")
    else
        include("test_round_toolkit/cl_toolkit.lua")
        include("test_round_toolkit/cl_weapons.lua")
    end
end)
