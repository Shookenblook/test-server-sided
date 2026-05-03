-- ============================================================
-- MANGO LOADER: Polaris Edition
-- Updated with GitHub Repository Path
-- ============================================================

local HttpService = game:GetService("HttpService")

-- The base URL for your raw GitHub files
local BASE = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function fetch(file)
    local success, result = pcall(function()
        return HttpService:GetAsync(BASE .. file)
    end)
    
    if success and result and result ~= "nil" and result ~= "404: Not Found" then
        return result
    end
    warn("[Loader] Failed to fetch: " .. file .. " | Error: " .. tostring(result))
    return nil
end

print("[Loader] Starting Mango initialization...")

-- 1. Initialize the Bridge (Server-side Logic)
local bridgeCode = fetch("bridge.lua")
if bridgeCode then
    local func, err = loadstring(bridgeCode)
    if func then 
        task.spawn(func) 
        print("[Loader] Bridge initialized successfully.")
    else 
        warn("[Loader] Bridge syntax error: " .. tostring(err)) 
    end
else
    warn("[Loader] Bridge failed to load from GitHub!")
end

-- 2. Initialize Main Logic (GUI & Polaris API)
local mainCode = fetch("main.lua")
if mainCode then
    local func, err = loadstring(mainCode)
    if func then 
        task.spawn(func) 
        print("[Loader] Polaris API and GUI online.")
    else 
        warn("[Loader] Main logic syntax error: " .. tostring(err)) 
    end
else
    warn("[Loader] Main logic failed to load from GitHub!")
end

print("[Loader] Process complete.")
