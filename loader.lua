-- ============================================================
-- MANGO UNIVERSAL LOADER: Polaris Edition
-- Use this for execution in any game via executor
-- ============================================================

-- Repository must be PUBLIC for game:HttpGet to work correctly
local BASE_URL = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function safeFetch(fileName)
    -- game:HttpGet bypasses the standard HttpService limits seen in image_0a0aec.png
    local success, result = pcall(function()
        return game:HttpGet(BASE_URL .. fileName)
    end)

    if success and result and result ~= "" and not result:find("404: Not Found") then
        return result
    end
    return nil
end

print("[Mango] Initializing Universal Loader...")

-- 1. Load Bridge (Server-Side Logic)
local bridgeCode = safeFetch("bridge.lua")
if bridgeCode then
    local func, err = loadstring(bridgeCode)
    if func then 
        task.spawn(func) 
        -- Note: If image_09fcc0.png shows "Server only!", the bridge requires an SS executor
        print("[Mango] Bridge Linked.")
    else 
        warn("[Mango] Bridge Syntax Error: " .. tostring(err))
    end
else
    warn("[Mango] Failed to fetch bridge.lua. Check GitHub visibility or URL.")
end

-- 2. Load Main (Polaris API & GUI)
local mainCode = safeFetch("main.lua")
if mainCode then
    local func, err = loadstring(mainCode)
    if func then 
        task.spawn(func) 
        print("[Mango] Polaris GUI Online.")
    else 
        -- Fixes the 'Expected end' error seen at line 50 in image_09fcc0.png
        warn("[Mango] Main Logic Syntax Error: " .. tostring(err))
    end
else
    warn("[Mango] Failed to fetch main.lua. Check GitHub visibility or URL.")
end

print("[Mango] Loader Process Complete.")
