-- loader.lua
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- FIX 1: Must use the 'raw' GitHub domain and point to the main branch
local BASE = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function fetch(file)
    local ok, result = pcall(function()
        return HttpService:GetAsync(BASE .. file, true)
    end)
    if not ok or type(result) ~= "string" or #result == 0 then
        warn("[Loader] Failed to fetch: " .. file .. " | " .. tostring(result))
        return nil
    end
    print("[Loader] Fetched: " .. file)
    return result
end

local function runServer(file)
    local code = fetch(file)
    if not code then return false end
    
    local fn, err = loadstring(code)
    if not fn then
        warn("[Loader] Compile error in " .. file .. ": " .. tostring(err))
        return false
    end
    
    -- Pass the Players service to the script in case it needs it
    local ok, err2 = pcall(fn, Players) 
    if not ok then
        warn("[Loader] Runtime error in " .. file .. ": " .. tostring(err2))
        return false
    end
    
    print("[Loader] Server script loaded: " .. file)
    return true
end

-- ============================================================
-- BOOT
-- ============================================================
print("[Loader] Starting...")

-- 1. Load Bridge (Connects to your local Node.js server)
local bridgeOk = runServer("bridge.lua")
if not bridgeOk then
    warn("[Loader] Bridge failed!")
end

task.wait(0.5)

-- 2. Load Main Logic (Handles Polaris functions and game manipulation)
local mainOk = runServer("main.lua")
if not mainOk then
    warn("[Loader] Main logic failed!")
end

-- FIX 2: GUI Injection removed because .Source is locked. 
-- Your GUI should be cloned from your Roblox Model inside main.lua instead.

print("[Loader] Done.")
