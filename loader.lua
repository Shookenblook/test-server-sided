-- loader.lua
-- Shookenblook/Val-Privss
-- Put this as a Script in ServerScriptService of any target game

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")

local BASE = "https://github.com/Shookenblook/test-server-sided"

-- Fetch a file from GitHub
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

-- Run a server script
local function runServer(file)
    local code = fetch(file)
    if not code then return false end
    local fn, err = loadstring(code)
    if not fn then
        warn("[Loader] Compile error in " .. file .. ": " .. tostring(err))
        return false
    end
    local ok, err2 = pcall(fn)
    if not ok then
        warn("[Loader] Runtime error in " .. file .. ": " .. tostring(err2))
        return false
    end
    print("[Loader] Server script loaded: " .. file)
    return true
end

-- Inject GUI LocalScript into a player
local function injectGui(player)
    task.wait(0.5)
    local code = fetch("gui.lua")
    if not code then return end

    -- Remove old instance
    local old = player.PlayerGui:FindFirstChild("own ss")
    if old then old:Destroy() end

    local ls = Instance.new("LocalScript")
    ls.Name = "own ss loader"
    ls.Source = code
    ls.Parent = player:WaitForChild("PlayerGui")
    print("[Loader] GUI injected into: " .. player.Name)
end

-- ============================================================
-- BOOT
-- ============================================================

print("[Loader] Starting...")

-- 1. Load bridge first
local bridgeOk = runServer("bridge.lua")
if not bridgeOk then
    warn("[Loader] Bridge failed!")
end

task.wait(0.5)

-- 2. Give GUI to players already in game
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(injectGui, player)
end

-- 3. Give GUI to future players
Players.PlayerAdded:Connect(function(player)
    task.spawn(injectGui, player)
end)

print("[Loader] Done.")
