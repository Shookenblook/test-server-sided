-- ============================================================
-- MANGO UNIVERSAL LOADER: Polaris Edition
-- Use this for execution in any game
-- ============================================================

-- Ensure the repository is PUBLIC on GitHub for this to work
local BASE_URL = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function safeFetch(fileName)
    -- HttpGet is used by executors to bypass standard Roblox HTTP limits
    local success, result = pcall(function()
        return game:HttpGet(BASE_URL .. fileName)
    end)

    if success and result and result ~= "" then
        return result
    end
    return nil
end

print("[Mango] Initializing Universal Loader...")

-- 1. Load Bridge (Server-Side Logic)
local bridge = safeFetch("bridge.lua")
if bridge then
    local func, err = loadstring(bridge)
    if func then 
        task.spawn(func) 
        print("[Mango] Bridge Linked.")
    else 
        warn("[Mango] Bridge Error: " .. tostring(err))
    end
else
    warn("[Mango] Failed to fetch Bridge. Check GitHub Visibility.")
end

-- 2. Load Main (Polaris API & GUI)
local main = safeFetch("main.lua")
if main then
    local func, err = loadstring(main)
    if func then 
        task.spawn(func) 
        print("[Mango] Polaris GUI Online.")
    else 
        warn("[Mango] Main Logic Error: " .. tostring(err))
    end
end
