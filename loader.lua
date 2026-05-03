local HttpService = game:GetService("HttpService")

-- Ensure this URL is exactly correct and your repo is PUBLIC
local BASE = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function fetch(file)
    local fullUrl = BASE .. file
    print("[Loader] Attempting to fetch from: " .. fullUrl)
    
    local success, result = pcall(function()
        return HttpService:GetAsync(fullUrl)
    end)
    
    if success and result and result ~= "nil" then
        return result
    end
    
    warn("[Loader] Critical Failure for " .. file .. ": " .. tostring(result))
    return nil
end

print("[Loader] Starting...")

-- Initialize Polaris Bridge
local bridge = fetch("bridge.lua")
if bridge then
    local func, err = loadstring(bridge)
    if func then 
        task.spawn(func) 
        print("[Loader] Bridge connected successfully.") 
    else 
        warn("[Loader] Syntax error in bridge.lua: " .. tostring(err)) 
    end
end

-- Initialize Polaris Main GUI/API
local main = fetch("main.lua")
if main then
    local func, err = loadstring(main)
    if func then 
        task.spawn(func) 
        print("[Loader] Polaris API & GUI Online.") 
    else 
        warn("[Loader] Syntax error in main.lua: " .. tostring(err)) 
    end
end

print("[Loader] Done.")
