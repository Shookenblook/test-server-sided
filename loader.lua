local HttpService = game:GetService("HttpService")

-- Attempting the most direct Raw URL format
local BASE = "https://raw.githubusercontent.com/Shookenblook/test-server-sided/main/"

local function fetch(file)
    local success, result = pcall(function()
        return HttpService:GetAsync(BASE .. file)
    end)
    
    if success and result then
        -- Check if GitHub returned a 404 page instead of code
        if result:find("404: Not Found") then
            warn("[Loader] 404 Error: " .. file .. " not found at URL. Check branch name.")
            return nil
        end
        return result
    end
    
    warn("[Loader] Network Error: " .. tostring(result))
    return nil
end

print("[Loader] Starting...")

local bridge = fetch("bridge.lua")
if bridge then
    local func, err = loadstring(bridge)
    if func then task.spawn(func) print("[Loader] Bridge Online.") else warn(err) end
end

local main = fetch("main.lua")
if main then
    local func, err = loadstring(main)
    if func then task.spawn(func) print("[Loader] Polaris API Online.") else warn(err) end
end

print("[Loader] Done.")
