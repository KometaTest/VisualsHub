-- VisualsHub: разведка перков во время матча (только чтение, ничего не отправляет на сервер).
-- Запусти В МАТЧЕ (лучше через 10-20 с после начала). Скрипт ~60 с слушает события и сканирует:
-- атрибуты / Value у игроков и персонажей, ReplicatedStorage, PlayerGui (картинки и тексты перков), MatchResults,
-- входящие RemoteEvent (только читает аргументы) и, если экзекутор умеет, getgc (таблицы {name, level}).
-- Итог: файл workspace/VisualsHub_perkscan.txt + копия в буфер обмена.

local LISTEN_SECONDS = 60
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

local out, seen = {}, {}
local function log(...)
    local t = table.pack(...)
    for i = 1, t.n do t[i] = tostring(t[i]) end
    local s = table.concat(t, " ", 1, t.n)
    if seen[s] then return end
    seen[s] = true
    out[#out + 1] = s
end
local function section(t) out[#out + 1] = "" out[#out + 1] = "==== " .. t .. " ====" end
local function path(x) local ok, p = pcall(function() return x:GetFullName() end) return ok and p or tostring(x) end

------------------------------------------------ справочник перков
local PERK, ICON = {}, {} -- PERK[lower name] = name ; ICON[assetId digits] = "name L<level>"
local function digits(s) return type(s) == "string" and s:match("%d%d%d%d+") or nil end
local function addPerkFolder(f, side)
    for _, p in ipairs(f:GetChildren()) do
        PERK[p.Name:lower()] = p.Name
        for _, lv in ipairs(p:GetChildren()) do
            local id
            if lv:IsA("Decal") then id = digits(lv.Texture)
            elseif lv:IsA("ImageLabel") or lv:IsA("ImageButton") then id = digits(lv.Image) end
            if id then ICON[id] = p.Name .. " L" .. lv.Name .. " (" .. side .. ")" end
        end
    end
end
if RS:FindFirstChild("Perks") then addPerkFolder(RS.Perks, "surv") end
if RS:FindFirstChild("Killers") then
    for _, k in ipairs(RS.Killers:GetChildren()) do
        if k:FindFirstChild("Perks") then addPerkFolder(k.Perks, "killer " .. k.Name) end
    end
end
local nPerk, nIcon = 0, 0
for _ in pairs(PERK) do nPerk += 1 end
for _ in pairs(ICON) do nIcon += 1 end

-- есть ли в строке упоминание перка
local function hit(s)
    if type(s) ~= "string" or s == "" then return nil end
    local l = s:lower()
    if PERK[l] then return "perk:" .. PERK[l] end
    if l:find("perk", 1, true) then return "word" end
    local id = digits(s)
    if id and ICON[id] then return "icon:" .. ICON[id] end
    if #s > 3 and #s < 4000 and (s:find("{", 1, true) or s:find(",", 1, true)) then
        for low, name in pairs(PERK) do
            if #low > 4 and l:find(low, 1, true) then return "contains:" .. name end
        end
    end
    return nil
end
local function short(v)
    local s = tostring(v)
    if #s > 300 then s = s:sub(1, 300) .. "...(" .. #s .. ")" end
    return s
end

-- атрибуты + Value-объекты одного инстанса
local function scanInst(x)
    local ok, attrs = pcall(function() return x:GetAttributes() end)
    if ok then
        for k, v in pairs(attrs) do
            local h = hit(k) or hit(type(v) == "string" and v or nil)
            if h then log("[attr]", path(x), "@" .. k, "=", short(v), " <" .. h .. ">") end
        end
    end
    if x:IsA("ValueBase") then
        local okv, v = pcall(function() return x.Value end)
        local h = hit(x.Name) or (okv and hit(type(v) == "string" and v or nil))
        if h then log("[value]", x.ClassName, path(x), "=", short(okv and v or "?"), " <" .. h .. ">") end
    elseif x:IsA("Folder") or x:IsA("Configuration") or x:IsA("Model") then
        local h = hit(x.Name)
        if h then log("[obj]", x.ClassName, path(x), " <" .. h .. ">") end
    end
end
local function scanTree(root, skip)
    local list = root:GetDescendants()
    for i, x in ipairs(list) do
        if not (skip and skip(x)) then pcall(scanInst, x) end
        if i % 3000 == 0 then task.wait() end
    end
end

------------------------------------------------ 0. шапка
section("info")
log("place", game.PlaceId, "job", game.JobId, "time", os.date and os.date("%H:%M:%S") or "")
log("perks known:", nPerk, "icons:", nIcon)
log("players:", #Players:GetPlayers(), "me:", LP.Name, LP.UserId, "team:", tostring(LP.Team))

------------------------------------------------ 1. MatchResults сейчас
section("MatchResults")
local MR = RS:FindFirstChild("MatchResults")
if not MR then log("нет ReplicatedStorage.MatchResults")
else
    log("children:", #MR:GetChildren())
    for _, e in ipairs(MR:GetChildren()) do
        local a = {}
        for k, v in pairs(e:GetAttributes()) do a[#a + 1] = k .. "=" .. short(v) end
        log(" ", e.Name, table.concat(a, " | "))
    end
end

------------------------------------------------ 2. игроки и персонажи
section("Players / characters")
for _, p in ipairs(Players:GetPlayers()) do
    local a = {}
    for k, v in pairs(p:GetAttributes()) do a[#a + 1] = k .. "=" .. short(v) end
    log("[player]", p.Name, p.UserId, "attrs:", table.concat(a, " | "))
    scanInst(p)
    local ppg = p:FindFirstChildOfClass("PlayerGui")
    scanTree(p, function(x) return ppg ~= nil and (x == ppg or x:IsDescendantOf(ppg)) end)
    if p.Character then
        local ca = {}
        for k, v in pairs(p.Character:GetAttributes()) do ca[#ca + 1] = k .. "=" .. short(v) end
        log("[char]", p.Name, "attrs:", table.concat(ca, " | "))
        scanInst(p.Character)
        scanTree(p.Character)
    end
end

------------------------------------------------ 3. ReplicatedStorage (без справочника перков и шаблонов GUI)
section("ReplicatedStorage")
local perksF, killersF, specF = RS:FindFirstChild("Perks"), RS:FindFirstChild("Killers"), RS:FindFirstChild("Spectator")
scanTree(RS, function(x)
    if perksF and x:IsDescendantOf(perksF) then return true end
    if specF and x:IsDescendantOf(specF) then return true end
    if killersF and x:IsDescendantOf(killersF) and x.Parent and (x.Parent.Name == "Perks" or (x.Parent.Parent and x.Parent.Parent.Name == "Perks")) then return true end
    return false
end)
scanInst(RS)

------------------------------------------------ 4. workspace (атрибуты верхних папок + всё, что не карта)
section("workspace")
for _, c in ipairs(workspace:GetChildren()) do
    pcall(scanInst, c)
    if c.Name ~= "Map" and not c:IsA("Terrain") and not c:IsA("Camera") then
        local okd, d = pcall(function() return #c:GetDescendants() end)
        if okd and d < 20000 then scanTree(c) end
    end
end
scanInst(workspace)

------------------------------------------------ 5. PlayerGui: картинки / тексты перков (тут свои перки в HUD)
section("PlayerGui")
local pg = LP:FindFirstChildOfClass("PlayerGui")
if pg then
    for i, x in ipairs(pg:GetDescendants()) do
        pcall(function()
            if x:IsA("ImageLabel") or x:IsA("ImageButton") then
                local id = digits(x.Image)
                if id and ICON[id] then log("[gui img]", path(x), "->", ICON[id], "visible:", tostring(x.Visible)) end
            elseif x:IsA("TextLabel") or x:IsA("TextButton") then
                local h = hit(x.Text)
                if h and h ~= "word" then log("[gui text]", path(x), "=", short(x.Text), " <" .. h .. ">") end
            end
            local h = hit(x.Name)
            if h then log("[gui name]", x.ClassName, path(x), " <" .. h .. ">") end
            scanInst(x)
        end)
        if i % 3000 == 0 then task.wait() end
    end
end

------------------------------------------------ 6. getgc: таблицы вида {name = <перк>, level = n}
section("getgc")
local gc = rawget(getfenv(), "getgc") or getgc
if type(gc) ~= "function" then log("getgc нет в этом экзекуторе")
else
    local ok, objs = pcall(gc, true)
    if not ok then log("getgc error", tostring(objs))
    else
        local perkTabs, holders, found = {}, 0, 0
        for _, t in ipairs(objs) do
            if type(t) == "table" then
                local okn, n = pcall(rawget, t, "name")
                if okn and type(n) == "string" and PERK[n:lower()] then
                    perkTabs[t] = true
                    found += 1
                end
            end
        end
        log("perk entries {name=...}:", found)
        -- кто держит списки таких записей и под какими ключами (UserId? имя игрока?)
        local lists = {}
        for _, t in ipairs(objs) do
            if type(t) == "table" then
                local okf, first = pcall(rawget, t, 1)
                if okf and perkTabs[first] then lists[t] = true end
            end
        end
        for _, t in ipairs(objs) do
            if type(t) == "table" and holders < 40 then
                pcall(function()
                    for k, v in next, t do
                        if lists[v] or perkTabs[v] then
                            local names = {}
                            if lists[v] then for _, e in ipairs(v) do names[#names + 1] = tostring(rawget(e, "name")) .. "/" .. tostring(rawget(e, "level")) end
                            else names[1] = tostring(rawget(v, "name")) .. "/" .. tostring(rawget(v, "level")) end
                            local pl = type(k) == "number" and Players:GetPlayerByUserId(k)
                            log("[gc] key=" .. short(k) .. (pl and (" (player " .. pl.Name .. ")") or ""), "->", table.concat(names, ", "))
                            holders += 1
                        end
                    end
                end)
            end
        end
    end
end

------------------------------------------------ 7. входящие события (только слушаем)
section("RemoteEvent (" .. LISTEN_SECONDS .. " s)")
local function ser(v, depth)
    depth = depth or 0
    if type(v) == "table" then
        if depth > 3 then return "{...}" end
        local parts, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n > 25 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. ser(x, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif typeof(v) == "Instance" then return "<" .. path(v) .. ">"
    end
    return tostring(v)
end
local conns, counts = {}, {}
for _, r in ipairs(RS:GetDescendants()) do
    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
        conns[#conns + 1] = r.OnClientEvent:Connect(function(...)
            local s = ser({ ... })
            counts[r] = (counts[r] or 0) + 1
            local h = hit(s)
            if h then log("[remote]", path(r), short(s), " <" .. h .. ">") end
        end)
    end
end
-- новые атрибуты, появляющиеся по ходу
local function watchAttrs(x, tag)
    conns[#conns + 1] = x.AttributeChanged:Connect(function(k)
        local v = x:GetAttribute(k)
        local h = hit(k) or hit(type(v) == "string" and v or nil)
        if h then log("[attr+]", tag, path(x), "@" .. k, "=", short(v), " <" .. h .. ">") end
    end)
end
for _, p in ipairs(Players:GetPlayers()) do watchAttrs(p, "player") if p.Character then watchAttrs(p.Character, "char") end end
if MR then conns[#conns + 1] = MR.ChildAdded:Connect(function(c) log("[MatchResults+]", c.Name, "at", os.clock()) end) end
conns[#conns + 1] = RS.ChildAdded:Connect(function(c) log("[RS+]", c.ClassName, c.Name) end)
print("[perkscan] слушаю события " .. LISTEN_SECONDS .. " с...")
task.wait(LISTEN_SECONDS)
for _, c in ipairs(conns) do c:Disconnect() end
local busy = {}
for r, n in pairs(counts) do busy[#busy + 1] = { path(r), n } end
table.sort(busy, function(a, b) return a[2] > b[2] end)
log("events received (top 25):")
for i = 1, math.min(25, #busy) do log("  ", busy[i][2], busy[i][1]) end

------------------------------------------------ итог
local text = table.concat(out, "\n")
local okw = pcall(function() writefile("VisualsHub_perkscan.txt", text) end)
local okc = pcall(function() setclipboard(text) end)
print("[perkscan] готово: " .. #out .. " строк" .. (okw and ", файл workspace/VisualsHub_perkscan.txt" or "") .. (okc and ", скопировано в буфер" or ""))
if not okw and not okc then print(text) end
