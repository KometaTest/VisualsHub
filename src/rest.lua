
local Options, Toggles = Library.Options, Library.Toggles
Library.ForceCheckbox = true

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(item)
    table.insert(self._tasks, item)
    return item
end

function Maid:Clean()
    local tasks = self._tasks
    for i = #tasks, 1, -1 do
        local t = tasks[i]
        tasks[i] = nil
        local kind = typeof(t)
        if kind == "RBXScriptConnection" then
            t:Disconnect()
        elseif kind == "Instance" then
            pcall(t.Destroy, t)
        elseif kind == "function" then
            pcall(t)
        else
            pcall(function()
                if t.Remove then t:Remove() elseif t.Destroy then t:Destroy() end
            end)
        end
    end
end

local function New(className, props)
    local inst = Instance.new(className)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end

local function SetIf(inst, prop, value)
    if inst[prop] ~= value then inst[prop] = value end
end

local function RandomName()
    return (HttpService:GenerateGUID(false):gsub("-", ""))
end

local function Escape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- [v42] дистанция в выбранных единицах (попап: Units studs/meters, 1 стад ~ 0.28 м)
local function FormatDist(d)
    if Library.Units == "meters" then return string.format("%d m", math.floor(d * 0.28 + 0.5)) end
    return string.format("%d studs", math.floor(d + 0.5))
end

local function RGBTag(color, text)
    return string.format('<font color="rgb(%d,%d,%d)">%s</font>',
        math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5), text)
end

local function ReadAttr(model, player, name)
    local v = model and model:GetAttribute(name)
    if v == nil and player then v = player:GetAttribute(name) end
    return v
end

local function GetRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function HudKey(s)
    return (string.lower(tostring(s or "")):gsub("[^%w]", ""))
end

-- "Masked" -> "Masked (Cobra)" (маска берётся из атрибута Mask персонажа киллера)
local function KillerTypeText(model, player)
    local kt = ReadAttr(model, player, "MorphedKiller")
    if type(kt) ~= "string" or kt == "" then return "" end
    if HudKey(kt) == "masked" then
        local mask = ReadAttr(model, player, "Mask")
        if type(mask) == "string" and mask ~= "" then
            kt = kt .. " (" .. mask .. ")"
        end
    end
    return kt
end

local function Truthy(v)
    return v == true or (type(v) == "string" and v ~= "") or (type(v) == "number" and v ~= 0)
end

local NotifyOnceCache = {}
local function NotifyOnce(key, text)
    if NotifyOnceCache[key] then return end
    NotifyOnceCache[key] = true
    Library:Notify({ Title = CONFIG.DisplayName, Description = text, Time = 5 })
end

local GlobalMaid = Maid.new()

local Containers = {}
do
    local root = New("Folder", { Name = RandomName() })
    local parents = {}
    pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then table.insert(parents, h) end
    end
    table.insert(parents, workspace.CurrentCamera)
    for _, p in ipairs(parents) do
        if pcall(function() root.Parent = p end) then break end
    end
    Containers.Root       = root
    Containers.Highlights = New("Folder", { Name = RandomName(), Parent = root })
    Containers.World      = New("Folder", { Name = RandomName(), Parent = root })
    GlobalMaid:Give(root)
end

-- IgnoreGuiInset = true -> координаты GUI == координаты WorldToViewportPoint
local function NewOverlayGui()
    local gui = New("ScreenGui", {
        Name = RandomName(),
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local parents = {}
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then table.insert(parents, h) end
    end
    pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
    table.insert(parents, LocalPlayer:WaitForChild("PlayerGui"))
    for _, p in ipairs(parents) do
        if pcall(function() gui.Parent = p end) then break end
    end
    return gui
end

-- линия на экране между двумя точками (Frame)
local function SetLineFrame(line, from, to, color, thickness)
    local delta = to - from
    local len = delta.Magnitude
    if len < 1 then
        line.Visible = false
        return
    end
    line.Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2)
    line.Size = UDim2.fromOffset(len, thickness)
    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
    line.BackgroundColor3 = color
    line.Visible = true
end

------------------------------------------------------------
-- Targets
------------------------------------------------------------
local Targets = {
    Survivors    = {},
    Killers      = {},
    Spectators   = {},
    Bots         = {},
    AllSurvivors = {},
    BotSet       = {},
    _lastBotScan = -math.huge,
}

local function IsBotModel(model)
    return model:IsA("Model")
        and (CollectionService:HasTag(model, "BotId") or model:FindFirstChild("BotAnimate") ~= nil)
        and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function MakeEntry(model, player)
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = GetRoot(model)
    if not hum or not root or hum.Health <= 0 then return nil end
    return {
        Model = model,
        Player = player,
        Name = player and player.Name or model.Name,
        Humanoid = hum,
        Root = root,
    }
end

function Targets.Refresh()
    local surv, kill, spec, bots = {}, {}, {}, {}
    local playerChars = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char then playerChars[char] = true end
        if plr ~= LocalPlayer and char then
            local team = plr.Team and plr.Team.Name
            local list = (team == CONFIG.Teams.Survivors and surv)
                or (team == CONFIG.Teams.Killer and kill)
                or (team == CONFIG.Teams.Spectator and spec)
            if list then
                local e = MakeEntry(char, plr)
                if e then list[#list + 1] = e end
            end
        end
    end

    local now = os.clock()
    if now - Targets._lastBotScan >= CONFIG.BotScanRate then
        Targets._lastBotScan = now
        local set = {}
        for _, inst in ipairs(CollectionService:GetTagged("BotId")) do
            local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
            if model and model:IsDescendantOf(workspace) then set[model] = true end
        end
        for _, child in ipairs(workspace:GetChildren()) do
            if not set[child] and IsBotModel(child) then set[child] = true end
        end
        Targets.BotSet = set
    end
    for model in pairs(Targets.BotSet) do
        if model.Parent and not playerChars[model] then
            local e = MakeEntry(model, nil)
            if e then bots[#bots + 1] = e end
        end
    end

    local all = table.clone(surv)
    for _, e in ipairs(bots) do all[#all + 1] = e end

    Targets.Survivors, Targets.Killers, Targets.Spectators = surv, kill, spec
    Targets.Bots, Targets.AllSurvivors = bots, all
end

------------------------------------------------------------
-- Map index
------------------------------------------------------------
local MapIndex = {
    Map = nil,
    Maid = Maid.new(),
    Sets = {
        Generators = {},
        Pallets    = {},
        Windows    = {},
        Levers     = {}, -- [v54] ExitLever (ворота выхода)
        Zombies    = {},
        Traps      = {},
        Pumpkins   = {},
        Rain       = {},
        Hooks      = {}, -- [v76] workspace.Map.Hook (Model: Hook.001 + HookPoint), по дампу Place_93978595733734
    },
}

local function ClassifyAdd(inst)
    local S = MapIndex.Sets
    local lname = string.lower(inst.Name)
    local parent = inst.Parent
    local parentIsFolder = parent ~= nil and parent:IsA("Folder")
    local plname = parent and string.lower(parent.Name) or ""

    if lname == "rain" then S.Rain[inst] = true end
    if lname == "window" and (inst:IsA("Model") or inst:IsA("Folder")) then S.Windows[inst] = true end
    -- [v54] окно с другим именем: родитель VaultTrigger / LeapVaultTrigger / VaultPointInUse, у которого есть Bottom
    -- (KillerActionController / HiddenLeapWindow / ChainWrap игры)
    if (lname == "vaulttrigger" or lname == "leapvaulttrigger" or lname == "vaultpointinuse") and parent
        and parent ~= MapIndex.Map and parent:FindFirstChild("Bottom") then
        S.Windows[parent] = true
    end
    -- [v54] workspace.Map.<ворота>.ExitLever (Main - деталь рычага)
    if lname == "exitlever" then S.Levers[inst] = true end
    -- [v76] крюк: модель Hook прямо в Map (внутри меш Hook.001 и деталь HookPoint)
    if lname == "hook" and inst:IsA("Model") then S.Hooks[inst] = true end

    -- workspace.Map.Pumpkins.Pumpkin3 ...
    if (inst:IsA("Model") or inst:IsA("BasePart"))
        and (plname == "pumpkins" or string.match(lname, "^pumpkin%d*$")) then
        S.Pumpkins[inst] = true
    end

    if inst:IsA("Model") then
        local name = inst.Name
        if string.match(lname, "^generator%d*$") or inst:GetAttribute("RepairProgress") ~= nil then
            S.Generators[inst] = true
        elseif name == "Newpallet" then
            S.Pallets[inst] = true
        end
        if string.match(lname, "^scp%d*$") or (plname == "scp" and parentIsFolder) then
            S.Zombies[inst] = true
        end
        if lname == "beartrap" or (plname == "beartrap" and parentIsFolder) then
            S.Traps[inst] = true
        end
    elseif inst:IsA("BasePart") then
        if lname == "beartrap" or (plname == "beartrap" and parentIsFolder) then
            S.Traps[inst] = true
        end
    end
end

local function ClassifyRemove(inst)
    for _, set in pairs(MapIndex.Sets) do set[inst] = nil end
end

function MapIndex.Bind(map)
    MapIndex.Maid:Clean()
    for _, set in pairs(MapIndex.Sets) do table.clear(set) end
    MapIndex.Map = map
    if not map then return end

    MapIndex.Maid:Give(map.DescendantAdded:Connect(ClassifyAdd))
    MapIndex.Maid:Give(map.DescendantRemoving:Connect(ClassifyRemove))

    local token = {}
    MapIndex.Token = token
    task.spawn(function()
        for i, d in ipairs(map:GetDescendants()) do
            if MapIndex.Token ~= token or Library.Unloaded then return end
            ClassifyAdd(d)
            if i % 3000 == 0 then task.wait() end
        end
    end)
end

local function WithoutContainers(set, filter)
    local containers = {}
    for inst in pairs(set) do
        local p = inst.Parent
        if p and set[p] then containers[p] = true end
    end
    local out = {}
    for inst in pairs(set) do
        if inst.Parent and not containers[inst] and (not filter or filter(inst)) then
            out[#out + 1] = inst
        end
    end
    return out
end

local Collect = {}

-- [v43] убрать вложенные: если объект лежит внутри другого из списка - берём только внешний
-- (иначе на одном генераторе висели две подсветки)
function Collect.Outermost(list)
    local set = {}
    for _, m in ipairs(list) do set[m] = true end
    local out = {}
    for _, m in ipairs(list) do
        local p, nested = m.Parent, false
        while p do
            if set[p] then nested = true break end
            p = p.Parent
        end
        if not nested then out[#out + 1] = m end
    end
    return out
end

-- генераторы: по индексу карты + по тегу "Generator" (игра сама их так помечает)
function Collect.Generators()
    local out, seen = {}, {}
    for m in pairs(MapIndex.Sets.Generators) do
        if m.Parent and not seen[m] then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    for _, m in ipairs(CollectionService:GetTagged("Generator")) do
        if m:IsA("Model") and not seen[m] and m:IsDescendantOf(workspace) then
            seen[m] = true
            out[#out + 1] = m
        end
    end
    return Collect.Outermost(out)
end

function Collect.Pallets()
    local out, seen = {}, {}
    -- [FIX v6] кроме моделей "Newpallet" берём модели с тегом "pallet" (PursuitPalletPredict
    -- у Slasher: CollectionService:HasTag(model, "pallet")). Нет Intact.Pallet -> подсвечиваем Intact.
    local roots = {}
    local function add(root)
        if seen[root] or not root.Parent then return end
        seen[root] = true
        roots[#roots + 1] = root
    end
    for root in pairs(MapIndex.Sets.Pallets) do add(root) end
    for _, m in ipairs(CollectionService:GetTagged("pallet")) do
        if m:IsA("Model") and m:IsDescendantOf(workspace) then add(m) end
    end
    for _, root in ipairs(Collect.Outermost(roots)) do
        -- [v43] сломанная паллета (PalletState = "Broken", PalletVisualsClient) - её больше нет, не подсвечиваем
        if root:GetAttribute("PalletState") ~= "Broken" then
            local intact = root:FindFirstChild("Intact")
            local pallet = intact and (intact:FindFirstChild("Pallet") or intact)
            if pallet then out[#out + 1] = pallet end
        end
    end
    return out
end

local WindowAdorneeCache = setmetatable({}, { __mode = "k" })

local function HasVisiblePart(inst)
    if inst:IsA("BasePart") then return inst.Transparency < 1 end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 1 then return true end
    end
    return false
end

local function WindowAdornee(w)
    local cached = WindowAdorneeCache[w]
    if cached and cached.Parent then return cached end
    local adornee = nil
    -- [v47] у окна (Window: Bottom, VaultTrigger x2, inviswall) подсвечиваем только низ - деталь Bottom
    -- (даже невидимую: раньше у окна без видимых деталей подсвечивался родитель - вся стена)
    local bottom = w:FindFirstChild("Bottom") or w:FindFirstChild("Bottom", true)
    if bottom and bottom:IsA("BasePart") then
        adornee = bottom
    elseif w:IsA("Model") and HasVisiblePart(w) then
        adornee = w
    else
        local p = w.Parent
        if p and p ~= MapIndex.Map and (p:IsA("Model") or p:IsA("BasePart")) then
            adornee = p
        elseif w:IsA("Model") then
            adornee = w
        end
    end
    WindowAdorneeCache[w] = adornee
    return adornee
end

-- [v48] окно рабочее, если у него есть VaultPoint - дочерним объектом ИЛИ тегом на детали
-- (ChainWrap / HiddenLeapWindow игры проверяют оба варианта). Заколоченные пропускаем.
function Collect.WindowOpen(w)
    if w:FindFirstChild("VaultPoint", true) or w:FindFirstChild("VaultPointInUse", true) then return true end
    for _, c in ipairs(w:GetChildren()) do
        -- [v54] + "занятое" окно (кто-то прыгает): тег VaultPointInUse, как в ChainWrap игры
        if CollectionService:HasTag(c, "VaultPoint") or CollectionService:HasTag(c, "VaultPointInUse") then return true end
    end
    return false
end

function Collect.Windows()
    local out, used = {}, {}
    -- [v48] + окна по тегу игры "vaultbox": его родитель - модель окна с Bottom (HiddenLeapWindow)
    local cand = {}
    for w in pairs(MapIndex.Sets.Windows) do cand[w] = true end
    for _, tag in ipairs({ "vaultbox", "VaultPoint", "VaultPointInUse" }) do -- [v54] + теги точек прыжка
        for _, vb in ipairs(CollectionService:GetTagged(tag)) do
            local m = vb.Parent
            if m and m ~= workspace and m:FindFirstChild("Bottom") then cand[m] = true end
        end
    end
    for w in pairs(cand) do
        if w.Parent and Collect.WindowOpen(w) then
            local adornee = WindowAdornee(w)
            if adornee and not used[adornee] then
                used[adornee] = true
                out[#out + 1] = adornee
            end
        end
    end
    return out
end

function Collect.Zombies()
    return WithoutContainers(MapIndex.Sets.Zombies, function(m)
        local hum = m:FindFirstChildOfClass("Humanoid")
        return hum == nil or hum.Health > 0
    end)
end

function Collect.Traps()
    return WithoutContainers(MapIndex.Sets.Traps)
end

function Collect.Pumpkins()
    return WithoutContainers(MapIndex.Sets.Pumpkins)
end

-- [v78] крюки (dumps/map_hooks.txt: workspace.Map.Hook - Model с Hook.001 и HookPoint) - модель целиком
function Collect.Hooks()
    return WithoutContainers(MapIndex.Sets.Hooks)
end

------------------------------------------------------------
-- Highlights (игроки + объекты)
------------------------------------------------------------
-- [CHANGED v3] Снова настоящие Roblox Highlight (силуэт + заливка, как было), но без лимита ~31:
--   * Подвижные (игроки, боты, зомби): свой Highlight на каждую модель - как в оригинале.
--   * Статичные объекты (генераторы, паллеты, окна, капканы, тыквы): ОДИН Highlight на тип.
--     Лимит Roblox считает экземпляры Highlight, а не объекты. Поэтому видимые детали всех объектов
--     типа копируются в одну модель (те же меш/текстуры/прозрачность, без коллизий/запросов/теней,
--     стоят на месте оригинала), и один Highlight подсвечивает всю модель. Позиции копий сверяются каждые UpdateRate.
-- Бюджет Highlight: CONFIG.MaxHighlights минус групповые и резерв (конус) - всё остальное игрокам.
local GHOST_RESCAN = 2 -- сек: пересбор деталей статичного объекта (паллета сломалась и т.п.)

local HighlightGroup = { All = {}, Reserved = 0 }
HighlightGroup.__index = HighlightGroup
-- [v66] эффекты ESP (src: блок «ESP FX» перед Boot): Style(prefix, model, style) - анимированный стиль подсветки,
-- Recolor[prefix](fn) - перекраска материала видимой модели. Поля таблицы, а не локалы (лимит 200 в чанке).
HighlightGroup.FX = { Recolor = {} }

local GhostRoot = New("Folder", { Name = RandomName() })
GhostRoot.Parent = workspace.CurrentCamera or workspace -- детали рендерятся только в workspace
GlobalMaid:Give(GhostRoot)

-- static = true -> групповой Highlight по копиям деталей
function HighlightGroup.new(getStyle, priority, static)
    local g = setmetatable({
        GetStyle = getStyle, Priority = priority or 5, Static = static == true,
        Map = {}, Desired = nil, Ghosts = {}, Folder = nil, Group = nil,
    }, HighlightGroup)
    table.insert(HighlightGroup.All, g)
    return g
end

function HighlightGroup:Sync(adornees)
    self.Desired = adornees
end

local function GhostDestroyRec(rec)
    for _, c in pairs(rec.Parts) do pcall(c.Destroy, c) end
    table.clear(rec.Parts)
end

function HighlightGroup:Clear()
    self.Desired = nil
    for _, h in pairs(self.Map) do pcall(h.Destroy, h) end
    table.clear(self.Map)
    for _, rec in pairs(self.Ghosts) do GhostDestroyRec(rec) end
    table.clear(self.Ghosts)
    if self.Group then pcall(self.Group.Destroy, self.Group) end
    if self.Folder then pcall(self.Folder.Destroy, self.Folder) end
    self.Group, self.Folder = nil, nil
end

local function PivotPosition(inst)
    if inst:IsA("PVInstance") then
        local ok, cf = pcall(inst.GetPivot, inst)
        if ok then return cf.Position end
    end
    return nil
end

local function ApplyStyle(h, style)
    SetIf(h, "FillColor", style.FillColor)
    SetIf(h, "FillTransparency", style.FillTransparency)
    SetIf(h, "OutlineColor", style.OutlineColor)
    SetIf(h, "OutlineTransparency", style.OutlineTransparency)
    SetIf(h, "DepthMode", style.DepthMode)
end

-- копия детали для группового Highlight: та же геометрия (MeshId/Mesh сохраняются), но невидимая
local function MakeGhost(part, folder)
    local arch = part.Archivable
    if not arch then pcall(function() part.Archivable = true end) end
    local ok, c = pcall(part.Clone, part)
    if not arch then pcall(function() part.Archivable = false end) end
    if not ok or not c then return nil end
    -- [FIX v6] оставляем всё, что влияет на вид детали (форма + текстуры), чтобы копия совпадала
    -- с оригиналом пиксель в пиксель; скрипты, звуки, промпты, вложенные детали и т.п. - удаляем
    for _, ch in ipairs(c:GetChildren()) do
        if not (ch:IsA("DataModelMesh") or ch:IsA("SurfaceAppearance") or ch:IsA("Decal")) then ch:Destroy() end
    end
    c.Name = RandomName()
    c.Anchored = true
    c.CanCollide = false
    c.CanQuery = false -- лучи (конус, трейсеры, игра) копии не видят
    c.CanTouch = false
    c.CastShadow = false
    -- [FIX v6] Прозрачность НЕ трогаем. С 0.99 Highlight рисовался только на простых Part
    -- (лампочки генератора), а MeshPart/Union (корпус генератора, паллеты, тыквы) пропадали.
    -- Копия совпадает с оригиналом, поэтому двойная отрисовка не видна.
    -- [v47] невидимая деталь, подсвеченная сама по себе (Bottom окна): с 1 Highlight не рисуется, 0.99 - да.
    -- [v48] но 0.99 Highlight рисует только у простых Part (MeshPart/Union пропадают) -> вместо копии
    -- обычный Part-коробка того же размера
    if c.Transparency >= 1 then
        pcall(c.Destroy, c)
        c = Instance.new("Part")
        c.Size = part.Size
        c.Transparency = 0.99
        c.Material = Enum.Material.SmoothPlastic
    end
    c.CFrame = part.CFrame
    c.Parent = folder
    return c
end

local function GhostSync(g, style, now)
    local desired = {}
    for _, a in ipairs(g.Desired or {}) do
        if a.Parent then desired[a] = true end
    end
    for a, rec in pairs(g.Ghosts) do
        if not desired[a] then
            GhostDestroyRec(rec)
            g.Ghosts[a] = nil
        end
    end
    if not next(desired) then
        if g.Group then SetIf(g.Group, "Enabled", false) end
        return 0
    end

    -- [FIX v5] Adornee у Highlight должен быть Model/BasePart: на Folder Highlight ничего не рисует,
    -- поэтому ESP генераторов/паллет (и остальных групповых объектов) был пустым.
    if not g.Folder or not g.Folder.Parent then
        g.Folder = New("Model", { Name = RandomName(), Parent = GhostRoot })
    end
    if not g.Group or not g.Group.Parent then
        g.Group = New("Highlight", { Name = RandomName(), Adornee = g.Folder, Parent = Containers.Highlights })
    end

    for a in pairs(desired) do
        local rec = g.Ghosts[a]
        if not rec then
            rec = { Parts = {}, NextScan = 0 }
            g.Ghosts[a] = rec
        end
        if now >= rec.NextScan then
            rec.NextScan = now + GHOST_RESCAN
            local keep = {}
            local function add(p)
                if p:IsA("BasePart") and (p.Transparency < 1 or p == a) then
                    keep[p] = true
                    if not rec.Parts[p] then rec.Parts[p] = MakeGhost(p, g.Folder) end
                end
            end
            add(a)
            for _, d in ipairs(a:GetDescendants()) do add(d) end
            for p, c in pairs(rec.Parts) do
                if not keep[p] or not p.Parent then
                    pcall(c.Destroy, c)
                    rec.Parts[p] = nil
                end
            end
        end
        for p, c in pairs(rec.Parts) do
            if c.Parent then
                local cf = p.CFrame
                if c.CFrame ~= cf then c.CFrame = cf end
                SetIf(c, "Size", p.Size)
            end
        end
    end

    ApplyStyle(g.Group, style)
    SetIf(g.Group, "Enabled", true)
    return 1
end

function HighlightGroup.Apply()
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position or Vector3.zero
    local now = os.clock()

    -- групповые (статичные) - по одному Highlight на тип
    local groupCount = 0
    for _, g in ipairs(HighlightGroup.All) do
        if g.Static then groupCount += GhostSync(g, g.GetStyle(), now) end
    end

    -- подвижные - как в оригинале, но в оставшийся бюджет
    local budget = math.max(CONFIG.MaxHighlights - groupCount - HighlightGroup.Reserved, 0)

    local requests = {}
    for _, g in ipairs(HighlightGroup.All) do
        if not g.Static and g.Desired then
            for _, adornee in ipairs(g.Desired) do
                if adornee.Parent then
                    local pos = PivotPosition(adornee)
                    requests[#requests + 1] = {
                        Group = g,
                        Adornee = adornee,
                        Distance = pos and (pos - camPos).Magnitude or math.huge,
                    }
                end
            end
        end
    end
    table.sort(requests, function(a, b)
        if a.Group.Priority ~= b.Group.Priority then return a.Group.Priority < b.Group.Priority end
        return a.Distance < b.Distance
    end)

    local granted = {}
    local used = {}
    local count = 0
    for _, r in ipairs(requests) do
        if count >= budget then break end
        if not used[r.Adornee] then
            used[r.Adornee] = true
            count += 1
            granted[r.Group] = granted[r.Group] or {}
            granted[r.Group][r.Adornee] = true
        end
    end

    for _, g in ipairs(HighlightGroup.All) do
        if not g.Static then
            local allowed = granted[g] or {}
            for adornee, h in pairs(g.Map) do
                if not allowed[adornee] then
                    pcall(h.Destroy, h)
                    g.Map[adornee] = nil
                end
            end
            if next(allowed) then
                local style = g.GetStyle()
                for adornee in pairs(allowed) do
                    local h = g.Map[adornee]
                    if not h or not h.Parent then
                        h = New("Highlight", {
                            Name = RandomName(),
                            Adornee = adornee,
                            Parent = Containers.Highlights,
                        })
                        g.Map[adornee] = h
                    end
                    local fx = g.Prefix and HighlightGroup.FX.Style -- [v66]
                    ApplyStyle(h, fx and fx(g.Prefix, adornee, style) or style)
                end
            end
        end
    end
end

------------------------------------------------------------
-- Billboard tags
------------------------------------------------------------
-- Head: над головой (имя, state, studs). Feet: под персонажем (Oneshot).
local Tags = { Map = { Head = {}, Feet = {} } }
local SLOT_ORDER = { State = 1, Parry = 2, Stun = 1, Flask = 2 }

local function AnchorOf(slot)
    return slot == "Oneshot" and "Feet" or "Head"
end

local function TagAdornee(model, anchor)
    if anchor == "Feet" then
        local root = GetRoot(model)
        if root then return root, Vector3.new(0, -3.2, 0) end
        return nil
    end
    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then return head, Vector3.new(0, 1.6, 0) end
    local root = GetRoot(model)
    if root then return root, Vector3.new(0, 3.1, 0) end
    return nil
end

function Tags.Remove(model, slot)
    local map = Tags.Map[AnchorOf(slot)]
    local rec = map[model]
    if not rec then return end
    local label = rec.Slots[slot]
    if label then
        label:Destroy()
        rec.Slots[slot] = nil
    end
    if next(rec.Slots) == nil then
        rec.Gui:Destroy()
        map[model] = nil
    end
end

function Tags.Set(model, slot, text, size, color, transparency)
    local anchor = AnchorOf(slot)
    local map = Tags.Map[anchor]
    local adornee, offset = TagAdornee(model, anchor)
    if not adornee then
        Tags.Remove(model, slot)
        return
    end

    local rec = map[model]
    if rec and not rec.Gui.Parent then
        map[model] = nil
        rec = nil
    end
    if not rec then
        local feet = anchor == "Feet"
        local gui = New("BillboardGui", {
            Name = RandomName(),
            Size = UDim2.fromOffset(300, 200),
            SizeOffset = Vector2.new(0, feet and -0.5 or 0.5),
            AlwaysOnTop = true,
            LightInfluence = 0,
            ClipsDescendants = false,
            Parent = Containers.World,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = feet and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
            Parent = gui,
        })
        rec = { Gui = gui, Slots = {}, Feet = feet }
        map[model] = rec
    end

    if rec.Gui.Adornee ~= adornee then
        rec.Gui.Adornee = adornee
        rec.Gui.StudsOffsetWorldSpace = offset
    end

    local label = rec.Slots[slot]
    if not label then
        label = New("TextLabel", {
            Name = slot,
            LayoutOrder = SLOT_ORDER[slot] or 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            RichText = true,
            Font = CONFIG.TagFont,
            TextStrokeTransparency = 0.35,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = rec.Feet and Enum.TextYAlignment.Top or Enum.TextYAlignment.Bottom,
            Text = "",
            Parent = rec.Gui,
        })
        Library:ApplyESPFont(label) -- [v62] пиксельный шрифт ESP
        rec.Slots[slot] = label
    end
    SetIf(label, "Text", text)
    SetIf(label, "TextSize", math.floor(size * (Library.ESPScale or 1) * (Library.ESPTextK or 1) + 0.5)) -- [v64] мельче
    SetIf(label, "TextColor3", color)
    SetIf(label, "TextTransparency", transparency or 0)
    SetIf(label, "TextStrokeTransparency", 0.35 + (transparency or 0) * 0.65)
end

function Tags.PruneSlot(slot, keep)
    local map = Tags.Map[AnchorOf(slot)]
    for model, rec in pairs(map) do
        if rec.Slots[slot] and not keep[model] then Tags.Remove(model, slot) end
    end
end

function Tags.RemoveSlotAll(slot)
    local map = Tags.Map[AnchorOf(slot)]
    for model in pairs(map) do Tags.Remove(model, slot) end
end

function Tags.DestroyAll()
    for _, map in pairs(Tags.Map) do
        for _, rec in pairs(map) do pcall(rec.Gui.Destroy, rec.Gui) end
        table.clear(map)
    end
end

------------------------------------------------------------
-- Stash / Features framework
------------------------------------------------------------
local Stash = {}
Stash.__index = Stash

function Stash.new()
    return setmetatable({ Items = {} }, Stash)
end

function Stash:Hide(inst)
    if self.Items[inst] or not inst.Parent then return end
    local parent = inst.Parent
    if pcall(function() inst.Parent = nil end) then
        self.Items[inst] = parent
    end
end

function Stash:RestoreAll()
    for inst, parent in pairs(self.Items) do
        if parent == game or parent:IsDescendantOf(game) then
            pcall(function() inst.Parent = parent end)
        end
    end
    table.clear(self.Items)
end

local Features = {}
local WarnedErrors = {}

local function SafeRun(f, method, ...)
    local fn = f[method]
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then
        local key = f.Id .. "." .. method
        if not WarnedErrors[key] then
            WarnedErrors[key] = true
            warn(string.format("[%s] %s failed: %s", CONFIG.ScriptName, key, tostring(err)))
        end
    end
end

-- def.Toggle = "Имя" ИЛИ def.Gate = { "Имя1", "Имя2" }
local function DefineFeature(def)
    def.Maid = Maid.new()
    def.Active = false
    def.Watch = def.Watch or {}
    table.insert(Features, def)
    return def
end

local function ApplyHighlights()
    local ok, err = pcall(HighlightGroup.Apply)
    if not ok and not WarnedErrors.Highlights then
        WarnedErrors.Highlights = true
        warn("[" .. CONFIG.ScriptName .. "] HighlightGroup.Apply failed: " .. tostring(err))
    end
end

local function SetFeatureActive(f, on)
    if f.Active == on then
        if on then SafeRun(f, "Update") end
    else
        f.Active = on
        if on then
            SafeRun(f, "Enable")
            SafeRun(f, "Update")
        else
            f.Maid:Clean()
            SafeRun(f, "Disable")
        end
    end
    if not Library.Unloaded then ApplyHighlights() end
end

------------------------------------------------------------
-- UI
------------------------------------------------------------
-- ИЗМЕНЕНО (только GUI): NeverUI в стиле Neverlose. Сайдбар с категориями, подвкладки в сайдбаре.
-- Все индексы элементов (Toggles/Options) и их значения по умолчанию - 1:1 как в Obsidian-версии,
-- фичи и старые конфиги работают без изменений.
Library.IconFolder = CONFIG.ScriptName .. "/icons" -- сюда пишутся PNG иконок (можно подложить свои)
local Window = Library:CreateWindow({
    Title = CONFIG.DisplayName, -- [v72] gamesense
    Footer = "Violence District",
    Center = true,
    AutoShow = true,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

Window:AddCategory("Visuals")
local Tabs = {}
-- [v73] всё ESP - во вкладке с солнцем (Visuals), подвкладки - иконками в «Category» сверху, как у skeet.
-- World стала подвкладкой (Tabs.World создаётся ниже, после Bot)
Tabs.Players = Window:AddTab("Visuals", "visuals", { Category = true })
Tabs.Skins   = Window:AddTab("Skinchanger", "skin") -- НОВОЕ: скинченджер (только NL-версия)
Window:AddCategory("Gameplay")
Tabs.Survivor = Window:AddTab("Survivor", "survivor")
Tabs.Killer   = Window:AddTab("Killer", "sub_killer") -- [v25] всё для игры за киллера (было в Misc)
Tabs.Misc     = Window:AddTab("Misc", "misc") -- (GUI) бывшая вкладка Camera + прицел
Window:AddCategory("Settings")
Tabs.Config = Window:AddTab("Config", "config")
-- [v72] сокращения в индикаторах слева (как DT / HS / FD у gamesense); остальные - по первым буквам
Library.ShortNames = {
    ["Moonwalk"] = "MN", ["Spear Auto-Aim"] = "AS", ["Chain Auto-Aim"] = "AC", ["Spear path + landing"] = "SL",
    ["Auto Parry"] = "AP", ["Flashlight Aim"] = "FA", ["Fullbright"] = "FB",
    -- [v83] новые функции v80-v81
    ["Auto crouch"] = "CR", ["Auto pallet"] = "PL", ["Twist of Fate aim"] = "TF", ["Smooth camera"] = "SC",
    ["Unlock cursor"] = "UC", ["Anonymous mode"] = "AN",
}

local COLORS = {
    Survivor  = Color3.fromRGB(0, 0, 205),
    Killer    = Color3.fromRGB(220, 20, 60),
    Spectator = Color3.fromRGB(255, 255, 255),
    Bot       = Color3.fromRGB(30, 144, 255),
    Generator = Color3.fromRGB(255, 215, 0),
    GenDone   = Color3.fromRGB(0, 230, 80),
    Pallet    = Color3.fromRGB(255, 140, 0),
    Window    = Color3.fromRGB(0, 200, 255),
    Zombie    = Color3.fromRGB(50, 205, 50),
    BearTrap  = Color3.fromRGB(255, 0, 255),
    Pumpkin   = Color3.fromRGB(170, 90, 255),
    Hook      = Color3.fromRGB(255, 100, 255), -- [v78]
    Knocked   = Color3.fromRGB(255, 165, 0),
    Hooked    = Color3.fromRGB(255, 60, 60),
    Hitted    = Color3.fromRGB(255, 230, 0),
    Crosshair = Color3.fromRGB(255, 255, 255),
}

local STATES = {
    { Key = "Knocked", Label = "Knocked", Color = COLORS.Knocked },
    { Key = "Hooked",  Label = "Hooked",  Color = COLORS.Hooked },
    { Key = "Hitted",  Label = "Hitted",  Color = COLORS.Hitted },
}
local ESPUI = {} -- ESP: превью-картинки страниц Players (ESPUI["SurvESP_"] = AddImage)

-- [v43] превью персонажа в «флат-позе»: детали ставятся по суставам (C0/C1) без анимации (Transform),
-- корень выравнивается по вертикали. Вызывать на копии с уже заякоренными деталями.
function ESPUI.FlatPose(model)
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    if not root then return end
    local joints = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("JointInstance") and d.Part0 and d.Part1 then
            table.insert(joints, { d.Part0, d.Part1, d.C0, d.C1 })
        elseif d:IsA("WeldConstraint") and d.Part0 and d.Part1 then
            -- у WeldConstraint нет C0/C1: держим текущее взаимное положение
            table.insert(joints, { d.Part0, d.Part1, d.Part0.CFrame:ToObjectSpace(d.Part1.CFrame), CFrame.new() })
        end
    end
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude > 1e-3 then root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit) end
    local placed = { [root] = true }
    for _ = 1, 64 do
        local changed = false
        for _, j in ipairs(joints) do
            local p0, p1, c0, c1 = j[1], j[2], j[3], j[4]
            if placed[p0] and not placed[p1] then
                p1.CFrame = p0.CFrame * c0 * c1:Inverse()
                placed[p1], changed = true, true
            elseif placed[p1] and not placed[p0] then
                p0.CFrame = p1.CFrame * c1 * c0:Inverse()
                placed[p0], changed = true, true
            end
        end
        if not changed then break end
    end
end
-- [v75] AmbienceOverlay убран: Ambience - прямо в World > Environment

-- ФИКС: у Luau лимит 200 локальных переменных на функцию, а весь скрипт - одна функция.
-- Страницы и секции меню нужны только здесь, поэтому они внутри do ... end и не занимают лимит.
do
    -- ESP (NL): секция "Model" - как Enemy Model у Neverlose: материал видимой модели,
    -- заливка за стенами и свечение. Индексы Enabled/FillColor/FillTransparency/Outline* - прежние.
    local function BuildChamsUI(box, p, color, description)
        box:AddCheckbox(p .. "Enabled", { Text = "Enabled", Default = false, Tooltip = description })
        box:AddDropdown(p .. "VisMat", {
            Text = "Visible", Values = { "Disabled", "Flat", "Neon", "Hologram", "Glass" }, Default = "Disabled",
            Tooltip = "Material of the visible model (only on your screen). Flat = plain color, Hologram = force field.",
        }):AddColorPicker(p .. "VisColor", { Default = color, Title = "Visible Color" })
        box:AddDropdown(p .. "WallMode", {
            Text = "Behind Walls", Values = { "Disabled", "Flat", "Outline" }, Default = "Flat",
            Tooltip = "Flat: color fill through walls. Outline: only the outline through walls. Disabled: not seen through walls. (Roblox draws the fill over the whole model, not only the hidden part.)",
        }):AddColorPicker(p .. "FillColor", { Default = color, Title = "Fill Color" })
            :AddSettings({ Title = "Behind Walls", Build = function(g)
                g:AddSlider(p .. "FillTransparency", { Text = "Fill Transparency", Default = 0.5, Min = 0, Max = 1, Rounding = 2 })
            end })
        box:AddCheckbox(p .. "Outline", { Text = "Glow", Default = true, Tooltip = "Glowing outline around the model." })
            :AddColorPicker(p .. "OutlineColor", { Default = color, Title = "Glow Color" })
            :AddSettings({ Title = "Glow", Build = function(g)
                g:AddSlider(p .. "OutlineTransparency", { Text = "Glow Transparency", Default = 0, Min = 0, Max = 1, Rounding = 2 })
            end })
    end

    -- [v73] ESP как «Enemy ESP» у skeet: каждый пункт - чекбокс со своим цветом (ids те же: <p>Box / BoxColor ...),
    -- бывшие «ESP Items» и цвета из «ESP» теперь одним списком
    local function BuildESPUI(box, p, color, isKiller)
        box:AddCheckbox(p .. "Box", { Text = "Bounding box", Default = false })
            :AddColorPicker(p .. "BoxColor", { Default = color, Title = "Box Color" })
            :AddSettings({ Title = "Bounding box", Build = function(g) -- [v81]
                g:AddDropdown(p .. "BoxStyle", { Text = "Box style", Values = { "Full", "Corners" }, Default = "Full" })
            end })
        box:AddCheckbox(p .. "Health", { Text = "Health bar", Default = false })
        box:AddCheckbox(p .. "HealthText", { Text = "Health text", Default = false, -- [v81]
            Tooltip = "HP number next to the box." })
        box:AddCheckbox(p .. "Name", { Text = "Name", Default = false })
            :AddColorPicker(p .. "TextColor", { Default = color, Title = "Text Color" })
        box:AddCheckbox(p .. "Studs", { Text = "Distance", Default = false })
        box:AddCheckbox(p .. "Team", { Text = "Team", Default = false, Tooltip = "SURVIVOR / KILLER / SPECTATOR / BOT under the name." }) -- [v81]
        box:AddCheckbox(p .. "Perks", { Text = "Perks", Default = false, -- [v86]
            Tooltip = "Perks (and item) under the name. In a match: only perks seen in action (seen:). After a match / in the lobby: full list from the results (last:)." })
        box:AddCheckbox(p .. "Item", { Text = "Item", Default = false, Tooltip = "Item in hands (Tool): flashlight, dagger..." })
        if isKiller then
            box:AddCheckbox(p .. "KillerType", { Text = "Killer type", Default = false, Tooltip = "Name · Veil (Masked shows the mask: Masked (Cobra))" })
        end
        box:AddSlider(p .. "TextSize", { Text = "Text size", Default = 14, Min = 8, Max = 30, Rounding = 0 })
        box:AddCheckbox(p .. "Skeleton", { Text = "Skeleton", Default = false })
            :AddColorPicker(p .. "SkeletonColor", { Default = Color3.new(1, 1, 1), Title = "Skeleton Color" })
        box:AddCheckbox(p .. "HeadDot", { Text = "Head dot", Default = false }) -- [v80]
            :AddColorPicker(p .. "HeadDotColor", { Default = color, Title = "Head Dot Color" })
        box:AddCheckbox(p .. "Tracer", { Text = "Tracer", Default = false })
            :AddColorPicker(p .. "TracerColor", { Default = color, Title = "Tracer Color" })
            :AddSettings({ Title = "Tracer", Build = function(g)
                g:AddSlider(p .. "TracerThickness", { Text = "Tracer Thickness", Default = 1, Min = 1, Max = 6, Rounding = 0 })
                g:AddDropdown(p .. "TracerOrigin", { Text = "Origin", Values = { "Bottom", "Center", "Top", "Mouse" }, Default = "Bottom" }) -- [v81]
            end })
        box:AddCheckbox(p .. "Arrow", { Text = "Off-screen arrow", Default = false })
            :AddColorPicker(p .. "ArrowColor", { Default = color, Title = "Arrow Color" })
            :AddSettings({ Title = "Offscreen Arrow", Build = function(g)
                g:AddSlider(p .. "ArrowSize", { Text = "Size", Default = 28, Min = 10, Max = 60, Rounding = 0, Suffix = "px" })
                g:AddSlider(p .. "ArrowRadius", { Text = "Distance from center", Default = 35, Min = 10, Max = 48, Rounding = 0, Suffix = "%" })
            end })
        box:AddSlider(p .. "MaxDist", { Text = "Max distance", Default = 0, Min = 0, Max = 1000, Rounding = 0, Suffix = " studs", -- [v81]
            Tooltip = "Name / distance / tracer / box / skeleton only for targets closer than this. 0 = no limit." })
    end

    local function BuildConeUI(box)
        box:AddCheckbox("Cone_Enabled", {
            Text = "Floor Cone", Default = false,
            Tooltip = "Flat sector on the floor at the killer's feet (like the terror radius), drawn as a flat overlay: visible through walls. Fill = Killer Chams fill color, outline = Killer Chams outline color. Angle = half-angle.",
        })
        box:AddSlider("Cone_Range", { Text = "Cone range", Default = 32, Min = 1, Max = 100, Rounding = 0 })
        box:AddSlider("Cone_Angle", { Text = "Cone angle", Default = 30, Min = 1, Max = 89, Rounding = 0 })
        -- [NEW] заливка и контур отдельно
        box:AddCheckbox("Cone_Fill", { Text = "Cone fill", Default = true })
        box:AddSlider("Cone_Transparency", { Text = "Cone fill transparency", Default = 0.8, Min = 0, Max = 0.95, Rounding = 2 }) -- [v11] 0.8: не закрывает обзор
        box:AddCheckbox("Cone_Outline", { Text = "Cone outline", Default = true })
    end

    local function BuildHiddenUI(box)
        -- (GUI) метка "Hidden" стала заголовком секции
        -- [CHANGED] Default = true: функции со скриншота включены в KillerHUD по умолчанию
        box:AddCheckbox("HiddenLeap_Enabled", {
            Text = "Leap Tracer", Default = true,
            Tooltip = "Predicted arc of Hidden's Leap (ability 2): where he will land.",
        }):AddColorPicker("HiddenLeap_Color", { Default = Color3.fromRGB(0, 200, 255), Title = "Leap Color" })
        box:AddCheckbox("HiddenMark_Enabled", {
            Text = "Mark Tracer", Default = true,
            Tooltip = "Predicted line of Hidden's Mark dash (ability 1): where it will hit.",
        }):AddColorPicker("HiddenMark_Color", { Default = Color3.fromRGB(255, 80, 80), Title = "Mark Color" })
        box:AddSlider("HiddenPredict_Thickness", { Text = "Tracer thickness", Default = 2, Min = 1, Max = 6, Rounding = 0 })
        box:AddCheckbox("HiddenInvis_Enabled", {
            Text = "Invisible Tag", Default = true,
            Tooltip = "Shows 'Invisible' over Hidden while he is invisible, removes it when visible.",
        }):AddColorPicker("HiddenInvis_Color", { Default = Color3.fromRGB(190, 160, 255), Title = "Invisible Color" })
    end


    -- VISUALS > Players: подвкладки Survivor / Killer / Spectator / Bot (были вкладками Tabbox "Players")
    local SurvPage   = Tabs.Players:AddSubTab("Survivor", "cat_team") -- [v73] иконки Category
    local KillerPage = Tabs.Players:AddSubTab("Killer", "cat_enemy")
    local SpecPage   = Tabs.Players:AddSubTab("Spectator", "cat_eye")
    local BotPage    = Tabs.Players:AddSubTab("Bot", "cat_bot")
    Tabs.World       = Tabs.Players:AddSubTab("World", "cat_world") -- [v73] была отдельной вкладкой

    -- [v73] как у skeet: на подвкладке два групбокса - слева «... ESP» (всё ESP / состояния / абилки), справа
    -- «... models» (чамсы + эффекты, эффекты добавляет блок ESP FX ниже через ESPUI.ModelBox)
    ESPUI.ModelBox = {}
    local SurvESPBox = SurvPage:AddLeftGroupbox("Survivor ESP")
    ESPUI.ModelBox.Survivors = SurvPage:AddRightGroupbox("Survivor models")
    BuildChamsUI(ESPUI.ModelBox.Survivors, "SurvChams_", COLORS.Survivor, "Team Survivors")
    BuildESPUI(SurvESPBox, "SurvESP_", COLORS.Survivor, false)
    local SurvStateBox = SurvESPBox
    -- [v73] подсказка-надпись убрана
    for _, s in ipairs(STATES) do
        SurvStateBox:AddCheckbox("SurvState_" .. s.Key, { Text = s.Label, Default = false })
            :AddColorPicker("SurvState_" .. s.Key .. "Color", { Default = s.Color, Title = s.Label .. " Color" })
    end
    -- [v41] прогресс-строки (данные с сервера): крюк, лечение, вырывание
    SurvStateBox:AddCheckbox("SurvState_HookInfo", { Text = "Hook stage + %", Default = false,
        Tooltip = "Over a hooked survivor: hook stage (HookCount) and struggle/sacrifice progress (HookedProgress)." })
    SurvStateBox:AddCheckbox("SurvState_HealInfo", { Text = "Heal / recover %", Default = false,
        Tooltip = "Over a survivor being healed or self-recovering: HealProgress (0-100)." })
    SurvStateBox:AddCheckbox("SurvState_WiggleInfo", { Text = "Wiggle %", Default = false,
        Tooltip = "Over a carried survivor: wiggle progress ((16 - RemainingCarryTime)/16, carry lasts 16s)." })
    SurvStateBox:AddSlider("SurvState_TextSize", { Text = "State Text Size", Default = 15, Min = 8, Max = 30, Rounding = 0 })

    -- [v41] состояние киллера + радиус террора (Players > Killer)
    local KillerESPBox = KillerPage:AddLeftGroupbox("Killer ESP") -- [v73]
    ESPUI.ModelBox.Killer = KillerPage:AddRightGroupbox("Killer models")
    BuildChamsUI(ESPUI.ModelBox.Killer, "KillerChams_", COLORS.Killer, "Team Killer")
    BuildESPUI(KillerESPBox, "KillerESP_", COLORS.Killer, true)
    local KillerStateBox = KillerESPBox
    KillerStateBox:AddCheckbox("KillerState_Stun", { Text = "Stunned", Default = false,
        Tooltip = "'STUNNED' over a killer while IsStunned is set (pallet / flashlight stun)." })
        :AddColorPicker("KillerState_StunColor", { Default = Color3.fromRGB(80, 200, 255), Title = "Stun color" })
    KillerStateBox:AddCheckbox("KillerState_Blind", { Text = "Blinded", Default = false, -- [v81]
        Tooltip = "'BLINDED 60%' over a killer blinded by a flashlight (Blindness attribute, FlashBlindEffect)." })
        :AddColorPicker("KillerState_BlindColor", { Default = Color3.fromRGB(255, 240, 150), Title = "Blind color" })
    -- [v47] из Animations.lua Cure: flaskcharge/flaskidle = целится колбой, после flaskthrow кулдаун 15с
    KillerStateBox:AddCheckbox("KillerState_Flask", { Text = "Cure flask", Default = false,
        Tooltip = "Over Cure: 'FLASK' while he aims a flask (charge/idle anims), then the 15s flask cooldown." })
        :AddColorPicker("KillerState_FlaskColor", { Default = Color3.fromRGB(110, 230, 80), Title = "Flask color" })
    KillerStateBox:AddCheckbox("TerrorRing_Enabled", { Text = "Terror radius ring", Default = false,
        Tooltip = "Ring on the ground of the killer's real terror radius (TerrorRadius attribute)." })
        :AddColorPicker("TerrorRing_Color", { Default = Color3.fromRGB(255, 70, 70), Title = "Terror ring color" })
    KillerStateBox:AddSlider("KillerState_TextSize", { Text = "State text size", Default = 15, Min = 8, Max = 30, Rounding = 0 }) -- [v73] в общем списке

    BuildConeUI(KillerESPBox)
    -- [NEW v13] ESP абилок киллеров (в NL - рядом с остальным ESP киллера)
    local AbilityBox = KillerESPBox -- [v73]
    AbilityBox:AddCheckbox("AbilityESP_Wave", {
        Text = "Corrupt Wave (Abyssal)", Default = true,
        Tooltip = "Highlights the flying Corrupt wave and draws its path to the end of its range.",
    }):AddColorPicker("AbilityESP_WaveColor", { Default = Color3.fromRGB(170, 60, 255), Title = "Wave Color" })
    AbilityBox:AddCheckbox("AbilityESP_VeilSpear", {
        Text = "Spear path (Veil)", Default = true,
        Tooltip = "Predicted path of an enemy Veil spear while he charges, and of the thrown spear.",
    }):AddColorPicker("AbilityESP_VeilColor", { Default = Color3.fromRGB(255, 120, 40), Title = "Spear Color" })
    AbilityBox:AddCheckbox("AbilityESP_VeilWarn", { -- [v65] вариант C
        Text = "Spear warning", Default = true,
        Tooltip = "When the spear path goes through you: the path turns red with a danger corridor, a 'SPEAR' warning shows in the middle of the screen (time to hit once thrown) and an arrow at the screen edge points to Veil if he is off-screen.",
    }):AddColorPicker("AbilityESP_VeilWarnColor", { Default = Color3.fromRGB(255, 70, 70), Title = "Warning Color" })
    AbilityBox:AddCheckbox("AbilityESP_CorruptAim", {
        Text = "Corrupt aim (Abyssal)", Default = true,
        Tooltip = "While the knight casts Corrupt: predicted wave line (where it will fly).",
    })
    -- [v37] Cure: путь колбы шлёт сервер целиком (VisualizeFlask "launch": Points + StartedAt, летит 70 ст/с)
    AbilityBox:AddCheckbox("AbilityESP_Flask", {
        Text = "Flask path (Cure)", Default = true,
        Tooltip = "Exact path of a thrown Cure flask (sent by the server), where it lands and where it is now.",
    }):AddColorPicker("AbilityESP_FlaskColor", { Default = Color3.fromRGB(110, 230, 80), Title = "Flask Color" })
    -- [v37] Butcher: цепь летит прямо 140 ст/с до 50 стад (ChainProjectile); полёт шлёт сервер (ChainState)
    AbilityBox:AddCheckbox("AbilityESP_Chain", {
        Text = "Chain (Butcher)", Default = true,
        Tooltip = "Exact line of a flying Butcher chain (sent by the server): where its tip is now and where it stops (50 studs or a wall).",
    }):AddColorPicker("AbilityESP_ChainColor", { Default = Color3.fromRGB(255, 170, 60), Title = "Chain Color" })

    -- (GUI) Hidden-трейсеры - та же подсветка абилок киллера, рядом с ESP Abilities
    BuildHiddenUI(KillerESPBox) -- [v73]

    local SpecESPBox = SpecPage:AddLeftGroupbox("Spectator ESP") -- [v73]
    ESPUI.ModelBox.Spectators = SpecPage:AddRightGroupbox("Spectator models")
    BuildChamsUI(ESPUI.ModelBox.Spectators, "SpecChams_", COLORS.Spectator, "Team Spectator")
    BuildESPUI(SpecESPBox, "SpecESP_", COLORS.Spectator, false)

    local BotESPBox = BotPage:AddLeftGroupbox("Bot ESP") -- [v73]
    ESPUI.ModelBox.Bots = BotPage:AddRightGroupbox("Bot models")
    BuildChamsUI(ESPUI.ModelBox.Bots, "BotChams_", COLORS.Bot, "NPC survivors (BotId tag / BotAnimate)")
    BuildESPUI(BotESPBox, "BotESP_", COLORS.Bot, false)

    -- VISUALS > World
    local ObjectBox = Tabs.World:AddLeftGroupbox("World ESP") -- [v73] два групбокса: World ESP и Environment
    -- [v73] подсказка-надпись убрана
    ObjectBox:AddSlider("Object_Fill", {
        Text = "Fill Transparency", Default = CONFIG.ObjectFillTransparency, Min = 0, Max = 1, Rounding = 2,
    })
    ObjectBox:AddSlider("Object_Outline", {
        Text = "Outline Transparency", Default = CONFIG.ObjectOutlineTransparency, Min = 0, Max = 1, Rounding = 2,
    })
    ObjectBox:AddDivider()
    ObjectBox:AddCheckbox("GenChams_Enabled", { Text = "Generator ESP", Default = false })
        :AddColorPicker("GenChams_Color", { Default = COLORS.Generator, Title = "Generator Color" })
    -- [v54] цвет ESP генератора по прогрессу, как у индикатора: красный -> жёлтый -> зелёный
    ObjectBox:AddCheckbox("GenChams_Gradient", { Text = "Generator color by progress", Default = true,
        Tooltip = "Red -> yellow -> green by RepairProgress (same as the progress bar). Off: Generator / Done colors." })
    ObjectBox:AddLabel("Generator Done Color"):AddColorPicker("GenChams_DoneColor", {
        Default = COLORS.GenDone, Title = "Repaired Generator Color",
    })
    ObjectBox:AddCheckbox("PalletChams_Enabled", { Text = "Pallet ESP", Default = false })
        :AddColorPicker("PalletChams_Color", { Default = COLORS.Pallet, Title = "Pallet Color" })
    ObjectBox:AddCheckbox("PumpkinChams_Enabled", {
        Text = "Pumpkin ESP", Default = false, Tooltip = "workspace.Map.Pumpkins.*",
    }):AddColorPicker("PumpkinChams_Color", { Default = COLORS.Pumpkin, Title = "Pumpkin Color" })
    ObjectBox:AddCheckbox("WindowChams_Enabled", {
        Text = "Window ESP", Default = false, Tooltip = "Boarded windows (no VaultPoint) are skipped",
    }):AddColorPicker("WindowChams_Color", { Default = COLORS.Window, Title = "Window Color" })
    ObjectBox:AddCheckbox("ZombieChams_Enabled", { Text = "Zombie ESP", Default = false })
        :AddColorPicker("ZombieChams_Color", { Default = COLORS.Zombie, Title = "Zombie Color" })
    ObjectBox:AddCheckbox("TrapChams_Enabled", { Text = "BearTrap ESP", Default = false })
        :AddColorPicker("TrapChams_Color", { Default = COLORS.BearTrap, Title = "BearTrap Color" })
    ObjectBox:AddCheckbox("HookChams_Enabled", { Text = "Hook ESP", Default = false, -- [v78]
        Tooltip = "workspace.Map.Hook" }):AddColorPicker("HookChams_Color", { Default = COLORS.Hook, Title = "Hook Color" })

    local GenBox = ObjectBox -- [v73] был отдельный групбокс Generator Progress
    GenBox:AddCheckbox("GenProgress_Enabled", {
        Text = "Generator Repair Progress", Default = false,
        Tooltip = "Custom progress bar under every generator (RepairProgress attribute)",
    })
    GenBox:AddCheckbox("GateProgress_Enabled", { Text = "Exit Gate Progress", Default = false,
        Tooltip = "Same bar over the exit gate lever (ExitLever). Shows 'In progress' while IsBeingProgressed is set." })
    GenBox:AddCheckbox("GenProgress_Percent", { Text = "Show Percent", Default = true })
    GenBox:AddCheckbox("GenProgress_ETA", { Text = "Show time left", Default = true, -- [v65]
        Tooltip = "Time until the generator is done, from how fast its progress is going up right now." })
    GenBox:AddCheckbox("GenProgress_Gradient", {
        Text = "Color By Progress", Default = true, -- [v54] снова по умолчанию: красный -> зелёный, как ESP генератора
        Tooltip = "Red -> yellow -> green. Off: generator ESP color (done color when repaired).",
    })
    GenBox:AddSlider("GenProgress_Width", {
        Text = "Bar Width", Default = 110, Min = 50, Max = 240, Rounding = 0, Suffix = "px",
    })
    GenBox:AddSlider("GenProgress_Height", {
        Text = "Bar Offset", Default = 0, Min = -4, Max = 4, Rounding = 1, Suffix = " studs",
        Tooltip = "0 = right under the generator",
    })

    local WorldBox = Tabs.World:AddRightGroupbox("Environment")
    ESPUI.EnvBox = WorldBox -- [v75] кнопки Ambience нет: всё из неё - прямо в Environment (блок Ambience ниже)
    WorldBox:AddCheckbox("World_NoFog", { Text = "Delete Fog", Default = false })
    WorldBox:AddCheckbox("World_NoBlur", { Text = "No Blur", Default = false })
    WorldBox:AddCheckbox("World_NoShadows", { Text = "No Shadows", Default = false })
    WorldBox:AddCheckbox("World_NoRain", { Text = "No Rain", Default = false })
    -- [v81] из Ambient.lua
    WorldBox:AddCheckbox("World_Blur", { Text = "Blur effect", Default = false, Tooltip = "Your own screen blur (not removed by No Blur)." })
    WorldBox:AddSlider("World_BlurSize", { Text = "Blur size", Default = 4, Min = 1, Max = 24, Rounding = 0 })
    WorldBox:AddCheckbox("World_LowGfx", { Text = "Low graphics", Default = false,
        Tooltip = "Map: plain materials, no textures / decals / surface maps, no particles; no terrain grass. Restored when off." })


    -- GAMEPLAY > Misc: Camera, Crosshair | As Killer
    -- [v91] Misc разбит на подвкладки: в одной колонке было 5 групбоксов, каждый сжимался до мелкой клетки со скроллом.
    -- View: Camera + Crosshair | Self Chams.  HUD: HUD | Indicators + Cosmetics.  Other: Hitsounds | Interface (+ Lua).
    Tabs.MiscView  = Tabs.Misc:AddSubTab("View", "cat_eye")
    Tabs.MiscHud   = Tabs.Misc:AddSubTab("HUD", "cat_fx")
    Tabs.MiscOther = Tabs.Misc:AddSubTab("Other", "cat_world")
    local CameraBox = Tabs.MiscView:AddLeftGroupbox("Camera")
    CameraBox:AddCheckbox("FOV_Enabled", { Text = "Enable FOV", Default = false })
    CameraBox:AddSlider("FOV_Value", { Text = "FOV", Default = 90, Min = 30, Max = 120, Rounding = 0 })
    -- [v80] плавность камеры игры: атрибут CameraStiffness у character.SmoothCamera (дефолт 8, SurvivorAnimationsController)
    -- [v81] Smooth camera как у Ambient.lua: камера догоняет персонажа с запаздыванием, мёртвая зона, возврат на месте
    CameraBox:AddCheckbox("Cam_Smooth", { Text = "Smooth camera", Default = false, BindIcon = "kb_eye",
        Tooltip = "Third-person camera follows your character with a lag (dead zone, follow speed, return when standing). Bind it (right-click)." })
        :AddSettings({ Title = "Smooth camera", Build = function(g)
            g:AddSlider("Cam_Deadzone", { Text = "Deadzone radius", Default = 2, Min = 0, Max = 10, Rounding = 1, Suffix = " studs",
                Tooltip = "The camera does not move while your character stays within this distance of it." })
            g:AddSlider("Cam_FollowSpeed", { Text = "Follow lag speed", Default = 7, Min = 1, Max = 30, Rounding = 1,
                Tooltip = "How fast the camera catches up. Lower = more lag." })
            g:AddSlider("Cam_IdleReturn", { Text = "Idle return", Default = 4, Min = 0, Max = 20, Rounding = 1,
                Tooltip = "How fast the camera re-centers when you stand still. 0 = off." })
        end })
    -- [v80] плавность камеры игры: атрибут CameraStiffness у character.SmoothCamera (дефолт 8)
    CameraBox:AddCheckbox("Cam_StiffOn", { Text = "Game camera stiffness", Default = false,
        Tooltip = "Survivor camera follow speed of the game itself (CameraStiffness, default 8). Lower = smoother. Only you." })
    CameraBox:AddSlider("Cam_Stiffness", { Text = "Camera stiffness", Default = 4, Min = 1, Max = 20, Rounding = 1 })

    local CrosshairBox = Tabs.MiscView:AddLeftGroupbox("Crosshair") -- [v60] слева под Camera (справа - Theme / Interface)
    -- CROSSHAIR: тумблер + цвет + «...» с настройками прицела. По умолчанию - прежний кружок.
    CrosshairBox:AddCheckbox("Crosshair_Enabled", { Text = "Crosshair", Default = false })
        :AddColorPicker("Crosshair_Color", { Default = COLORS.Crosshair, Title = "Crosshair Color" })
        :AddSettings({ Title = "Crosshair", Build = function(g)
            g:AddCheckbox("Crosshair_Cross", { Text = "Cross", Default = false })
            g:AddCheckbox("Crosshair_TShape", { Text = "T-Shape", Default = false, Tooltip = "Cross without the top line" })
            g:AddCheckbox("Crosshair_Circle", { Text = "Circle", Default = true })
            g:AddCheckbox("Crosshair_Dot", { Text = "Center Dot", Default = false })
            g:AddCheckbox("Crosshair_Outline", { Text = "Outline", Default = false, Tooltip = "Black outline, visible on bright backgrounds" })
            g:AddSlider("Crosshair_Size", { Text = "Size", Default = 5, Min = 1, Max = 30, Rounding = 0, Tooltip = "Circle radius / line length" })
            g:AddSlider("Crosshair_Gap", { Text = "Gap", Default = 3, Min = 0, Max = 20, Rounding = 0 })
            g:AddSlider("Crosshair_Thickness", { Text = "Thickness", Default = 1.5, Min = 1, Max = 6, Rounding = 1 })
            g:AddSlider("Crosshair_Transparency", { Text = "Transparency", Default = 0, Min = 0, Max = 0.9, Rounding = 2 })
            -- [v78] как у конкурента: прицел только при прицеливании (атрибут персонажа Aiming ставят
            -- Twist of Fate, Holy Water, Gate, Riot Shield, Bandage - по дампам; spearmode у киллера - из их кода)
            g:AddCheckbox("Crosshair_OnlyAim", { Text = "Only when aiming", Default = false,
                Tooltip = "Shown only while your character is aiming an item (Aiming) or a killer spear (spearmode)." })
            g:AddCheckbox("Crosshair_AimTOF", { Text = "Twist of Fate only", Default = false,
                Tooltip = "Survivor: only while aiming Twist of Fate (not Holy Water / Gate / Riot Shield / Bandage)." })
            -- [v80] анимации и цвет (как у Ambient.lua)
            g:AddSlider("Crosshair_Spin", { Text = "Spin speed", Default = 0, Min = 0, Max = 720, Rounding = 0, Suffix = " deg/s",
                Tooltip = "0 = no spin." })
            g:AddCheckbox("Crosshair_Pulse", { Text = "Pulse", Default = false, Tooltip = "Size grows and shrinks." })
            g:AddSlider("Crosshair_PulseSpeed", { Text = "Pulse speed", Default = 2, Min = 0.5, Max = 8, Rounding = 1, Suffix = " Hz" })
            g:AddCheckbox("Crosshair_Rainbow", { Text = "Rainbow", Default = false })
            g:AddCheckbox("Crosshair_Accent", { Text = "Menu color", Default = false, Tooltip = "Use the menu accent color." })
            g:AddCheckbox("Crosshair_HideCursor", { Text = "Hide game cursor", Default = false,
                Tooltip = "Hides the mouse icon while the menu is closed." })
            -- [v81] остальное из Ambient.lua
            g:AddSlider("Crosshair_StaticRot", { Text = "Static rotation", Default = 0, Min = 0, Max = 90, Rounding = 0, Suffix = " deg" })
            g:AddSlider("Crosshair_RainbowSpeed", { Text = "Rainbow speed", Default = 25, Min = 5, Max = 200, Rounding = 0, Suffix = "%" })
            g:AddSlider("Crosshair_PulseAmp", { Text = "Pulse amplitude", Default = 25, Min = 5, Max = 80, Rounding = 0, Suffix = "%" })
            g:AddDropdown("Crosshair_DotShape", { Text = "Dot shape", Values = { "Square", "Circle" }, Default = "Square" })
            g:AddDropdown("Crosshair_Position", { Text = "Position", Values = { "Center", "Mouse" }, Default = "Center" })
            g:AddSlider("Crosshair_OffsetX", { Text = "Offset X", Default = 0, Min = -300, Max = 300, Rounding = 0, Suffix = "px" })
            g:AddSlider("Crosshair_OffsetY", { Text = "Offset Y", Default = 0, Min = -300, Max = 300, Rounding = 0, Suffix = "px" })
            g:AddCheckbox("Crosshair_Dynamic", { Text = "Dynamic movement", Default = false,
                Tooltip = "Lines move apart while you run (gap grows with your speed)." })
            g:AddSlider("Crosshair_Spread", { Text = "Spread multiplier", Default = 8, Min = 1, Max = 30, Rounding = 0 })
            g:AddCheckbox("Crosshair_Image", { Text = "Image (decal)", Default = false,
                Tooltip = "Shows a Roblox image instead of the lines / circle / dot." })
            g:AddInput("Crosshair_ImageId", { Text = "Image ID", Default = "4463666440", Placeholder = "rbxassetid number" })
            g:AddSlider("Crosshair_ImageSize", { Text = "Image size", Default = 32, Min = 8, Max = 200, Rounding = 0, Suffix = "px" })
            g:AddLabel("Image tint"):AddColorPicker("Crosshair_ImageTint", { Default = Color3.new(1, 1, 1), Title = "Image tint" })
            g:AddSlider("Crosshair_ImageOpacity", { Text = "Image opacity", Default = 100, Min = 5, Max = 100, Rounding = 0, Suffix = "%" })
        end })

    -- [v67] Self Chams: всё твоё тело (как Hand Chams, видно в третьем лице); руки остаются за Hand Chams, если он включён
    local SelfBox = Tabs.MiscView:AddRightGroupbox("Self Chams")
    SelfBox:AddCheckbox("SelfChams_Enabled", { Text = "Self Chams", Default = false,
        Tooltip = "Recolors your whole character (third person). Only you see it." })
        :AddColorPicker("SelfChams_Color", { Default = Color3.fromRGB(120, 170, 255), Title = "Body Color" })
    SelfBox:AddDropdown("SelfChams_Material", { Text = "Material",
        Values = { "ForceField", "Neon", "Glass", "SmoothPlastic", "Foil", "Ice", "Metal" }, Default = "ForceField" })
    SelfBox:AddSlider("SelfChams_Transparency", { Text = "Transparency", Default = 0, Min = 0, Max = 90, Rounding = 0, Suffix = "%" })
    SelfBox:AddCheckbox("SelfChams_Rainbow", { Text = "Rainbow", Default = false, Tooltip = "Body color cycles through the hue wheel." })
    SelfBox:AddSlider("SelfChams_RainbowSpeed", { Text = "Rainbow speed", Default = 25, Min = 5, Max = 100, Rounding = 0, Suffix = "%" })
    SelfBox:AddCheckbox("SelfChams_NoTextures", { Text = "Remove clothes / face", Default = true,
        Tooltip = "Hides shirt, pants, face and texture maps so the color shows cleanly." })
    SelfBox:AddDropdown("SelfChams_Accessories", { Text = "Accessories", Values = { "Chams", "Keep", "Hide" }, Default = "Chams",
        Tooltip = "Hats / hair: recolor with the body, leave as is, or hide." })
    SelfBox:AddCheckbox("SelfChams_Outline", { Text = "Outline", Default = false, Tooltip = "Glowing outline around your character." })
        :AddColorPicker("SelfChams_OutlineColor", { Default = Color3.fromRGB(255, 255, 255), Title = "Outline Color" })
    SelfBox:AddCheckbox("SelfChams_Aura", { Text = "Aura", Default = false })
        :AddColorPicker("SelfChams_AuraColor", { Default = Color3.fromRGB(190, 150, 255), Title = "Aura Color" })
    SelfBox:AddCheckbox("SelfChams_Trail", { Text = "Trail", Default = false })
        :AddColorPicker("SelfChams_TrailColor", { Default = Color3.fromRGB(120, 170, 255), Title = "Trail Color" })
    SelfBox:AddSlider("SelfChams_TrailLength", { Text = "Trail length", Default = 1, Min = 0.2, Max = 4, Rounding = 1, Suffix = "s" })

    -- [v60] перед Hitsounds (большой групбокс - последним в колонке, листается он)
    -- [v42] индикатор замедления (атрибут speedboost < 1)
    local IndBox = Tabs.MiscHud:AddRightGroupbox("Indicators")
    IndBox:AddCheckbox("SlowIndicator_Enabled", { Text = "SLOW indicator", Default = false,
        Tooltip = "Shows 'SLOW' in the left indicator list while you are slowed (speedboost < 1): chain slow, stun, etc." })
        :AddColorPicker("SlowIndicator_Color", { Default = Color3.fromRGB(255, 90, 60), Title = "Slow color" })
    -- [v72] хит-логи как у gamesense (слева сверху, двигаются при открытом меню)
    IndBox:AddCheckbox("HitLog_Enabled", { Text = "Hit logs", Default = false,
        Tooltip = "Event log in the top-left corner (like gamesense). Drag it while the menu is open." })
    IndBox:AddDropdown("HitLog_Events", { Text = "Log events", Multi = true,
        Values = { "Hit", "Down", "Got hit", "Hook", "Parry", "Stun" },
        Default = { "Hit", "Down", "Got hit", "Hook", "Parry", "Stun" } })
    IndBox:AddSlider("HitLog_Time", { Text = "Log duration", Default = 5, Min = 2, Max = 10, Rounding = 0, Suffix = "s" })

    -- [v75] HUD: хитмаркер, цифры урона, компас угрозы, радар, статистика сессии, таймер погони
    local HudBox = Tabs.MiscHud:AddLeftGroupbox("HUD")
    HudBox:AddCheckbox("Hud_Hitmarker", { Text = "Hit marker", Default = false,
        Tooltip = "Cross at the crosshair when you hit (white), down (red) or parry (menu color)." })
        :AddColorPicker("Hud_HitmarkerColor", { Default = Color3.new(1, 1, 1), Title = "Hit marker" })
        :AddSettings({ Title = "Hit marker", Build = function(g)
            g:AddSlider("Hud_HitmarkerSize", { Text = "Size", Default = 10, Min = 4, Max = 24, Rounding = 0, Suffix = "px" })
        end })
    HudBox:AddCheckbox("Hud_DamageNum", { Text = "Damage numbers", Default = false, Tooltip = "'-25' floats up over the survivor you hit." })
        :AddColorPicker("Hud_DamageNumColor", { Default = Color3.fromRGB(255, 225, 120), Title = "Damage numbers" })
    HudBox:AddCheckbox("Hud_Compass", { Text = "Threat compass", Default = false,
        Tooltip = "Arcs around the crosshair point to killers (also behind you); closer = thicker and redder." })
        :AddColorPicker("Hud_CompassColor", { Default = Color3.fromRGB(255, 200, 80), Title = "Far color" })
        :AddSettings({ Title = "Threat compass", Build = function(g)
            g:AddSlider("Hud_CompassRadius", { Text = "Radius", Default = 90, Min = 40, Max = 300, Rounding = 0, Suffix = "px" })
            g:AddSlider("Hud_CompassRange", { Text = "Range", Default = 90, Min = 20, Max = 300, Rounding = 0, Suffix = " studs" })
            g:AddCheckbox("Hud_CompassSurv", { Text = "Show survivors (as killer)", Default = true })
        end })
    HudBox:AddCheckbox("Hud_Radar", { Text = "Radar", Default = false, Tooltip = "Mini map; drag it while the menu is open." })
        :AddSettings({ Title = "Radar", Build = function(g)
            g:AddSlider("Hud_RadarRange", { Text = "Range", Default = 120, Min = 40, Max = 400, Rounding = 0, Suffix = " studs" })
            g:AddSlider("Hud_RadarSize", { Text = "Size", Default = 170, Min = 110, Max = 320, Rounding = 0, Suffix = "px" })
            g:AddCheckbox("Hud_RadarRotate", { Text = "Rotate with camera", Default = true })
        end })
    HudBox:AddDropdown("Hud_RadarShow", { Text = "Radar shows", Multi = true,
        Values = { "Killer", "Survivors", "Generators", "Pallets", "Exit gates", "Hooks" }, -- [v76] Hooks
        Default = { "Killer", "Survivors", "Generators", "Exit gates", "Hooks" } })
    HudBox:AddCheckbox("Hud_Stats", { Text = "Session stats", Default = false,
        Tooltip = "Panel with hits, downs, parries, stuns and chase time this session; drag it while the menu is open." })
        :AddSettings({ Title = "Session stats", Build = function(g)
            g:AddButton({ Text = "Reset stats", Func = function() if ESPUI.ResetStats then ESPUI.ResetStats() end end })
        end })
    HudBox:AddCheckbox("Hud_Chase", { Text = "Chase timer", Default = false,
        Tooltip = "'CHASE 0:12' in the left indicators while a killer chases you (closing in on you and sees you, or right next to you)." })
    -- [v86] перки игроков во время матча (ReplicatedStorage.MatchResults: атрибут Perks = JSON [{name, level}])
    HudBox:AddCheckbox("Hud_Perks", { Text = "Perks panel", Default = false,
        Tooltip = "Players' perks and items. During a match the server does not send other players' perks, so only perks seen in action are shown (Built different, Snake Step, High Karma, Flowstate, Visual Learner, Enhanced Senses). Full list - on the results screen and in the lobby (last match). Drag it while the menu is open." })
    -- [v87] перки на карточках выживших слева снизу (SurvivorHUD игры: Survivor1..5, атрибут UserId)
    HudBox:AddCheckbox("Hud_CardPerks", { Text = "Perks on portraits", Default = false,
        Tooltip = "Perk icons on survivor portraits in the game's HUD (bottom left). During a match only perks seen in action (Built different, Snake Step, High Karma, Flowstate, Visual Learner, Enhanced Senses). Only on your screen." })
        :AddSettings({ Title = "Perks on portraits", Build = function(g)
            g:AddDropdown("Hud_CardPerksPos", { Text = "Position", Values = { "Above", "Below", "Inside" }, Default = "Above",
                Tooltip = "Above / below the portrait, or over its bottom edge." })
            g:AddSlider("Hud_CardPerksSize", { Text = "Icon size", Default = 100, Min = 60, Max = 160, Rounding = 0, Suffix = "%",
                Tooltip = "100% = a third of the portrait width." })
            g:AddCheckbox("Hud_CardPerksBg", { Text = "Dark background", Default = true })
        end })
    -- [v91] предмет выжившего у его карточки (иконка из ReplicatedStorage.Items + заряд / речарж, где игра его отдаёт)
    HudBox:AddCheckbox("Hud_CardItems", { Text = "Items on portraits", Default = false,
        Tooltip = "Item icon to the left of each survivor portrait (bottom left) with its charge / recharge where the game shares it: flashlight seconds left, bandage charge, Twist of Fate shots, adrenaline used, Monkey Paw recharge, dagger cooldown (+N s = blocked until the killer chains it, the game gives no time). Only on your screen." })
        :AddSettings({ Title = "Items on portraits", Build = function(g)
            g:AddSlider("Hud_CardItemsSize", { Text = "Icon size", Default = 100, Min = 60, Max = 160, Rounding = 0, Suffix = "%",
                Tooltip = "100% = 40% of the portrait width." })
            g:AddCheckbox("Hud_CardItemsText", { Text = "Charge / recharge text", Default = true })
        end })
    -- [v80] из Ambient.lua: полоска здоровья Roblox, свободный курсор
    HudBox:AddCheckbox("AimFX_Circle", { Text = "Aim FOV circle", Default = false, -- [v80]
        Tooltip = "While an aim helper works (spear, Twist of Fate, flashlight): circle of its aim FOV around the crosshair." })
        :AddColorPicker("AimFX_Color", { Default = Color3.new(1, 1, 1), Title = "FOV circle" })
    HudBox:AddCheckbox("AimFX_Dots", { Text = "Aim target dots", Default = false,
        Tooltip = "Dots on the heads of possible targets of the aim helper; the picked target is bigger and red." })
    HudBox:AddCheckbox("Hud_HideHealth", { Text = "Hide Roblox health bar", Default = false })
    -- [v81] (v77 в архиве не было) ники в HUD выживших (SurvivorHUD: карточки Survivor1..5, TextLabel = имя)
    HudBox:AddCheckbox("Hud_Anon", { Text = "Anonymous mode", Default = false,
        Tooltip = "Your name is replaced with the nickname everywhere in the game's GUI (survivor cards, lobby, results) and in the watermark. Only on your screen." })
        :AddSettings({ Title = "Anonymous mode", Build = function(g)
            g:AddInput("Hud_AnonName", { Text = "Nickname", Default = "Me", Placeholder = "nickname" })
            g:AddCheckbox("Hud_AnonAll", { Text = "Hide other names too", Default = false, Tooltip = "Others become Player 1..5." })
            -- [v91]
            g:AddCheckbox("Hud_AnonGrey", { Text = "Grey characters", Default = false, -- [v92]
                Tooltip = "Everyone (you too) looks like a plain grey dummy: grey body, no clothes / accessories / textures. Skinchanger wins on your own character. Only on your screen." })
            g:AddCheckbox("Hud_AnonDummy", { Text = "Grey dummy portraits", Default = false,
                Tooltip = "Every survivor portrait in the HUD shows a plain grey dummy instead of the real avatar." })
            g:AddCheckbox("Hud_AnonLevel", { Text = "Spoof level", Default = false,
                Tooltip = "Your level in the game's GUI (lobby badge, results) shows the number below. Only on your screen." })
            g:AddSlider("Hud_AnonLevelValue", { Text = "Level", Default = 1, Min = 1, Max = 999, Rounding = 0 })
        end })
    HudBox:AddCheckbox("Hud_UnlockCursor", { Text = "Unlock cursor", Default = false, BindIcon = "kb_key",
        Tooltip = "Mouse is free (not locked to the center) while on. Bind it to a key (right-click)." })
    -- [v78] как KillerInfo у конкурента: ник киллера, его персонаж и платформа (атрибуты игрока SelectedKiller / platform)
    HudBox:AddCheckbox("Hud_KillerInfo", { Text = "Killer info", Default = false,
        Tooltip = "When a new killer shows up (round start): their name, killer and platform at the top of the screen." })
        :AddSettings({ Title = "Killer info", Build = function(g)
            g:AddSlider("Hud_KillerInfoTime", { Text = "Duration", Default = 6, Min = 2, Max = 15, Rounding = 0, Suffix = "s" })
            g:AddCheckbox("Hud_KillerInfoKiller", { Text = "Show when you are the killer", Default = false })
        end })

    -- [v78] косметика из скрипта конкурента: только у тебя на экране / в ушах, другие игроки не видят
    ESPUI.CosBox = Tabs.MiscHud:AddRightGroupbox("Cosmetics")
    ESPUI.CosBox:AddCheckbox("Cos_Medkit", { Text = "DBD medkit", Default = false,
        Tooltip = "Your bandage looks like a Dead by Daylight medkit. Only you see it." })
    -- [v80] цвета аур самой игры: атрибуты LocalPlayer genaura / survaura / spikeaura / leveraura / killeraura /
    -- bloodpoolscolor (дамп: Highlight-new, BloodPoolColor, настройки Preferences). Только у тебя.
    ESPUI.CosBox:AddCheckbox("GameAura_Enabled", { Text = "Game aura colors", Default = false,
        Tooltip = "Recolors the game's own auras (what you see through walls from perks / as killer) and blood pools. Applies to auras that appear after the change." })
        :AddSettings({ Title = "Game aura colors", Build = function(g)
            g:AddLabel("Generators"):AddColorPicker("GameAura_Gen", { Default = Color3.fromRGB(255, 215, 0), Title = "Generators" })
            g:AddLabel("Survivors"):AddColorPicker("GameAura_Surv", { Default = Color3.fromRGB(80, 160, 255), Title = "Survivors" })
            g:AddLabel("Hooks / spikes"):AddColorPicker("GameAura_Hook", { Default = Color3.fromRGB(255, 100, 255), Title = "Hooks / spikes" })
            g:AddLabel("Exit gate levers"):AddColorPicker("GameAura_Lever", { Default = Color3.fromRGB(80, 255, 140), Title = "Exit levers" })
            g:AddLabel("Killer"):AddColorPicker("GameAura_Killer", { Default = Color3.fromRGB(255, 50, 50), Title = "Killer" })
            g:AddLabel("Blood pools"):AddColorPicker("GameAura_Blood", { Default = Color3.fromRGB(93, 0, 2), Title = "Blood pools" })
        end })
    ESPUI.CosBox:AddCheckbox("Cos_TripleT", { Text = "Triple T", Default = false,
        Tooltip = "Loads the 'Triple T' model (asset 123969132800771) on your body and hides your character. Only you see it." })

    -- [v40] Hitsounds: локальный звук тебе при попадании / сбитии / парри (24 звука вшиты, getcustomasset)
    local HS_NAMES = HITSOUNDS_ORDER or {}
    local HitBox = Tabs.MiscOther:AddLeftGroupbox("Hitsounds")
    HitBox:AddCheckbox("Hitsound_Hit", {
        Text = "Hit (you hurt a survivor)", Default = false,
        Tooltip = "Plays a sound for you (only you hear it) the moment a survivor loses health while you are the killer near them.",
    })
    local function HS_def(name) return (table.find(HS_NAMES, name) and name) or HS_NAMES[1] end
    HitBox:AddDropdown("Hitsound_HitSound", { Text = "Hit sound", Values = HS_NAMES, Default = HS_def("nl hitsound") })
    HitBox:AddCheckbox("Hitsound_Down", { Text = "Down (survivor knocked)", Default = false })
    HitBox:AddDropdown("Hitsound_DownSound", { Text = "Down sound", Values = HS_NAMES, Default = HS_def("bonk") })
    HitBox:AddCheckbox("Hitsound_Parry", { Text = "Parry (your successful parry)", Default = false })
    HitBox:AddDropdown("Hitsound_ParrySound", { Text = "Parry sound", Values = HS_NAMES, Default = HS_def("satisfying click") })
    HitBox:AddSlider("Hitsound_Volume", { Text = "Volume", Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
    HitBox:AddSlider("Hitsound_Pitch", { Text = "Pitch", Default = 100, Min = 50, Max = 200, Rounding = 0, Suffix = "%" })
    HitBox:AddCheckbox("Hitsound_PitchByDamage", { Text = "Pitch by damage", Default = false,
        Tooltip = "Higher tone the more damage the hit dealt (like CS hitsounds)." })
    HitBox:AddButton({ Text = "Test hit sound", Func = function() if ESPUI.TestHitsound then ESPUI.TestHitsound() end end })

    -- (GUI) функции для игры за киллера
    local KillerExploits = Tabs.Killer:AddLeftGroupbox("General") -- [v25] из Misc -> Gameplay > Killer
    KillerExploits:AddCheckbox("AntiBlind_Enabled", {
        Text = "Anti Blind",
        Default = false,
        Tooltip = "Disables the LocalScript Slasher.Blind.blinded. Re-enabled when toggled off.",
    })
    KillerExploits:AddCheckbox("NoBlindVFX_Enabled", {
        Text = "No Blind VFX",
        Default = false,
        Tooltip = "Hides Slasher.Blind (Visible = false). Restored when toggled off.",
    })

    -- [NEW v24] Veil (играешь за Veil): авто-наводка копья и место падения
    local VeilKillerBox = Tabs.Killer:AddRightGroupbox("Veil") -- [v25] из Misc -> Gameplay > Killer
    VeilKillerBox:AddCheckbox("SpearAim_Enabled", {
        Text = "Spear Auto-Aim", Default = false, BindIcon = "kb_target",
        Tooltip = "While you charge the spear, the camera aims it at the survivor nearest to your crosshair: lead for their movement and the drop for the current charge, so the throw lands on them.",
    })
    VeilKillerBox:AddDropdown("SpearAim_Mode", {
        Text = "Aim mode", Values = { "Default", "Legit" }, Default = "Default",
        Tooltip = "Default: aims for you. Legit: does not move your view, only shows a marker where to put your crosshair and throw.",
    })
    VeilKillerBox:AddSlider("SpearAim_FOV", {
        Text = "Aim FOV", Default = 45, Min = 5, Max = 180, Rounding = 0, Suffix = " deg",
        Tooltip = "Only survivors within this angle from your crosshair are picked.",
    })
    -- [v26] камера больше не «прыгает»: наводим мышью (как будто ты сам повёл), плавно
    VeilKillerBox:AddSlider("SpearAim_Smooth", {
        Text = "Aim smoothness", Default = 60, Min = 0, Max = 90, Rounding = 0, Suffix = "%",
        Tooltip = "0% = instant, higher = smoother. Aim turns your view like your own mouse would, so it does not jump back after the throw.",
    })
    VeilKillerBox:AddDropdown("SpearAim_Part", { Text = "Aim at", Values = { "Body", "Head", "Legs" }, Default = "Body", -- [v81]
        Tooltip = "Which point of the survivor the spear goes to." })
    VeilKillerBox:AddCheckbox("SpearAim_Predict", {
        Text = "Predict movement", Default = true,
        Tooltip = "Throws ahead of the survivor: uses their speed and direction and the spear flight time, so a running target walks into the spear.",
    })
    VeilKillerBox:AddSlider("SpearAim_PredictScale", {
        Text = "Prediction", Default = 100, Min = 0, Max = 200, Rounding = 0, Suffix = "%",
        Tooltip = "100% = exact lead for their current speed. Lower if you overshoot (they stop / turn a lot), higher if you hit behind them.",
    })
    VeilKillerBox:AddCheckbox("SpearLand_Enabled", {
        Text = "Spear path + landing", Default = false, BindIcon = "kb_cross", -- [v65] дуга + кольцо (вариант A)
        Tooltip = "While you charge the spear: its flight arc and a circle where it will land.",
    }):AddColorPicker("SpearLand_Color", { Default = Color3.fromRGB(255, 70, 70), Title = "Landing Color" })
    VeilKillerBox:AddCheckbox("SpearLand_Info", { Text = "Distance + flight time", Default = false, -- [v80]
        Tooltip = "While you charge the spear: distance to the landing point and how long the spear flies, next to the landing point (needs Spear path + landing)." })

    -- [v37] Butcher: авто-наводка цепи (как у копья Veil, но цепь летит прямо - без падения)
    local ButcherKillerBox = Tabs.Killer:AddLeftGroupbox("Butcher")
    ButcherKillerBox:AddCheckbox("ChainAim_Enabled", {
        Text = "Chain Auto-Aim", Default = false, BindIcon = "kb_target",
        Tooltip = "Aims the chain at the survivor nearest to your crosshair with lead (chain: 140 studs/s, 50 studs, from your head). Bind it in Hold mode and hold while you throw.",
    })
    ButcherKillerBox:AddDropdown("ChainAim_Mode", {
        Text = "Aim mode", Values = { "Default", "Legit" }, Default = "Default",
        Tooltip = "Default: aims for you. Legit: only shows a marker where to put your crosshair.",
    })
    ButcherKillerBox:AddSlider("ChainAim_FOV", { Text = "Aim FOV", Default = 45, Min = 5, Max = 180, Rounding = 0, Suffix = " deg" })
    ButcherKillerBox:AddSlider("ChainAim_Smooth", { Text = "Aim smoothness", Default = 50, Min = 0, Max = 90, Rounding = 0, Suffix = "%" })
    ButcherKillerBox:AddCheckbox("ChainAim_Predict", { Text = "Predict movement", Default = true })

    -- [v37] кулдауны кинжалов выживших (parryResult сервер шлёт всем: успех, кулдаун, перманентный, сброс, персонаж)
    local SurvInfoBox = Tabs.Killer:AddLeftGroupbox("Survivors")
    SurvInfoBox:AddCheckbox("ParryESP_Enabled", {
        Text = "Parry timers", Default = false,
        Tooltip = "Over survivors with a Parrying Dagger: 'PARRY!' while they parry, the dagger cooldown, or 'Dagger ready'. Swing when it is on cooldown.",
    }):AddColorPicker("ParryESP_Color", { Default = Color3.fromRGB(255, 200, 70), Title = "Ready / parry color" })
    SurvInfoBox:AddSlider("ParryESP_TextSize", { Text = "Text size", Default = 14, Min = 8, Max = 30, Rounding = 0 })

    -- GAMEPLAY > Survivor: подвкладки Main / Dodger
    -- [v43] Abysswalker / Veil / Cure / Butcher + кинжал (Auto Parry, Fake Dagger) - в одной подвкладке Dodger
    local SurvMain = Tabs.Survivor:AddSubTab("Main", "sub_survivor")
    local SurvMove = Tabs.Survivor:AddSubTab("Movement", "sub_survivor") -- [v90] Moonwalk переехал сюда
    local Dodger   = Tabs.Survivor:AddSubTab("Dodger", "sub_abyss")

    local SurvivorExploits = SurvMain:AddLeftGroupbox("Exploits")
    SurvivorExploits:AddCheckbox("AutoSkillCheck_Enabled", {
        Text = "Auto SkillCheck",
        Default = false,
        Tooltip = "Automatically hits skill checks (Survivors team only).",
    })
    -- [NEW] режимы автоскиллчека
    SurvivorExploits:AddDropdown("AutoSkillCheck_Mode", {
        Text = "SkillCheck mode",
        Values = { "Default", "Legit" },
        Default = "Default",
        Tooltip = "Default: hits Great on the first possible tick (as before). Legit: sometimes Good (grey), Great is hit later inside the zone.",
    })
    SurvivorExploits:AddSlider("AutoSkillCheck_LegitGreat", {
        Text = "Legit: Great chance", Default = 70, Min = 0, Max = 100, Rounding = 0, Suffix = "%",
    })
    SurvivorExploits:AddSlider("AutoSkillCheck_LegitGood", {
        Text = "Legit: Good zone width", Default = 12, Min = 2, Max = 40, Rounding = 0, Suffix = " deg",
        Tooltip = "Width of the grey (Good) part after the white (Great) part. Tune if Legit hits Great or misses instead of Good.",
    })

    -- [NEW v24] Parrying Dagger: авто-парри (Items.ParryingDagger.ParryClient)
    local ParryBox = Dodger:AddRightGroupbox("Auto Parry")
    ParryBox:AddCheckbox("AutoParry_Enabled", {
        Text = "Auto Parry", Default = false, BindIcon = "kb_shield",
        Tooltip = "Parrying Dagger in hands: parries the moment the killer starts an attack (its attack / lunge animations are read from the killer's Animations script). Same rules as the game: HP >= 50%, not busy, not on cooldown.",
    })
    -- [v64] режим: Legit / Rage выставляют настройки ниже (потом их можно подкрутить - режим станет Custom)
    ParryBox:AddDropdown("AutoParry_Mode", { Text = "Mode", Values = { "Legit", "Rage", "Custom" }, Default = "Custom",
        Tooltip = "Legit: human-like (delay 70 + random reaction, 92% chance, only killers on screen, no camera snap). Rage: every attack, instantly after the 70 ms delay, turns camera to the killer. Custom: your own settings." })
    -- [v34] по логике AutoDagger: радиус 14 (в нём слайдер 10..18), угол 360 = без проверки
    ParryBox:AddSlider("AutoParry_Distance", {
        Text = "Parry distance", Default = 14, Min = 6, Max = 20, Rounding = 1, Suffix = " studs",
        Tooltip = "Killer must start the attack this close to you.",
    })
    ParryBox:AddSlider("AutoParry_Angle", {
        Text = "Parry angle", Default = 360, Min = 20, Max = 360, Rounding = 0, Suffix = " deg",
        Tooltip = "Killer must face you within this cone (full angle). 360 = any direction.",
    })
    ParryBox:AddCheckbox("AutoParry_ShowRange", {
        Text = "Show range", Default = true,
        Tooltip = "Circle on the ground around you = parry distance.",
    }):AddColorPicker("AutoParry_Color", { Default = Color3.fromRGB(0, 255, 100), Title = "Range Color" })
    ParryBox:AddDropdown("AutoParry_CircleStyle", { Text = "Circle style", Values = { "Threat", "Dotted", "Solid" }, Default = "Threat", -- [v39] [v75] Threat
        Tooltip = "Threat: the lit part of the ring points to the nearest killer and grows / turns red as he gets closer; an inner ring fills up to the edge right when he will reach your parry range; the ring flashes on a successful parry." })
    ParryBox:AddCheckbox("AutoParry_ShowAngle", {
        Text = "Show angle", Default = false,
        Tooltip = "Cone in front of the nearest killer (only when Parry angle < 360).",
    })
    ParryBox:AddCheckbox("AutoParry_Guess", {
        Text = "Guess unknown attacks", Default = true,
        Tooltip = "If the killer's attack animations can't be read (no decompile in your executor): learn them from hits you take and react to lunges / swing animations.",
    })
    ParryBox:AddSlider("AutoParry_Early", {
        Text = "Parry early", Default = 250, Min = 0, Max = 800, Rounding = 0, Suffix = " ms",
        Tooltip = "Only for learned attacks: how long before the hit to parry.",
    })
    -- [v39] как у Ambient: задержка, хуманизация, компенсация пинга
    -- [v48] сколько ждать после начала зажатия удара (lungehold), если киллер уже в радиусе
    ParryBox:AddSlider("AutoParry_HoldWait", {
        Text = "Lunge wait", Default = 0, Min = 0, Max = 300, Rounding = 0, Suffix = " ms",
        Tooltip = "Killer started holding attack (lunge) within range: parry after this long. 0 = at once (catches quick taps); higher = catches long full-hold lunges.",
    })
    ParryBox:AddSlider("AutoParry_Delay", {
        Text = "Delay", Default = 70, -- [v64] 70: раньше парри уходило слишком рано и удар попадал в кулдаун Min = 0, Max = 300, Rounding = 0, Suffix = " ms",
        Tooltip = "Wait this long after the attack is detected before parrying (0 = instantly).",
    })
    -- [v58] легитность
    ParryBox:AddSlider("AutoParry_React", {
        Text = "Reaction (random)", Default = 0, Min = 0, Max = 200, Rounding = 0, Suffix = " ms",
        Tooltip = "Adds a random 0..this delay to every parry, like a human reaction. Keep it under ~120 ms or quick taps will land first.",
    })
    ParryBox:AddSlider("AutoParry_Chance", {
        Text = "Parry chance", Default = 100, Min = 50, Max = 100, Rounding = 0, Suffix = "%",
        Tooltip = "Sometimes don't parry on purpose so it doesn't look perfect.",
    })
    ParryBox:AddCheckbox("AutoParry_OnScreen", {
        Text = "Only if killer on screen", Default = false,
        Tooltip = "Don't parry attacks from a killer you can't see on your screen (behind you).",
    })
    ParryBox:AddCheckbox("AutoParry_Predict", {
        Text = "Predict lunge", Default = true,
        Tooltip = "Uses the killer's real closing speed to parry exactly when he'll be in range by the time your parry reaches the server (ping + delays), instead of a fixed 27 studs/s.",
    })
    ParryBox:AddCheckbox("AutoParry_Humanize", {
        Text = "Humanize delay (±10ms)", Default = false,
        Tooltip = "Adds a random ±10 ms to every parry so the timing is never perfectly the same.",
    })
    ParryBox:AddCheckbox("AutoParry_PingComp", {
        Text = "Ping compensation", Default = false,
        Tooltip = "Parries earlier by your ping: Delay is reduced by it, learned attacks are parried earlier by it.",
    })
    ParryBox:AddButton({ Text = "Forget learned attacks", Func = function()
        if ESPUI.ParryLearned then table.clear(ESPUI.ParryLearned) end
        pcall(function() if delfile and isfile and isfile(CONFIG.ScriptName .. "/parry_anims.json") then delfile(CONFIG.ScriptName .. "/parry_anims.json") end end)
    end })
    ParryBox:AddCheckbox("AutoParry_Face", {
        Text = "Face the killer", Default = true,
        Tooltip = "Turns the camera to the killer for the parry (the game turns you to where the camera looks).",
    })
    ParryBox:AddCheckbox("AutoParry_Log", {
        Text = "Log parries (F9)", Default = false,
        Tooltip = "Prints why a parry fired and the server result (cooldown / success) to F9 - send it if timing is off.",
    })
    -- [v64] пресеты режимов. Delay 70 мс в обоих: меньше - парри уходит раньше удара, окно 0.8с кончается,
    -- а дальше кинжал в кулдауне и удар проходит.
    ESPUI.ParryPresets = {
        Legit = { AutoParry_Distance = 13, AutoParry_Angle = 180, AutoParry_HoldWait = 0, AutoParry_Delay = 70,
            AutoParry_React = 40, AutoParry_Chance = 92, AutoParry_OnScreen = true, AutoParry_Predict = true,
            AutoParry_Humanize = true, AutoParry_PingComp = false, AutoParry_Face = false, AutoParry_Guess = true },
        Rage = { AutoParry_Distance = 16, AutoParry_Angle = 360, AutoParry_HoldWait = 0, AutoParry_Delay = 70,
            AutoParry_React = 0, AutoParry_Chance = 100, AutoParry_OnScreen = false, AutoParry_Predict = true,
            AutoParry_Humanize = false, AutoParry_PingComp = false, AutoParry_Face = true, AutoParry_Guess = true },
    }
    ESPUI.ApplyingPreset = false
    Options.AutoParry_Mode:OnChanged(function()
        local pr = ESPUI.ParryPresets[Options.AutoParry_Mode.Value]
        if not pr then return end
        ESPUI.ApplyingPreset = true
        for idx, v in pairs(pr) do
            pcall(function()
                if type(v) == "boolean" then Toggles[idx]:SetValue(v) else Options[idx]:SetValue(v) end
            end)
        end
        ESPUI.ApplyingPreset = false
    end)
    -- ручная правка любой настройки -> режим Custom
    for idx, v in pairs(ESPUI.ParryPresets.Legit) do
        local el = type(v) == "boolean" and Toggles[idx] or Options[idx]
        if el then
            el:OnChanged(function()
                if ESPUI.ApplyingPreset then return end
                local mode = Options.AutoParry_Mode.Value
                local pr = ESPUI.ParryPresets[mode]
                if pr and pr[idx] ~= nil and pr[idx] ~= el.Value then Options.AutoParry_Mode:SetValue("Custom") end
            end)
        end
    end

    -- [NEW v24] Moonwalk: лицом к камере, зажатый S и быстрый A/D ([v90] в подвкладке Movement)
    local MoveBox = SurvMove:AddLeftGroupbox("Movement")
    MoveBox:AddCheckbox("Moonwalk_Enabled", {
        Text = "Moonwalk", Default = false, BindIcon = "kb_run",
        Tooltip = "Your character keeps looking forward (where the camera looks) while it holds S and spams A/D, so it walks backwards. Best bound to a key in Hold mode (right-click).",
    })
    MoveBox:AddSlider("Moonwalk_Rate", {
        Text = "A/D switch", Default = 70, Min = 20, Max = 300, Rounding = 0, Suffix = " ms",
        Tooltip = "How often A and D swap.",
    })
    MoveBox:AddSlider("Moonwalk_Random", {
        Text = "Randomize", Default = 5, Min = 0, Max = 25, Rounding = 0, Suffix = " deg",
        Tooltip = "Humanization: every step turns a bit differently (e.g. 37° left, 44° right, 41°...) and the A/D timing varies a little. 0 = perfectly even.",
    })
    MoveBox:AddSlider("Moonwalk_Sway", {
        Text = "Body sway", Default = 40, Min = 0, Max = 80, Rounding = 0, Suffix = " deg",
        Tooltip = "How much the body turns toward each A / D step (like a manual moonwalk). 0 = looks straight forward.",
    })
    MoveBox:AddCheckbox("Moonwalk_Stutter", { -- [v39]
        Text = "Stutters", Default = false,
        Tooltip = "Random micro-pauses (50-150 ms, all keys released) now and then, like a real hand losing the rhythm.",
    })

    -- [v80] Auto Crouch / Auto Pallet (из Ambient.lua): жмут клавиши игры (KeybindsConfig crouch / droppallet)
    ESPUI.AutoBox = SurvMain:AddLeftGroupbox("Auto")
    ESPUI.AutoBox:AddCheckbox("AutoCrouch_Enabled", { Text = "Auto crouch", Default = false, BindIcon = "kb_shield",
        Tooltip = "Crouches by itself (game crouch key, hold or toggle mode) while a killer is within the radius; stands up when he leaves. The game only lets you crouch above 50 HP." })
    ESPUI.AutoBox:AddSlider("AutoCrouch_Radius", { Text = "Crouch radius", Default = 40, Min = 5, Max = 120, Rounding = 0, Suffix = " studs" })
    ESPUI.AutoBox:AddCheckbox("AutoCrouch_Facing", { Text = "Only if killer looks at you", Default = false,
        Tooltip = "Crouch only while the killer faces you (within 60 degrees)." })
    ESPUI.AutoBox:AddCheckbox("AutoPallet_Enabled", { Text = "Auto pallet", Default = false, BindIcon = "kb_shield",
        Tooltip = "Presses the game's drop-pallet key when you stand at an upright pallet and the killer comes within the radius." })
    ESPUI.AutoBox:AddSlider("AutoPallet_Radius", { Text = "Killer distance", Default = 9, Min = 3, Max = 30, Rounding = 0, Suffix = " studs",
        Tooltip = "Drop when the killer is this close to you." })
    ESPUI.AutoBox:AddSlider("AutoPallet_Reach", { Text = "Pallet reach", Default = 6, Min = 2, Max = 12, Rounding = 0, Suffix = " studs",
        Tooltip = "How close you must be to the pallet. Lower it if it presses the key too far away." })
    ESPUI.AutoBox:AddCheckbox("AutoPallet_Facing", { Text = "Only if killer looks at you", Default = true })
    ESPUI.AutoBox:AddCheckbox("AutoPallet_Closing", { Text = "Only if killer closes in", Default = true,
        Tooltip = "Drop only while the killer is getting closer (chasing), not when he walks away." })
    ESPUI.AutoBox:AddCheckbox("AutoPallet_Lunge", { Text = "Drop on lunge", Default = true, -- [v81]
        Tooltip = "Also drop when the killer lunges at you (closes in faster than 22 studs/s) up to 6 studs beyond the killer distance." })

    -- [v39] Fake Dagger: анимация парри кинжала без самого парри (приманка)
    local FakeBox = Dodger:AddRightGroupbox("Fake Dagger")
    FakeBox:AddCheckbox("FakeDagger_Enabled", {
        Text = "Fake Dagger", Default = false,
        Tooltip = "Press the key: your character plays the dagger parry animation (everyone sees it), but no parry is sent - the killer waits or wastes the lunge.",
    }):AddKeyPicker("FakeDagger_Key", { Default = "Z", Text = "Fake Dagger" })
    FakeBox:AddCheckbox("FakeDagger_Face", {
        Text = "Face camera direction", Default = true,
        Tooltip = "Turns your character to where the camera looks before the fake, like the real parry.",
    })
    FakeBox:AddDropdown("FakeDagger_Preset", {
        Text = "Animation", Values = { "Auto", "Parry", "Parry hit" }, Default = "Auto",
        Tooltip = "Auto / Parry = the dagger's parry animation (useanim). Parry hit = its successful-parry animation (parriedanim).",
    })
    FakeBox:AddSlider("FakeDagger_Freeze", { Text = "Freeze duration", Default = 1.2, Min = 0.2, Max = 3, Rounding = 1, Suffix = " s",
        Tooltip = "How long you stand in the pose (a real parry locks you for 0.8 s)." })
    FakeBox:AddSlider("FakeDagger_Speed", { Text = "Animation speed", Default = 1, Min = 0.5, Max = 2, Rounding = 1, Suffix = "x" })
    FakeBox:AddSlider("FakeDagger_Cooldown", { Text = "Cooldown", Default = 0.5, Min = 0, Max = 5, Rounding = 1, Suffix = " s" })

    local SurvivorMisc = SurvMain:AddRightGroupbox("Killer HUD")
    SurvivorMisc:AddCheckbox("KillerHUD_Enabled", {
        Text = "Killer HUD", Default = false,
        Tooltip = "Per-killer info panel (Veil: spears / ability cooldown / charge; Hidden: Leap + Mark cooldowns; Masked: mask swap timer; Stalker: stage / timer / grab / stalk % / target; Butcher: traps / chain; Slasher: mist / pursuit; Killer: frenzy / power / debug; Abysswalker: slash / corrupt). Drag it to move.",
    })
    -- [v73] подсказка-надпись убрана
    local ChaseBox = SurvMain:AddRightGroupbox("Chase Preview") -- (GUI) индикатор для выжившего, рядом с Killer HUD
    ChaseBox:AddCheckbox("ChasePreview_Enabled", {
        Text = "ChasePreview",
        Default = true,
        Tooltip = "Shows 'In chase' when you are being chased (IsChasing attribute / killer target).",
    })

    -- [CHANGED v10] Abysswalker: Slash (рывок) -> присед, Corrupt (волна) -> уход вбок
    local SlashBox = Dodger:AddLeftGroupbox("Abysswalker")
    SlashBox:AddCheckbox("DodgeAbyss_Slash", {
        Text = "Autododge Slash (Abyssal)", Default = false,
        Tooltip = "Knight Slashes at you: crouches exactly at the hit (0.8s after Slash starts), stands up right after the hit window.",
    })
    -- [NEW v11] упреждение приседа до удара (пинг + время, за которое персонаж садится)
    SlashBox:AddSlider("DodgeAbyss_SlashLead", {
        Text = "Slash crouch lead", Default = 120, Min = 0, Max = 400, Rounding = 0, Suffix = " ms",
        Tooltip = "How early before the hit (0.8s after Slash starts) to crouch. Raise it if you still get hit, lower it to crouch later.",
    })
    local CorruptBox = SlashBox
    CorruptBox:AddCheckbox("DodgeAbyss_Corrupt", {
        Text = "Autododge Corrupt (Abyssal)", Default = false,
        Tooltip = "Corrupt windup aimed at you (predicted wave line) / its wave flying at you: takes over movement and strafes you out of the wave line.",
    })
    -- [v58] общие настройки ухода: реакция, «своя сторона», стены, анти-застревание
    local DodgeLegit = Dodger:AddRightGroupbox("Dodge Behaviour")
    DodgeLegit:AddSlider("Dodge_React", {
        Text = "Reaction (random)", Default = 0, Min = 0, Max = 200, Rounding = 0, Suffix = " ms",
        Tooltip = "Starts every dodge after a random 0..this delay, like a human. Too high and fast projectiles land first.",
    })
    DodgeLegit:AddCheckbox("Dodge_TrustMe", {
        Text = "Don't press if I already dodge", Default = true,
        Tooltip = "If you're already moving off the threat line yourself, the script doesn't press anything.",
    })
    -- [v73] подсказка-надпись убрана
    local DodgeDebug = Dodger:AddRightGroupbox("Debug")
    DodgeDebug:AddCheckbox("Dodge_Logger", {
        Text = "Log killer animations", Default = false,
        Tooltip = "Prints every new animation the killer plays (id, name, length, distance) to F9. Use it to collect ability IDs.",
    })
    -- [v73] подсказка-надпись убрана

    -- [NEW v14] Veil: додж копья
    local SpearBox = Dodger:AddLeftGroupbox("Veil")
    SpearBox:AddCheckbox("DodgeVeil_Spear", {
        Text = "Autododge Spear (Veil)", Default = false,
        Tooltip = "At the moment Veil throws a spear whose path hits your body: strafes you off the spear line.",
    })
    SpearBox:AddCheckbox("DodgeVeil_Charge", {
        Text = "Dodge while charging", Default = true,
        Tooltip = "Start strafing while Veil is still charging if his aim goes through you (the spear is too fast to dodge after the throw at close range).",
    })
    SpearBox:AddSlider("DodgeVeil_Margin", {
        Text = "Body margin", Default = 1.5, Min = 0, Max = 5, Rounding = 1, Suffix = " studs",
        Tooltip = "Extra size around your body parts when checking the spear path (spear hitboxes are your body parts).",
    })

    -- [v37] Cure / Butcher: додж колбы и цепи по точным данным сервера
    local FlaskBox = Dodger:AddLeftGroupbox("Cure")
    FlaskBox:AddCheckbox("DodgeCure_Flask", {
        Text = "Autododge Flask (Cure)", Default = false,
        Tooltip = "When a thrown flask's path (sent by the server) goes through you: strafes you off its line before it arrives.",
    })
    FlaskBox:AddCheckbox("DodgeCure_Aim", {
        Text = "Dodge while aiming", Default = true,
        Tooltip = "Start strafing while Cure is still aiming the flask if its predicted arc (same math as the game) goes through you.",
    })
    FlaskBox:AddSlider("DodgeCure_Margin", {
        Text = "Body margin", Default = 1.5, Min = 0, Max = 5, Rounding = 1, Suffix = " studs",
    })
    local ChainBox = Dodger:AddLeftGroupbox("Butcher")
    ChainBox:AddCheckbox("DodgeButcher_Chain", {
        Text = "Autododge Chain (Butcher)", Default = false,
        Tooltip = "Chain flies 140 studs/s up to 50 studs (hit radius 1). When a flying chain's line goes through you: strafes you off it. Far throws can be dodged, point-blank ones are too fast.",
    })
    ChainBox:AddSlider("DodgeButcher_Margin", {
        Text = "Body margin", Default = 1.5, Min = 0, Max = 5, Rounding = 1, Suffix = " studs",
    })

    -- [v37] фонарик: наводка луча на голову киллера
    local FlashBox = SurvMain:AddRightGroupbox("Flashlight")
    FlashBox:AddCheckbox("FlashAim_Enabled", {
        Text = "Flashlight Aim", Default = false, BindIcon = "kb_target",
        Tooltip = "While you shine the flashlight (item key held): turns your view so the beam goes into the killer's face (nearest to the crosshair).",
    })
    FlashBox:AddSlider("FlashAim_FOV", { Text = "Aim FOV", Default = 60, Min = 5, Max = 180, Rounding = 0, Suffix = " deg" })
    FlashBox:AddSlider("FlashAim_Smooth", { Text = "Aim smoothness", Default = 50, Min = 0, Max = 90, Rounding = 0, Suffix = "%" })
    FlashBox:AddCheckbox("FlashAim_WallCheck", { -- [v39]
        Text = "Obstacle check", Default = true,
        Tooltip = "Only aims at a killer whose head you can actually see (no wall between).",
    })

    -- [v80] Twist of Fate: наводка камеры (выстрел летит по взгляду камеры - TwistoffateClient: Fire(..., LookVector))
    ESPUI.TOFBox = SurvMain:AddRightGroupbox("Twist of Fate")
    ESPUI.TOFBox:AddCheckbox("TOFAim_Enabled", { Text = "Twist of Fate aim", Default = false, BindIcon = "kb_target",
        Tooltip = "While you aim Twist of Fate: turns your view to the killer nearest to the crosshair. The shot goes where the camera looks." })
    ESPUI.TOFBox:AddSlider("TOFAim_FOV", { Text = "Aim FOV", Default = 60, Min = 5, Max = 180, Rounding = 0, Suffix = " deg" })
    ESPUI.TOFBox:AddSlider("TOFAim_Smooth", { Text = "Aim smoothness", Default = 50, Min = 0, Max = 90, Rounding = 0, Suffix = "%" })
    ESPUI.TOFBox:AddDropdown("TOFAim_Part", { Text = "Aim at", Values = { "Head", "Torso" }, Default = "Torso" })
    ESPUI.TOFBox:AddSlider("TOFAim_MaxDist", { Text = "Max distance", Default = 150, Min = 10, Max = 500, Rounding = 0, Suffix = " studs" }) -- [v81]
    ESPUI.TOFBox:AddCheckbox("TOFAim_WallCheck", { Text = "Obstacle check", Default = true,
        Tooltip = "Only aims at a killer you can actually see (no wall between)." })
end

------------------------------------------------------------
-- Player chams
------------------------------------------------------------
-- ESP (NL): Behind Walls = Disabled / Flat (заливка сквозь стены) / Outline (только контур сквозь стены),
-- Glow = контур. Highlight у Roblox один на модель, поэтому так:
--   Flat     -> AlwaysOnTop, заливка видна;  Outline -> AlwaysOnTop, заливки нет, контур есть
--   Disabled -> Occluded: сквозь стены ничего, Glow остаётся только на видимой части
local function ChamsStyle(p)
    local mode = Options[p .. "WallMode"].Value
    local glow = Toggles[p .. "Outline"].Value
    return {
        FillColor = Options[p .. "FillColor"].Value,
        FillTransparency = mode == "Flat" and Options[p .. "FillTransparency"].Value or 1,
        OutlineColor = glow and Options[p .. "OutlineColor"].Value or Options[p .. "FillColor"].Value,
        OutlineTransparency = (glow or mode == "Outline") and Options[p .. "OutlineTransparency"].Value or 1,
        DepthMode = mode ~= "Disabled" and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded,
    }
end

local function MakePlayerChams(p, getList, priority)
    local group = HighlightGroup.new(function() return ChamsStyle(p) end, priority)
    group.Prefix = p -- [v66] для эффектов ESP (радуга / пульс / цвет по HP)
    return DefineFeature({
        Id = p,
        Toggle = p .. "Enabled",
        Watch = {
            p .. "WallMode", p .. "FillColor", p .. "FillTransparency",
            p .. "Outline", p .. "OutlineColor", p .. "OutlineTransparency",
        },
        Update = function(self)
            local adornees = {}
            -- ESP: Behind Walls = Disabled и Glow выкл. -> Highlight не нужен (не тратим бюджет)
            if Options[p .. "WallMode"].Value ~= "Disabled" or Toggles[p .. "Outline"].Value then
                for _, e in ipairs(getList()) do adornees[#adornees + 1] = e.Model end
            end
            group:Sync(adornees)
        end,
        Disable = function(self)
            group:Clear()
        end,
    })
end

MakePlayerChams("KillerChams_", function() return Targets.Killers end, 0)
MakePlayerChams("SurvChams_", function() return Targets.Survivors end, 1)
MakePlayerChams("BotChams_", function() return Targets.Bots end, 1)
MakePlayerChams("SpecChams_", function() return Targets.Spectators end, 2)

-- ESP (NL): Visible - материал видимой модели (Flat / Neon / Hologram / Glass).
-- Меняется только у тебя на экране; всё исходное (материал, цвет, текстуры, одежда, лицо) запоминается
-- и возвращается, когда выключаешь, меняешь режим или игрок уходит из списка (умер, сменил команду).
do
    local MATERIALS = {
        Flat = Enum.Material.SmoothPlastic,
        Neon = Enum.Material.Neon,
        Hologram = Enum.Material.ForceField,
        Glass = Enum.Material.Glass,
    }
    local Owner = {} -- [model] = prefix, чтобы две группы не красили одну модель

    local function MakeVisibleMaterial(p, getList)
        local recs = {} -- [model] = { Props = { [inst] = { [prop] = исходное } }, Want = {...}, Conns = {}, Stash }

        local function restore(model)
            local rec = recs[model]
            if not rec then return end
            for _, c in ipairs(rec.Conns) do pcall(function() c:Disconnect() end) end
            for inst, props in pairs(rec.Props) do
                for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
            end
            rec.Stash:RestoreAll()
            recs[model] = nil
            if Owner[model] == p then Owner[model] = nil end
        end

        -- ставит значение и держит его (если игра перезапишет - вернём своё, а "исходное" обновим)
        local function hold(rec, inst, prop, value)
            local props = rec.Props[inst]
            if not props then props = {} rec.Props[inst] = props end
            local want = rec.Want[inst]
            if not want then want = {} rec.Want[inst] = want end
            if props[prop] == nil then
                local ok, cur = pcall(function() return inst[prop] end)
                if not ok then return end
                props[prop] = cur
                table.insert(rec.Conns, inst:GetPropertyChangedSignal(prop):Connect(function()
                    local w = want[prop]
                    if w == nil then return end
                    local now = inst[prop]
                    if now ~= w then
                        props[prop] = now
                        pcall(function() inst[prop] = w end)
                    end
                end))
            end
            want[prop] = value
            if inst[prop] ~= value then pcall(function() inst[prop] = value end) end
        end

        local function apply(model, mat, color)
            local rec = recs[model]
            if not rec then
                rec = { Props = {}, Want = {}, Conns = {}, Stash = Stash.new() }
                recs[model] = rec
            end
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then
                    if d.Name ~= "HumanoidRootPart" then
                        hold(rec, d, "Material", mat)
                        hold(rec, d, "Color", color)
                        if d:IsA("MeshPart") then hold(rec, d, "TextureID", "") end
                    end
                elseif d:IsA("SpecialMesh") then
                    hold(rec, d, "TextureId", "")
                elseif d:IsA("Decal") then
                    hold(rec, d, "Transparency", 1) -- лицо и наклейки
                elseif d:IsA("SurfaceAppearance") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
                    rec.Stash:Hide(d) -- одежда/PBR-текстуры перекрывают цвет
                end
            end
        end

        -- [v66] эффекты ESP: перекраска материала каждый кадр (через hold - игра не перебьёт)
        HighlightGroup.FX.Recolor[p] = function(getColor)
            for model, rec in pairs(recs) do
                local c = getColor(model)
                if c then
                    for inst, want in pairs(rec.Want) do
                        if want.Color ~= nil and want.Color ~= c then hold(rec, inst, "Color", c) end
                    end
                end
            end
        end
        HighlightGroup.FX.Models = HighlightGroup.FX.Models or {}
        HighlightGroup.FX.Models[p] = recs

        return DefineFeature({
            Id = p .. "VisMat",
            Toggle = p .. "Enabled",
            Watch = { p .. "VisMat", p .. "VisColor" },
            Update = function(self)
                local mat = MATERIALS[Options[p .. "VisMat"].Value]
                local color = Options[p .. "VisColor"].Value
                local seen = {}
                if mat then
                    for _, e in ipairs(getList()) do
                        local o = Owner[e.Model]
                        if o == nil or o == p then
                            Owner[e.Model] = p
                            seen[e.Model] = true
                            apply(e.Model, mat, color)
                        end
                    end
                end
                for model in pairs(recs) do
                    if not seen[model] then restore(model) end
                end
            end,
            Disable = function(self)
                for model in pairs(recs) do restore(model) end
            end,
        })
    end

    MakeVisibleMaterial("KillerChams_", function() return Targets.Killers end)
    MakeVisibleMaterial("SurvChams_", function() return Targets.Survivors end)
    MakeVisibleMaterial("BotChams_", function() return Targets.Bots end)
    MakeVisibleMaterial("SpecChams_", function() return Targets.Spectators end)
end

------------------------------------------------------------
-- Survivor State
------------------------------------------------------------
DefineFeature({
    Id = "SurvState_",
    Gate = { "SurvState_Knocked", "SurvState_Hooked", "SurvState_Hitted",
        "SurvState_HookInfo", "SurvState_HealInfo", "SurvState_WiggleInfo" }, -- [v41]
    Watch = {
        "SurvState_KnockedColor", "SurvState_HookedColor", "SurvState_HittedColor",
        "SurvState_TextSize",
    },
    Track = {},

    Update = function(self)
        local now = os.clock()
        local size = Options.SurvState_TextSize.Value
        local seen = {}

        for _, e in ipairs(Targets.AllSurvivors) do
            seen[e.Model] = true

            local t = self.Track[e.Model]
            if not t then
                t = { hooked = false, lastDec = 0 }
                self.Track[e.Model] = t
            end
            local hc = tonumber(ReadAttr(e.Model, e.Player, "HookCount"))
            local hp = tonumber(ReadAttr(e.Model, e.Player, "HookedProgress"))
            if hc and t.hc and hc > t.hc then
                t.hooked = true
                t.lastDec = now
            end
            if t.hooked then
                if hp and t.hp and hp < t.hp then t.lastDec = now end
                if now - t.lastDec > CONFIG.HookGrace then t.hooked = false end
            end
            t.hc, t.hp = hc, hp

            local active = {
                Knocked = ReadAttr(e.Model, e.Player, "Knocked") == true,
                Hooked = t.hooked,
                Hitted = math.abs(e.Humanoid.Health - CONFIG.HitHealth) < 0.5,
            }

            local lines = {}
            for _, s in ipairs(STATES) do
                if active[s.Key] and Toggles["SurvState_" .. s.Key].Value then
                    lines[#lines + 1] = RGBTag(Options["SurvState_" .. s.Key .. "Color"].Value, s.Label)
                end
            end

            -- [v41] прогресс-строки по атрибутам сервера
            if Toggles.SurvState_HookInfo.Value and ReadAttr(e.Model, e.Player, "IsHooked") == true then
                local stage = tonumber(ReadAttr(e.Model, e.Player, "HookCount")) or 1
                local hp = tonumber(ReadAttr(e.Model, e.Player, "HookedProgress")) or 0
                lines[#lines + 1] = RGBTag(Options.SurvState_HookedColor.Value,
                    string.format("Hook S%d %d%%", math.max(stage, 1), math.floor(math.clamp(hp, 0, 1) * 100 + 0.5)))
            end
            if Toggles.SurvState_HealInfo.Value then
                local ci = e.Model:FindFirstChild("CheckInterractable")
                local healing = ReadAttr(e.Model, e.Player, "IsBeingHealed") == true or (ci and ci:GetAttribute("isHealing") == true)
                local recover = e.Humanoid and e.Humanoid.MaxHealth > 0 and e.Humanoid.Health / e.Humanoid.MaxHealth < 0.5
                    and ReadAttr(e.Model, e.Player, "IsHooked") ~= true
                local prog = tonumber(ReadAttr(e.Model, e.Player, "HealProgress"))
                if (healing or recover) and prog then
                    lines[#lines + 1] = RGBTag(Color3.fromRGB(120, 230, 120),
                        string.format("%s %d%%", healing and "Heal" or "Recover", math.floor(math.clamp(prog, 0, 100) + 0.5)))
                end
            end
            if Toggles.SurvState_WiggleInfo.Value and ReadAttr(e.Model, e.Player, "IsCarried") == true then
                local rem = tonumber(ReadAttr(e.Model, e.Player, "RemainingCarryTime")) or 16
                lines[#lines + 1] = RGBTag(Color3.fromRGB(255, 200, 70),
                    string.format("Wiggle %d%%", math.floor(math.clamp((16 - rem) / 16, 0, 1) * 100 + 0.5)))
            end

            if #lines > 0 then
                Tags.Set(e.Model, "State", table.concat(lines, "\n"), size, Color3.new(1, 1, 1))
            else
                Tags.Remove(e.Model, "State")
            end
        end

        Tags.PruneSlot("State", seen)
        for model in pairs(self.Track) do
            if not seen[model] then self.Track[model] = nil end
        end
    end,

    Disable = function(self)
        Tags.RemoveSlotAll("State")
        table.clear(self.Track)
    end,
})

-- [v42] индикатор SLOW в левом списке (атрибут speedboost < 1 у своего персонажа)
DefineFeature({
    Id = "SlowIndicator_",
    Toggle = "SlowIndicator_Enabled",
    Update = function(self)
        local KL = Library.KeybindList
        if not KL then return end
        local char = LocalPlayer.Character
        local boost = char and tonumber(char:GetAttribute("speedboost"))
        local slowed = boost ~= nil and boost < 0.98
        if slowed then
            KL:SetStatus("Slow", { Text = "SLOW", Icon = "kb_warn", -- [v72] треугольник, как у gamesense
                Color = Options.SlowIndicator_Color.Value })
            self.Shown = true
        elseif self.Shown then
            KL:SetStatus("Slow", nil)
            self.Shown = false
        end
    end,
    Disable = function(self)
        if Library.KeybindList then Library.KeybindList:SetStatus("Slow", nil) end
        self.Shown = false
    end,
})

-- [v41] "STUNNED" над оглушённым киллером (атрибут IsStunned)
DefineFeature({
    Id = "KillerStun_",
    Toggle = "KillerState_Stun",
    Watch = { "KillerState_StunColor", "KillerState_TextSize" },
    Update = function(self)
        local seen = {}
        for _, e in ipairs(Targets.Killers) do
            if e.Model and ReadAttr(e.Model, e.Player, "IsStunned") == true then
                seen[e.Model] = true
                Tags.Set(e.Model, "Stun", RGBTag(Options.KillerState_StunColor.Value, "STUNNED"),
                    Options.KillerState_TextSize.Value, Color3.new(1, 1, 1))
            end
        end
        Tags.PruneSlot("Stun", seen)
    end,
    Disable = function(self) Tags.RemoveSlotAll("Stun") end,
})

-- [v47] Cure: колба. Animations.lua: зажал ПКМ -> flaskcharge, затем flaskidle (целится); отпустил ->
-- flaskthrow, через 0.2с бросок; когда flaskthrow закончилась - makeMoveCooldown 15с.
do
    local FLASK_AIM = { ["121108316060822"] = true, ["79390410596403"] = true } -- flaskcharge, flaskidle
    local FLASK_THROW, FLASK_CD = "99210996402874", 15
    DefineFeature({
        Id = "CureFlask_",
        Toggle = "KillerState_Flask",
        Watch = { "KillerState_FlaskColor", "KillerState_TextSize" },
        Throws = setmetatable({}, { __mode = "k" }), -- [track flaskthrow] = модель
        Ready = setmetatable({}, { __mode = "k" }),  -- [модель] = os.clock() конца кулдауна
        Update = function(self)
            local now, seen = os.clock(), {}
            for _, e in ipairs(Targets.Killers) do
                local animator = e.Model and e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
                local aiming = false
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
                        if id and FLASK_AIM[id] then aiming = true
                        elseif id == FLASK_THROW then self.Throws[track] = e.Model end
                    end
                end
                local text
                if aiming then
                    text = "FLASK"
                else
                    local left = (self.Ready[e.Model] or 0) - now
                    if left > 0 then text = string.format("FLASK %ds", math.ceil(left)) end
                end
                if text then
                    seen[e.Model] = true
                    Tags.Set(e.Model, "Flask", RGBTag(Options.KillerState_FlaskColor.Value, text),
                        Options.KillerState_TextSize.Value, Color3.new(1, 1, 1))
                end
            end
            -- бросок закончился -> кулдаун пошёл
            for track, model in pairs(self.Throws) do
                if not track.IsPlaying then
                    self.Ready[model] = now + FLASK_CD
                    self.Throws[track] = nil
                end
            end
            Tags.PruneSlot("Flask", seen)
        end,
        Disable = function(self)
            Tags.RemoveSlotAll("Flask")
            table.clear(self.Throws)
            table.clear(self.Ready)
        end,
    })
end

-- [v41] кольцо радиуса террора киллера (атрибут TerrorRadius), неоновые детали в папке камеры
do
    local function VizPart(folder)
        return New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
            CastShadow = false, Material = Enum.Material.Neon, Transparency = 1, Size = Vector3.new(0.2, 0.2, 1), Parent = folder })
    end
    DefineFeature({
        Id = "TerrorRing_",
        Toggle = "TerrorRing_Enabled",
        Watch = { "TerrorRing_Color" },
        Enable = function(self)
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.Maid:Give(folder)
            self.Parts = {}
            for i = 1, 60 do self.Parts[i] = VizPart(folder) end
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Draw") end))
        end,
        Draw = function(self)
            local color = Options.TerrorRing_Color.Value
            -- ближайший киллер с заданным радиусом террора
            local killer, radius
            for _, e in ipairs(Targets.Killers) do
                local r = tonumber(ReadAttr(e.Model, e.Player, "TerrorRadius"))
                if e.Root and r and r > 0 then killer, radius = e, r break end
            end
            if not killer then
                for _, p in ipairs(self.Parts) do p.Transparency = 1 end
                return
            end
            local c = killer.Root.Position
            local n = #self.Parts
            local step = 2 * math.pi / n
            local len = 2 * math.pi * radius / n * 0.6
            for i, part in ipairs(self.Parts) do
                local a = (i - 1) * step
                local pos = c + Vector3.new(math.cos(a) * radius, -2.5, math.sin(a) * radius)
                local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
                part.Size = Vector3.new(0.25, 0.25, len)
                part.CFrame = CFrame.lookAt(pos, pos + tangent)
                part.Color = color
                part.Transparency = 0.1
            end
        end,
        Disable = function(self) self.Parts = nil end,
    })
end

------------------------------------------------------------
-- ESP
------------------------------------------------------------
local function IsOneshot(model, player)
    for _, key in ipairs({ "oneshot", "Oneshot", "OneShot" }) do
        if ReadAttr(model, player, key) == true then return true end
    end
    return CollectionService:HasTag(model, "oneshot")
end

local function MakeESP(p, getList, isKiller)
    local gate = { p .. "Name", p .. "Studs", p .. "Tracer", p .. "Team", p .. "Perks" } -- [v81] + Team, [v86] + Perks
    if isKiller then table.insert(gate, p .. "KillerType") end
    -- [v81] подпись команды
    local TEAM_LABEL = ({ SurvESP_ = "SURVIVOR", KillerESP_ = "KILLER", SpecESP_ = "SPECTATOR", BotESP_ = "BOT" })[p] or ""

    return DefineFeature({
        Id = p,
        Gate = gate,
        Watch = { p .. "TracerColor", p .. "TextColor", p .. "TextSize", p .. "TracerThickness" },
        Lines = {},
        Roots = {},

        Update = function(self)
            local showName = Toggles[p .. "Name"].Value
            local showStuds = Toggles[p .. "Studs"].Value
            local showType = isKiller and Toggles[p .. "KillerType"].Value
            local showTracer = Toggles[p .. "Tracer"].Value
            local textColor = Options[p .. "TextColor"].Value
            local textSize = Options[p .. "TextSize"].Value

            if showTracer and not self.Gui then
                self.Gui = self.Maid:Give(NewOverlayGui())
            end

            local myRoot = GetRoot(LocalPlayer.Character)
            local seen, oneshots = {}, {}
            local showTeam = Toggles[p .. "Team"].Value -- [v81]
            local maxD = Options[p .. "MaxDist"].Value -- [v81] 0 = без ограничения
            local camNow = workspace.CurrentCamera
            local fromPos = (myRoot and myRoot.Position) or (camNow and camNow.CFrame.Position)

            for _, e in ipairs(getList()) do
              if not (maxD > 0 and fromPos and e.Root and (e.Root.Position - fromPos).Magnitude > maxD) then -- [v81]
                seen[e.Model] = true
                self.Roots[e.Model] = e.Root

                local lines = {}
                local first = showName and Escape(Library.StreamerMode and (isKiller and "Killer" or "Player") or e.Name) or "" -- [v71] Streamer mode
                if showType then
                    local kt = KillerTypeText(e.Model, e.Player)
                    if kt ~= "" then
                        first = first .. (first ~= "" and " · " or "") .. Escape(kt)
                    end
                end
                if first ~= "" then lines[#lines + 1] = first end
                if showStuds and myRoot then
                    local d = (myRoot.Position - e.Root.Position).Magnitude
                    lines[#lines + 1] = FormatDist(d)
                end
                if showTeam and TEAM_LABEL ~= "" then lines[#lines + 1] = TEAM_LABEL end -- [v81]
                -- [v86] перки из MatchResults (имена через « · », предмет в скобках)
                if Toggles[p .. "Perks"].Value and e.Player and ESPUI.PerkData then
                    local pd = ESPUI.PerkData(e.Player)
                    if pd and #pd.Names > 0 then
                        lines[#lines + 1] = Escape((pd.Source == "last" and "last: " or "seen: ") -- [v88] откуда данные
                        .. table.concat(pd.Names, " · ") .. (pd.Item and pd.Item ~= "" and (" [" .. pd.Item .. "]") or ""))
                    end
                end

                if #lines > 0 then
                    Tags.Set(e.Model, p, table.concat(lines, "\n"), textSize, textColor)
                else
                    Tags.Remove(e.Model, p)
                end

                -- Oneshot: отдельная надпись ПОД персонажем
                if isKiller and IsOneshot(e.Model, e.Player) then
                    oneshots[e.Model] = true
                    Tags.Set(e.Model, "Oneshot", "Oneshot", textSize, textColor, 0.45)
                end

                if showTracer and not self.Lines[e.Model] then
                    self.Lines[e.Model] = New("Frame", {
                        AnchorPoint = Vector2.new(0.5, 0.5),
                        BorderSizePixel = 0,
                        Visible = false,
                        Parent = self.Gui,
                    })
                end
              end
            end

            Tags.PruneSlot(p, seen)
            if isKiller then Tags.PruneSlot("Oneshot", oneshots) end
            for model, line in pairs(self.Lines) do
                if not showTracer or not seen[model] then
                    line:Destroy()
                    self.Lines[model] = nil
                end
            end
            for model in pairs(self.Roots) do
                if not seen[model] then self.Roots[model] = nil end
            end
        end,

        Render = function(self)
            if next(self.Lines) == nil then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            local vp = cam.ViewportSize
            -- [v81] Origin: Bottom / Center / Top / Mouse
            local origin = Options[p .. "TracerOrigin"] and Options[p .. "TracerOrigin"].Value or "Bottom"
            local from = Vector2.new(vp.X / 2, vp.Y)
            if origin == "Center" then from = vp / 2
            elseif origin == "Top" then from = Vector2.new(vp.X / 2, 0)
            elseif origin == "Mouse" then from = UserInputService:GetMouseLocation() end
            local color = Options[p .. "TracerColor"].Value
            local thickness = Options[p .. "TracerThickness"].Value

            for model, line in pairs(self.Lines) do
                local root = self.Roots[model]
                if root and root.Parent then
                    local pos = root.Position
                    local sp = cam:WorldToViewportPoint(pos)
                    local to
                    if sp.Z > 0 then
                        to = Vector2.new(sp.X, sp.Y)
                    else
                        local rel = cam.CFrame:PointToObjectSpace(pos)
                        local dir = Vector2.new(rel.X, -rel.Y)
                        dir = dir.Magnitude > 1e-3 and dir.Unit or Vector2.new(0, 1)
                        to = from + dir * vp.Magnitude
                    end
                    SetLineFrame(line, from, to, color, thickness)
                else
                    line.Visible = false
                end
            end
        end,

        Disable = function(self)
            Tags.RemoveSlotAll(p)
            if isKiller then Tags.RemoveSlotAll("Oneshot") end
            table.clear(self.Lines)
            table.clear(self.Roots)
            self.Gui = nil
        end,
    })
end

MakeESP("SurvESP_", function() return Targets.Survivors end, false)
MakeESP("KillerESP_", function() return Targets.Killers end, true)
MakeESP("SpecESP_", function() return Targets.Spectators end, false)
MakeESP("BotESP_", function() return Targets.Bots end, false)

------------------------------------------------------------
-- ESP (NL): Bounding Box, Health Bar, Skeleton, Item, Offscreen Arrow + превью в меню
------------------------------------------------------------
-- Рисуется каждый кадр рамками на экране (как трейсеры). Имя/дистанция - прежние надписи над головой.
do
    -- R6 (в игре) и R15: пары деталей для скелета
    local R15_BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
    }
    local MAX_BONES = #R15_BONES

    -- точки скелета в мире: список пар {a, b}
    local function SkeletonPoints(model)
        local out = {}
        local torso = model:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then
            local tc = torso.CFrame
            local hy = torso.Size.Y / 2
            local neck, pelvis = (tc * CFrame.new(0, hy, 0)).Position, (tc * CFrame.new(0, -hy, 0)).Position
            local head = model:FindFirstChild("Head")
            if head and head:IsA("BasePart") then table.insert(out, { head.Position, neck }) end
            table.insert(out, { neck, pelvis })
            for _, n in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
                local part = model:FindFirstChild(n)
                if part and part:IsA("BasePart") then
                    local py = part.Size.Y / 2
                    local top = (part.CFrame * CFrame.new(0, py * 0.8, 0)).Position
                    local bottom = (part.CFrame * CFrame.new(0, -py * 0.9, 0)).Position
                    local from = string.find(n, "Arm") and neck or pelvis
                    table.insert(out, { from, top })
                    table.insert(out, { top, bottom })
                end
            end
            return out
        end
        for _, b in ipairs(R15_BONES) do
            local a, c = model:FindFirstChild(b[1]), model:FindFirstChild(b[2])
            if a and c and a:IsA("BasePart") and c:IsA("BasePart") then table.insert(out, { a.Position, c.Position }) end
        end
        return out
    end

    -- предмет в руках: Tool внутри персонажа (фонарик, кинжал...)
    local function HeldItem(model)
        local tool = model:FindFirstChildOfClass("Tool")
        return tool and tool.Name or nil
    end

    local function HealthColor(f)
        return Color3.fromHSV(math.clamp(f, 0, 1) * 0.33, 0.85, 1)
    end

    -- набор рамок для одной цели; parent - экранный слой (ScreenGui или рамка превью)
    local function NewDrawing(parent)
        local d = { Bones = {} }
        local function stroke(frame, th, color, tr)
            return New("UIStroke", { Thickness = th, Color = color, Transparency = tr or 0,
                LineJoinMode = Enum.LineJoinMode.Miter, Parent = frame })
        end
        d.BoxOuter = New("Frame", { BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = parent })
        stroke(d.BoxOuter, 3, Color3.new(0, 0, 0), 0.35)
        d.Box = New("Frame", { BackgroundTransparency = 1, Visible = false, ZIndex = 3, Parent = parent })
        d.BoxStroke = stroke(d.Box, 1, Color3.new(1, 1, 1))
        d.HpBack = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
            BorderSizePixel = 0, Visible = false, ZIndex = 2, Parent = parent })
        d.HpFill = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 1, 1, -1),
            BorderSizePixel = 0, ZIndex = 3, Parent = d.HpBack })
        d.Item = New("TextLabel", { BackgroundTransparency = 1, Text = "", Font = CONFIG.TagFont, TextStrokeTransparency = 0.35,
            AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(200, 16), Visible = false, ZIndex = 3, Parent = parent })
        Library:ApplyESPFont(d.Item) -- [v62]
        -- [v80] Head dot: кружок на голове
        d.HeadDot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Visible = false, ZIndex = 4, Parent = parent })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d.HeadDot })
        New("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.3, Parent = d.HeadDot })
        d.Parent = parent
        return d
    end

    local function DestroyDrawing(d)
        for _, k in ipairs({ "BoxOuter", "Box", "HpBack", "Item", "Arrow", "HeadDot", "HpText" }) do -- [v80] + HeadDot, [v81] + HpText
            if d[k] then pcall(function() d[k]:Destroy() end) end
        end
        for _, f in ipairs(d.Corners or {}) do pcall(function() f:Destroy() end) end -- [v81]
        for _, b in ipairs(d.Bones) do pcall(function() b:Destroy() end) end
        for _, b in ipairs(d.Glow or {}) do pcall(function() b:Destroy() end) end -- [v66]
    end

    local function HideDrawing(d)
        d.BoxOuter.Visible, d.Box.Visible, d.HpBack.Visible, d.Item.Visible = false, false, false, false
        for _, b in ipairs(d.Bones) do b.Visible = false end
        if d.Glow then for _, b in ipairs(d.Glow) do b.Visible = false end end -- [v66]
        if d.Arrow then d.Arrow.Visible = false end
        if d.HeadDot then d.HeadDot.Visible = false end -- [v80]
        if d.HpText then d.HpText.Visible = false end -- [v81]
        if d.Corners then for _, f in ipairs(d.Corners) do f.Visible = false end end -- [v81]
    end

    -- рамка персонажа на экране: верх головы и низ ног по корню; ширина = 0.55 высоты
    local function BoxRect(project, root)
        local up = root.CFrame.UpVector
        local hy = root.Size.Y / 2
        local top, okT = project(root.Position + up * (hy * 2.6))
        local bottom, okB = project(root.Position - up * (hy * 3.1))
        local mid, okM = project(root.Position)
        if not (okT and okB and okM) then return nil end
        local h = math.abs(bottom.Y - top.Y)
        if h < 4 then return nil end
        local w = h * 0.55
        return Vector2.new(mid.X - w / 2, math.min(top.Y, bottom.Y)), Vector2.new(w, h)
    end

    -- s = { Box, Health, Skeleton, Item, BoxColor, SkelColor, TextColor, TextSize }
    local function DrawTarget(d, project, model, root, hum, s)
        local pos, size = BoxRect(project, root)
        if not pos then HideDrawing(d) return false end
        local x, y, w, h = math.floor(pos.X + 0.5), math.floor(pos.Y + 0.5), math.floor(size.X + 0.5), math.floor(size.Y + 0.5)

        -- [v81] Box style Corners: 8 отрезков по углам (с чёрной обводкой), полная рамка скрыта
        local corners = s.Box and s.Corners
        if corners then
            if not d.Corners then
                d.Corners = {}
                for i = 1, 8 do
                    local f = New("Frame", { BorderSizePixel = 0, ZIndex = 3, Parent = d.Parent })
                    New("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.35, Parent = f })
                    d.Corners[i] = f
                end
            end
            local cw, ch = math.max(math.floor(w / 4), 2), math.max(math.floor(h / 4), 2)
            local rects = {
                { x, y, cw, 1 }, { x, y, 1, ch }, { x + w - cw, y, cw, 1 }, { x + w - 1, y, 1, ch },
                { x, y + h - 1, cw, 1 }, { x, y + h - ch, 1, ch }, { x + w - cw, y + h - 1, cw, 1 }, { x + w - 1, y + h - ch, 1, ch },
            }
            for i, r in ipairs(rects) do
                local f = d.Corners[i]
                f.Position, f.Size = UDim2.fromOffset(r[1], r[2]), UDim2.fromOffset(r[3], r[4])
                SetIf(f, "BackgroundColor3", s.BoxColor)
                f.Visible = true
            end
        elseif d.Corners then
            for _, f in ipairs(d.Corners) do f.Visible = false end
        end
        d.Box.Visible, d.BoxOuter.Visible = s.Box and not corners, s.Box and not corners
        if s.Box and not corners then
            d.Box.Position, d.Box.Size = UDim2.fromOffset(x, y), UDim2.fromOffset(w, h)
            d.BoxOuter.Position, d.BoxOuter.Size = d.Box.Position, d.Box.Size
            SetIf(d.BoxStroke, "Color", s.BoxColor)
        end

        -- [v81] Health text: число HP слева от рамки (или от полосы HP)
        if s.HealthText and hum then
            if not d.HpText then
                d.HpText = New("TextLabel", { AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 1, Font = CONFIG.TagFont,
                    TextStrokeTransparency = 0.35, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromOffset(40, 12),
                    ZIndex = 3, Parent = d.Parent })
                Library:ApplyESPFont(d.HpText)
            end
            local f = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
            d.HpText.Text = tostring(math.floor(hum.Health + 0.5))
            d.HpText.Position = UDim2.fromOffset(x - (s.Health and 8 or 3), y - 2)
            SetIf(d.HpText, "TextSize", math.max(math.floor((s.TextSize - 2) * (Library.ESPTextK or 1) + 0.5), 6))
            SetIf(d.HpText, "TextColor3", HealthColor(f))
            d.HpText.Visible = true
        elseif d.HpText then
            d.HpText.Visible = false
        end

        d.HpBack.Visible = s.Health and hum ~= nil
        if s.Health and hum then
            local f = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
            d.HpBack.Position, d.HpBack.Size = UDim2.fromOffset(x - 6, y - 1), UDim2.fromOffset(4, h + 2)
            d.HpFill.Size = UDim2.new(0, 2, f, -2 * f)
            SetIf(d.HpFill, "BackgroundColor3", HealthColor(f))
        end

        local used = 0
        if s.Skeleton then
            for _, pair in ipairs(SkeletonPoints(model)) do
                local a, okA = project(pair[1])
                local b, okB = project(pair[2])
                if okA and okB then
                    used += 1
                    local line = d.Bones[used]
                    if not line then
                        line = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3, Parent = d.Parent })
                        d.Bones[used] = line
                    end
                    -- [v66] эффекты ESP: цвет скелета (радуга / HP) и неоновое свечение под линией
                    local fxc = s.Prefix and HighlightGroup.FX.SkelColor and HighlightGroup.FX.SkelColor(s.Prefix, model, s.SkelColor)
                    local col = fxc or s.SkelColor
                    SetLineFrame(line, a, b, col, 1)
                    local glow = d.Glow and d.Glow[used]
                    if s.Prefix and HighlightGroup.FX.SkelGlow and HighlightGroup.FX.SkelGlow(s.Prefix) then
                        d.Glow = d.Glow or {}
                        glow = d.Glow[used]
                        if not glow then
                            glow = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 2, Parent = d.Parent })
                            d.Glow[used] = glow
                        end
                        SetLineFrame(glow, a, b, col, 4)
                        SetIf(glow, "BackgroundTransparency", 0.65)
                        SetIf(glow, "Visible", true)
                    elseif glow then
                        SetIf(glow, "Visible", false)
                    end
                end
                if used >= MAX_BONES then break end
            end
        end
        for i = used + 1, #d.Bones do d.Bones[i].Visible = false end
        if d.Glow then for i = used + 1, #d.Glow do d.Glow[i].Visible = false end end -- [v66]

        -- [v80] Head dot: размер от высоты рамки (3..10 px)
        if d.HeadDot then
            local head = s.HeadDot and model:FindFirstChild("Head")
            local hp, okH
            if head and head:IsA("BasePart") then hp, okH = project(head.Position) end
            d.HeadDot.Visible = okH == true
            if okH then
                local r = math.clamp(math.floor(h * 0.07 + 0.5), 3, 10)
                d.HeadDot.Position = UDim2.fromOffset(math.floor(hp.X + 0.5), math.floor(hp.Y + 0.5))
                SetIf(d.HeadDot, "Size", UDim2.fromOffset(r, r))
                SetIf(d.HeadDot, "BackgroundColor3", s.HeadDotColor or s.BoxColor)
            end
        end

        local item = s.Item and HeldItem(model) or nil
        d.Item.Visible = item ~= nil
        if item then
            d.Item.Text = item
            d.Item.Position = UDim2.fromOffset(x + w / 2, y + h + 2)
            SetIf(d.Item, "TextColor3", s.TextColor)
            SetIf(d.Item, "TextSize", math.max(math.floor((s.TextSize - 2) * (Library.ESPTextK or 1) + 0.5), 6)) -- [v64]
            SetIf(d.Item, "Size", UDim2.fromOffset(200, s.TextSize))
        end
        return true
    end

    -- стрелка за экраном: картинка-треугольник (или ▲, если нет getcustomasset), остриём к цели
    local function NewArrow(parent)
        local icon = Library:GetIcon("esp_arrow")
        return icon and New("ImageLabel", { BackgroundTransparency = 1, Image = icon,
            AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 4, Parent = parent })
            or New("TextLabel", { BackgroundTransparency = 1, Text = "▲", Font = Enum.Font.GothamBold,
            TextScaled = true, AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 4, Parent = parent })
    end
    local function PlaceArrow(a, at, dir, size, color)
        a.Position = UDim2.fromOffset(at.X, at.Y)
        a.Size = UDim2.fromOffset(size, size)
        a.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90
        if a:IsA("ImageLabel") then SetIf(a, "ImageColor3", color) else SetIf(a, "TextColor3", color) end
        a.Visible = true
    end

    local function Settings(p)
        return {
            Box = Toggles[p .. "Box"].Value, Health = Toggles[p .. "Health"].Value,
            Skeleton = Toggles[p .. "Skeleton"].Value, Item = Toggles[p .. "Item"].Value,
            BoxColor = Options[p .. "BoxColor"].Value, SkelColor = Options[p .. "SkeletonColor"].Value,
            Prefix = p, -- [v66] эффекты ESP: цвет / неон скелета
            HeadDot = Toggles[p .. "HeadDot"] and Toggles[p .. "HeadDot"].Value, -- [v80]
            Corners = Options[p .. "BoxStyle"] and Options[p .. "BoxStyle"].Value == "Corners", -- [v81]
            HealthText = Toggles[p .. "HealthText"] and Toggles[p .. "HealthText"].Value, -- [v81]
            HeadDotColor = Options[p .. "HeadDotColor"] and Options[p .. "HeadDotColor"].Value,
            TextColor = Options[p .. "TextColor"].Value, TextSize = Options[p .. "TextSize"].Value,
        }
    end

    local function MakeESPDraw(p, getList)
        return DefineFeature({
            Id = p .. "Draw",
            Gate = { p .. "Box", p .. "Health", p .. "Skeleton", p .. "Item", p .. "Arrow", p .. "HeadDot", p .. "HealthText" }, -- [v80] + HeadDot, [v81] + HealthText
            Draw = {},
            Entries = {},

            Enable = function(self)
                self.Gui = self.Maid:Give(NewOverlayGui())
            end,

            Update = function(self)
                local seen = {}
                for _, e in ipairs(getList()) do
                    seen[e.Model] = true
                    self.Entries[e.Model] = e
                    if not self.Draw[e.Model] and self.Gui then self.Draw[e.Model] = NewDrawing(self.Gui) end
                end
                for model, d in pairs(self.Draw) do
                    if not seen[model] then
                        DestroyDrawing(d)
                        self.Draw[model] = nil
                        self.Entries[model] = nil
                    end
                end
            end,

            Render = function(self)
                local cam = workspace.CurrentCamera
                if not cam or next(self.Draw) == nil then return end
                local vp = cam.ViewportSize
                local center = vp / 2
                local s = Settings(p)
                local arrow = Toggles[p .. "Arrow"].Value
                local arrowColor = Options[p .. "ArrowColor"].Value
                local arrowSize = Options[p .. "ArrowSize"].Value
                local radius = math.min(vp.X, vp.Y) * Options[p .. "ArrowRadius"].Value / 100
                local function project(pos)
                    local sp, on = cam:WorldToViewportPoint(pos)
                    return Vector2.new(sp.X, sp.Y), sp.Z > 0 and on ~= nil
                end
                local maxD = Options[p .. "MaxDist"] and Options[p .. "MaxDist"].Value or 0 -- [v81] Max distance
                local myRoot = maxD > 0 and GetRoot(LocalPlayer.Character)
                local fromPos = myRoot and myRoot.Position or cam.CFrame.Position
                for model, d in pairs(self.Draw) do
                    local e = self.Entries[model]
                    local root = e and e.Root
                    if not root or not root.Parent or (maxD > 0 and (root.Position - fromPos).Magnitude > maxD) then
                        HideDrawing(d)
                    else
                        local sp = cam:WorldToViewportPoint(root.Position)
                        local onScreen = sp.Z > 0 and sp.X >= 0 and sp.Y >= 0 and sp.X <= vp.X and sp.Y <= vp.Y
                        if onScreen then
                            DrawTarget(d, project, model, root, e.Humanoid, s)
                        else
                            HideDrawing(d)
                        end
                        -- стрелка к игроку за экраном (по кругу вокруг центра, остриём к нему)
                        if arrow and not onScreen then
                            d.Arrow = d.Arrow or NewArrow(self.Gui)
                            local rel = cam.CFrame:PointToObjectSpace(root.Position)
                            local dir = Vector2.new(rel.X, -rel.Y)
                            if sp.Z > 0 then dir = Vector2.new(sp.X, sp.Y) - center end
                            dir = dir.Magnitude > 1e-3 and dir.Unit or Vector2.new(0, 1)
                            PlaceArrow(d.Arrow, center + dir * radius, dir, arrowSize, arrowColor)
                        elseif d.Arrow then
                            d.Arrow.Visible = false
                        end
                    end
                end
            end,

            Disable = function(self)
                table.clear(self.Draw)
                table.clear(self.Entries)
                self.Gui = nil
            end,
        })
    end

    MakeESPDraw("SurvESP_", function() return Targets.Survivors end)
    MakeESPDraw("KillerESP_", function() return Targets.Killers end)
    MakeESPDraw("SpecESP_", function() return Targets.Spectators end)
    MakeESPDraw("BotESP_", function() return Targets.Bots end)

    --------------------------------------------------------
    -- Превью (как у NL): модель с материалом "Visible" и ESP по включённым кнопкам
    --------------------------------------------------------
    local PREVIEW_MATS = {
        Flat = Enum.Material.SmoothPlastic, Neon = Enum.Material.Neon,
        Hologram = Enum.Material.ForceField, Glass = Enum.Material.Glass,
    }
    local CLEAN = { "LuaSourceContainer", "Sound", "BillboardGui", "SurfaceGui", "Highlight", "ProximityPrompt",
        "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "Light", "ForceField", "Constraint", "JointInstance" }
    local CLEAN_KEEP = { Motor6D = true, Weld = true } -- суставы оставляем: детали якорные, позы не сломаются

    local function IsShown(gui)
        local g = gui
        while g do
            if g:IsA("GuiObject") and not g.Visible then return false end
            if g:IsA("ScreenGui") then return g.Enabled end
            g = g.Parent
        end
        return false
    end

    -- копия персонажа без скриптов/звуков; запоминаем исходный вид деталей, чтобы менять материал на лету
    local function ClonePreview(model)
        local ok, clone = pcall(function()
            local was = model.Archivable
            model.Archivable = true
            local c = model:Clone()
            model.Archivable = was
            return c
        end)
        if not ok or not clone then return nil end
        -- [v43] сначала якорим и ставим во флат-позу (пока все суставы на месте), потом чистим
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = true end
        end
        pcall(ESPUI.FlatPose, clone)
        for _, d in ipairs(clone:GetDescendants()) do
            if not CLEAN_KEEP[d.ClassName] then
                for _, cls in ipairs(CLEAN) do
                    if d:IsA(cls) then pcall(function() d:Destroy() end) break end
                end
            end
        end
        local orig = {}
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = true
                pcall(function() d.LocalTransparencyModifier = 0 end)
                if d.Name ~= "HumanoidRootPart" then
                    orig[d] = { Material = d.Material, Color = d.Color, TextureID = d:IsA("MeshPart") and d.TextureID or nil }
                end
            elseif d:IsA("SpecialMesh") then
                orig[d] = { TextureId = d.TextureId }
            elseif d:IsA("Decal") then
                orig[d] = { Transparency = d.Transparency }
            elseif d:IsA("SurfaceAppearance") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
                orig[d] = { Parent = d.Parent }
            elseif d:IsA("Humanoid") then
                pcall(function() d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
            end
        end
        return clone, orig
    end

    local function PaintPreview(orig, mat, color)
        for inst, o in pairs(orig) do
            pcall(function()
                if inst:IsA("BasePart") then
                    inst.Material = mat or o.Material
                    inst.Color = mat and color or o.Color
                    if o.TextureID then inst.TextureID = mat and "" or o.TextureID end
                elseif inst:IsA("SpecialMesh") then
                    inst.TextureId = mat and "" or o.TextureId
                elseif inst:IsA("Decal") then
                    inst.Transparency = mat and 1 or o.Transparency
                else
                    inst.Parent = (not mat) and o.Parent or nil
                end
            end)
        end
    end

    local PAGES = {
        { P = "SurvESP_", C = "SurvChams_", List = function() return Targets.Survivors end, Killer = false },
        { P = "KillerESP_", C = "KillerChams_", List = function() return Targets.Killers end, Killer = true },
        { P = "SpecESP_", C = "SpecChams_", List = function() return Targets.Spectators end, Killer = false },
        { P = "BotESP_", C = "BotChams_", List = function() return Targets.Bots end, Killer = false },
    }

    for _, pg in ipairs(PAGES) do
        local I = ESPUI[pg.P]
        if I and I.Overlay then
            local p, c = pg.P, pg.C
            local st = { Source = nil, Model = nil, Orig = nil, NextCheck = 0, Name = "Player" }
            local layer = I.Overlay
            local draw = NewDrawing(layer)
            local nameLbl = New("TextLabel", { BackgroundTransparency = 1, Text = "", Font = CONFIG.TagFont, TextStrokeTransparency = 0.35,
                AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(200, 32), TextYAlignment = Enum.TextYAlignment.Bottom,
                Visible = false, ZIndex = 3, Parent = layer })
            Library:ApplyESPFont(nameLbl) -- [v62]
            local tracer = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Visible = false, ZIndex = 2, Parent = layer })
            local arrowImg = NewArrow(layer) -- пример Offscreen Arrow: справа от модели, остриём наружу

            local function repaint()
                if st.Orig then PaintPreview(st.Orig, Toggles[c .. "Enabled"].Value and PREVIEW_MATS[Options[c .. "VisMat"].Value] or nil, Options[c .. "VisColor"].Value) end
            end
            -- источник: первый игрок этой группы (как у NL - модель врага), иначе ты сам
            local function rebuild()
                local list = pg.List()
                local mine = LocalPlayer.Character
                -- текущую модель не меняем, пока она подходит (иначе превью прыгало бы между игроками)
                if st.Source and st.Source.Parent and st.Model and st.Model.Parent then
                    local still = (#list == 0 and st.Source == mine)
                    for _, x in ipairs(list) do if x.Model == st.Source then still = true break end end
                    if still then return end
                end
                local e = list[1]
                local src = e and e.Model or mine
                if not src then return end
                local m, orig = ClonePreview(src)
                if not m then return end
                st.Source, st.Model, st.Orig = src, m, orig
                st.Name = e and e.Name or LocalPlayer.Name
                I:SetModel(m)
                repaint()
            end
            for _, idx in ipairs({ c .. "Enabled", c .. "VisMat", c .. "VisColor" }) do
                local el = Toggles[idx] or Options[idx]
                if el then el:OnChanged(repaint) end
            end

            local function frame()
                local now = os.clock()
                if now >= st.NextCheck then
                    st.NextCheck = now + 1
                    pcall(rebuild)
                end
                local m = st.Model
                local root = m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
                if not root then HideDrawing(draw) nameLbl.Visible = false tracer.Visible = false arrowImg.Visible = false return end

                -- проекция через камеру превью (ViewportFrame: вертикальный FOV, свой размер)
                local cam = I.Camera
                local size = layer.AbsoluteSize
                local f = (size.Y / 2) / math.tan(math.rad(cam.FieldOfView) / 2)
                local camCF = cam.CFrame
                local function project(pos)
                    local rel = camCF:PointToObjectSpace(pos)
                    if rel.Z >= -0.05 then return Vector2.zero, false end
                    return Vector2.new(size.X / 2 + rel.X / -rel.Z * f, size.Y / 2 - rel.Y / -rel.Z * f), true
                end
                local s = Settings(p)
                local hum = m:FindFirstChildOfClass("Humanoid")
                local shown = DrawTarget(draw, project, m, root, hum, s)

                local lines = {}
                if Toggles[p .. "Name"].Value then
                    local first = Escape(Library.StreamerMode and "Player" or st.Name) -- [v71] Streamer mode
                    if pg.Killer and Toggles[p .. "KillerType"].Value and st.Source then
                        local ok, kt = pcall(KillerTypeText, st.Source, Players:GetPlayerFromCharacter(st.Source))
                        if ok and kt and kt ~= "" then first = first .. " · " .. Escape(kt) end
                    end
                    table.insert(lines, first)
                end
                if Toggles[p .. "Studs"].Value then table.insert(lines, "12 studs") end
                local pos, bsize = BoxRect(project, root)
                nameLbl.Visible = shown and #lines > 0 and pos ~= nil
                if nameLbl.Visible then
                    nameLbl.RichText = true
                    nameLbl.Text = table.concat(lines, "\n")
                    nameLbl.Position = UDim2.fromOffset(pos.X + bsize.X / 2, pos.Y - 3)
                    SetIf(nameLbl, "TextColor3", s.TextColor)
                    SetIf(nameLbl, "TextSize", math.floor(s.TextSize * (Library.ESPTextK or 1) + 0.5)) -- [v64]
                end
                if Toggles[p .. "Arrow"].Value then
                    local asz = Options[p .. "ArrowSize"].Value
                    PlaceArrow(arrowImg, Vector2.new(size.X - asz / 2 - 10, size.Y / 2), Vector2.new(1, 0), asz, Options[p .. "ArrowColor"].Value)
                else
                    arrowImg.Visible = false
                end
                tracer.Visible = shown and Toggles[p .. "Tracer"].Value and pos ~= nil
                if tracer.Visible then
                    SetLineFrame(tracer, Vector2.new(size.X / 2, size.Y), Vector2.new(pos.X + bsize.X / 2, pos.Y + bsize.Y),
                        Options[p .. "TracerColor"].Value, Options[p .. "TracerThickness"].Value)
                end
            end
            local renderName = RandomName()
            RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value - 1, function()
                if Library.Unloaded or not IsShown(I.Box) then return end -- слой скрыт, пока нет модели; смотрим на рамку
                local ok, err = pcall(frame)
                if not ok and not WarnedErrors[renderName] then
                    WarnedErrors[renderName] = true
                    warn("[" .. CONFIG.ScriptName .. "] ESP preview failed: " .. tostring(err))
                end
            end)
            ESPUI[p .. "Frame"] = frame -- для тестов
            GlobalMaid:Give(function() pcall(function() RunService:UnbindFromRenderStep(renderName) end) end)
        end
    end
end

------------------------------------------------------------
-- Floor Cone (плоский 2D сектор на полу у ног киллера, как террор-радиус)
------------------------------------------------------------
-- [CHANGED v11] Вместо деталей-клиньев - один плоский SurfaceGui на полу:
--   * AlwaysOnTop + LightInfluence 0 -> виден сквозь стены, цвет ровный, без теней и швов между клиньями;
--   * сектор (заливка полосами + контур линиями) строится ОДИН раз при смене range/angle/цветов,
--     каждый кадр двигается только невидимая деталь-носитель -> движение плавное, нагрузки почти нет.
-- Носитель повёрнут так, что его Front-грань смотрит вверх, а "верх" GUI = взгляд киллера
-- (у Front-грани верх GUI всегда = UpVector детали).
-- Высота пола = от ног киллера (HRP - ноги), без луча вниз -> не прыгает на ящики/пропы.
local CONE_PPS = 8          -- пикселей GUI на stud
local CONE_ROW = 2          -- px: высота полосы заливки
local CONE_LINE = 3         -- px: толщина контура
local CONE_LIFT = 0.05      -- над полом

local function FeetY(root, model)
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    if hum and hum.RigType == Enum.HumanoidRigType.R15 then
        return root.Position.Y - root.Size.Y / 2 - hum.HipHeight
    end
    return root.Position.Y - 3
end

-- линия внутри GUI (как SetLineFrame, но без экранных координат)
local function ConeGuiLine(parent, a, b, color)
    local f = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = parent })
    SetLineFrame(f, a, b, color, CONE_LINE)
    return f
end

DefineFeature({
    Id = "Cone_",
    Toggle = "Cone_Enabled",
    Watch = { "Cone_Range", "Cone_Angle", "Cone_Transparency", "Cone_Fill", "Cone_Outline" },
    Pool = {},

    Enable = function(self)
        local folder = New("Folder", { Name = RandomName() })
        folder.Parent = workspace.CurrentCamera or workspace
        self.Maid:Give(folder)
        self.Folder = folder
        self.Key = nil
    end,

    -- носитель + SurfaceGui для i-го киллера
    Get = function(self, i)
        local rec = self.Pool[i]
        if rec and rec.Part.Parent and rec.Gui.Parent then return rec end
        local part = New("Part", {
            Name = RandomName(),
            Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
            Transparency = 1,
            Size = Vector3.new(1, 1, 0.05),
            Parent = self.Folder,
        })
        local gui = New("SurfaceGui", {
            Name = RandomName(),
            Face = Enum.NormalId.Front,
            Adornee = part,
            AlwaysOnTop = true,
            LightInfluence = 0,
            SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
            PixelsPerStud = CONE_PPS,
            ClipsDescendants = false,
            ResetOnSpawn = false,
            Parent = Containers.Root,
        })
        self.Maid:Give(gui)
        rec = { Part = part, Gui = gui, Key = nil }
        self.Pool[i] = rec
        return rec
    end,

    -- перерисовать сектор в GUI (только когда изменились параметры)
    Build = function(self, rec, range, angle, fillOn, fillT, lineOn, fillColor, lineColor)
        rec.Gui:ClearAllChildren()
        local a = math.rad(angle)
        local W, H = 2 * range * math.sin(a) * CONE_PPS + CONE_LINE * 2, range * CONE_PPS + CONE_LINE * 2
        rec.Part.Size = Vector3.new(W / CONE_PPS, H / CONE_PPS, 0.05)
        local cx, cy = W / 2, H - CONE_LINE -- вершина: низ по центру
        local tanA = math.tan(a)

        if fillOn then
            for y = 0, H - 1, CONE_ROW do
                local dy = (cy - (y + CONE_ROW / 2)) / CONE_PPS -- studs от вершины по взгляду
                if dy > 0 and dy <= range then
                    local hw = math.min(dy * tanA, math.sqrt(math.max(range * range - dy * dy, 0)))
                    if hw > 0 then
                        New("Frame", {
                            Position = UDim2.fromOffset(cx - hw * CONE_PPS, y),
                            Size = UDim2.fromOffset(hw * 2 * CONE_PPS, CONE_ROW),
                            BackgroundColor3 = fillColor,
                            BackgroundTransparency = fillT,
                            BorderSizePixel = 0,
                            Parent = rec.Gui,
                        })
                    end
                end
            end
        end

        if lineOn then
            local apex = Vector2.new(cx, cy)
            local segs = math.clamp(math.ceil(angle / 4), 6, 24)
            local prev, first
            for i = 0, segs do
                local p = -a + 2 * a * i / segs
                local pt = apex + Vector2.new(math.sin(p), -math.cos(p)) * range * CONE_PPS
                if prev then ConeGuiLine(rec.Gui, prev, pt, lineColor) else first = pt end
                prev = pt
            end
            ConeGuiLine(rec.Gui, apex, first, lineColor)
            ConeGuiLine(rec.Gui, apex, prev, lineColor)
        end
    end,

    Render = function(self)
        if not self.Folder or not self.Folder.Parent then return end
        local range = Options.Cone_Range.Value
        local angle = Options.Cone_Angle.Value
        local fillOn, lineOn = Toggles.Cone_Fill.Value, Toggles.Cone_Outline.Value
        local fillT = Options.Cone_Transparency.Value
        local fillColor = Options.KillerChams_FillColor.Value
        local lineColor = Options.KillerChams_OutlineColor.Value
        local key = table.concat({ range, angle, tostring(fillOn), fillT, tostring(lineOn),
            fillColor:ToHex(), lineColor:ToHex() }, "|")

        local list = {}
        for _, e in ipairs(Targets.Killers) do list[#list + 1] = { Root = e.Root, Model = e.Model } end
        local team = LocalPlayer.Team and LocalPlayer.Team.Name
        if team == CONFIG.Teams.Killer and LocalPlayer.Character then
            local r = GetRoot(LocalPlayer.Character)
            if r then list[#list + 1] = { Root = r, Model = LocalPlayer.Character } end
        end

        local used = 0
        for _, k in ipairs(list) do
            local root = k.Root
            if root and root.Parent then
                local lv = root.CFrame.LookVector
                local look = Vector3.new(lv.X, 0, lv.Z)
                if look.Magnitude > 1e-3 then
                    look = look.Unit
                    used += 1
                    local rec = self:Get(used)
                    if rec.Key ~= key then
                        rec.Key = key
                        self:Build(rec, range, angle, fillOn, fillT, lineOn, fillColor, lineColor)
                    end
                    local apex = Vector3.new(root.Position.X, FeetY(root, k.Model) + CONE_LIFT, root.Position.Z)
                    -- Front-грань вверх: +Z детали = вниз, UpVector = взгляд, X = Y x Z
                    local down = Vector3.new(0, -1, 0)
                    local h = rec.Part.Size.Y
                    local center = apex + look * (h / 2 - CONE_LINE / CONE_PPS)
                    rec.Part.CFrame = CFrame.fromMatrix(center, look:Cross(down), look, down)
                    SetIf(rec.Gui, "Enabled", true)
                end
            end
        end
        for i = used + 1, #self.Pool do
            local rec = self.Pool[i]
            if rec and rec.Gui.Parent then SetIf(rec.Gui, "Enabled", false) end
        end
    end,

    Disable = function(self)
        table.clear(self.Pool)
        self.Folder = nil
    end,
})

------------------------------------------------------------
-- Killer HUD
------------------------------------------------------------
local KillerHUD = { Defs = {} }

function KillerHUD.Register(name, def)
    KillerHUD.Defs[HudKey(name)] = def
end

local function HudLabel(parent, text, order)
    local scheme = Library.Scheme
    -- [v91] как ватермарка gamesense: Noto Sans SemiBold 13, белый, с тенью
    return New("TextLabel", {
        LayoutOrder = order or 0,
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        FontFace = (Library.BindFonts and Library.BindFonts[Enum.FontWeight.SemiBold]) or scheme.Font,
        TextSize = 13,
        TextColor3 = scheme.FontColor,
        TextStrokeTransparency = 0.6,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = text or "",
        Parent = parent,
    })
end

local function HudDivider(parent, order)
    -- [v91] у gamesense пункты разделены только отступом - разделитель невидимый (видимость по-прежнему
    -- переключают определения киллеров, отступ остаётся)
    return New("Frame", {
        LayoutOrder = order or 0,
        Size = UDim2.fromOffset(0, 16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = parent,
    })
end

-- [NEW v5] абилка в кулдауне -> её элемент HUD полупрозрачный
local HUD_CD_TRANSPARENCY = 0.5
local function HudSetCD(label, onCooldown)
    SetIf(label, "TextTransparency", onCooldown and HUD_CD_TRANSPARENCY or 0)
end

KillerHUD.Register("default", {})

-- ===== VEIL =====
local VEIL_CHARGE_IDS = {
    ["77303734522729"]  = "charge",
    ["87436543050891"]  = "charge",
    ["79809716042968"]  = "power",
    ["122765810542358"] = "power",
}

local function VeilChargeKind(e)
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    local kind
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        local k = id and VEIL_CHARGE_IDS[id]
        if k == "power" then return "power" end
        if k == "charge" then kind = "charge" end
    end
    return kind
end

KillerHUD.Register("Veil", {
    Build = function(ctx)
        ctx.Div1   = HudDivider(ctx.Body, 2)
        ctx.Spears = HudLabel(ctx.Body, "Spears: 0", 3)
        ctx.Div2   = HudDivider(ctx.Body, 4)
        ctx.Ability = HudLabel(ctx.Body, "Ability ready", 5)
        ctx.Div3   = HudDivider(ctx.Body, 6)
        ctx.Charge = HudLabel(ctx.Body, "", 7)
        ctx.ChargeStart = nil

        -- таймеры (в игре нет атрибута кулдауна, считаем по Spears / special)
        ctx.LastSpears, ctx.SpearEnd = nil, nil
        ctx.LastReady, ctx.AbilityEnd = nil, nil
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        local V = CONFIG.Veil

        -- копья: каждые SpearRecharge сек +1 до MaxSpears
        local spears = tonumber(ReadAttr(e.Model, e.Player, "Spears")) or 0
        if spears >= V.MaxSpears then
            ctx.SpearEnd = nil
        elseif ctx.LastSpears == nil or ctx.SpearEnd == nil or spears > ctx.LastSpears then
            -- первый кадр / бросок из полного запаса / копьё восстановилось -> отсчёт следующего
            ctx.SpearEnd = now + V.SpearRecharge
        end
        ctx.LastSpears = spears

        local spearText = "Spears: " .. tostring(spears)
        if ctx.SpearEnd then
            spearText = string.format("%s · next %.1fs", spearText, math.max(ctx.SpearEnd - now, 0))
        end
        SetIf(ctx.Spears, "Text", spearText)
        SetIf(ctx.Spears, "TextColor3", scheme.FontColor)

        -- способность (Through the Veil): special == true -> готова; true -> false = бросок, кулдаун AbilityCooldown
        local ready = ReadAttr(e.Model, e.Player, "special") == true
        local abilityText, abilityColor
        if ready then
            ctx.AbilityEnd = nil
            abilityText, abilityColor = "Ability ready", Color3.fromRGB(90, 225, 130)
        else
            if ctx.LastReady == true then ctx.AbilityEnd = now + V.AbilityCooldown end
            abilityColor = Color3.fromRGB(255, 200, 60)
            if ctx.AbilityEnd then
                abilityText = string.format("Ability: %.1fs", math.max(ctx.AbilityEnd - now, 0))
            else
                abilityText = "Ability: cooldown" -- бросок не видели, время неизвестно
            end
        end
        ctx.LastReady = ready
        SetIf(ctx.Ability, "Text", abilityText)
        SetIf(ctx.Ability, "TextColor3", abilityColor)
        HudSetCD(ctx.Ability, not ready) -- [NEW v5]
        SetIf(ctx.Ability, "Visible", true)
        SetIf(ctx.Div2, "Visible", true)

        local kind = VeilChargeKind(e)
        local text, color = "", scheme.FontColor
        if kind then
            if not ctx.ChargeStart then ctx.ChargeStart = now end
            local t = now - ctx.ChargeStart
            if kind == "power" then
                text, color = "Ability charge", Color3.fromRGB(255, 90, 90)
            elseif t >= 2 then
                text, color = "Charge 2s+", Color3.fromRGB(255, 200, 60)
            else
                text = string.format("Charging %.1fs", t)
            end
        else
            ctx.ChargeStart = nil
        end
        SetIf(ctx.Charge, "Text", text)
        SetIf(ctx.Charge, "TextColor3", color)
        SetIf(ctx.Charge, "Visible", text ~= "")
        SetIf(ctx.Div3, "Visible", text ~= "")

        for _, d in ipairs({ ctx.Div1, ctx.Div2, ctx.Div3 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== MASKED =====
-- "Mask Up": маска меняется каждые SwapCooldown сек. Атрибута таймера нет -
-- отсчёт стартует, когда мы видим смену атрибута Mask. До первой смены время неизвестно.
-- [NEW v6] Сила маски из Masked Powers (save.rbxmx JOSE_091E9 -> LocalScript Powers):
-- только с маской Richard; Activatepower + анимация 92125118598365, действует 3.8с (замах) + 64с,
-- затем Deactivatepower + та же анимация, кулдаун 30с. Атрибута у силы нет (MaskExpired ставится
-- локально у киллера и к нам не доходит) -> ловим анимацию, как у Hidden.
-- Alex: атрибут ChainsawRushActive (Animations у Masked).
local MASKED_POWER_ANIM = "92125118598365"
local MASKED_POWER_TIME = 3.8 + 64
local MASKED_POWER_CD   = 30

local function MaskedPowerAnim(e)
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        if id == MASKED_POWER_ANIM then return true end
    end
    return false
end

KillerHUD.Register("Masked", {
    Build = function(ctx)
        ctx.Div1 = HudDivider(ctx.Body, 2)
        ctx.Swap = HudLabel(ctx.Body, "Mask swap: ?", 3)
        ctx.LastMask, ctx.SwapEnd = nil, nil
        -- [NEW v6]
        ctx.Div2  = HudDivider(ctx.Body, 4)
        ctx.Power = HudLabel(ctx.Body, "", 5)
        ctx.PowerAnim, ctx.PowerEnd, ctx.PowerCD = false, nil, nil
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        local cd = CONFIG.Masked.SwapCooldown

        local mask = ReadAttr(e.Model, e.Player, "Mask")
        mask = type(mask) == "string" and mask or ""

        if ctx.LastMask ~= nil and mask ~= ctx.LastMask then
            ctx.SwapEnd = now + cd
        end
        ctx.LastMask = mask

        -- таймер дошёл до нуля, а маска не поменялась (выпала такая же) -> следующий цикл
        while ctx.SwapEnd and now >= ctx.SwapEnd do
            ctx.SwapEnd += cd
        end

        local text, color
        if ctx.SwapEnd then
            local left = math.max(ctx.SwapEnd - now, 0)
            text = string.format("Mask swap: %.1fs", left)
            color = left <= 5 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 200, 60)
        else
            text, color = "Mask swap: ?", scheme.FontColor
        end
        SetIf(ctx.Swap, "Text", text)
        SetIf(ctx.Swap, "TextColor3", color)
        SetIf(ctx.Div1, "BackgroundColor3", scheme.OutlineColor)

        -- [NEW v6] сила маски: анимация в начале = активация, повтор в конце = снятие -> кулдаун
        local anim = MaskedPowerAnim(e)
        if anim and not ctx.PowerAnim then
            if ctx.PowerEnd and now < ctx.PowerEnd and now > ctx.PowerEnd - 10 then
                ctx.PowerEnd, ctx.PowerCD = nil, now + MASKED_POWER_CD -- снятие силы
            elseif not ctx.PowerEnd then
                ctx.PowerEnd, ctx.PowerCD = now + MASKED_POWER_TIME, nil -- активация
            end
        end
        ctx.PowerAnim = anim
        if ctx.PowerEnd and now >= ctx.PowerEnd then -- снятия не увидели - считаем по таймеру
            ctx.PowerEnd, ctx.PowerCD = nil, now + MASKED_POWER_CD
        end

        local pText, pColor, onCd = "", scheme.FontColor, false
        if mask == "Alex" and ReadAttr(e.Model, e.Player, "ChainsawRushActive") == true then
            pText, pColor = "Chainsaw rush!", Color3.fromRGB(255, 80, 80)
        elseif ctx.PowerEnd then
            pText, pColor = string.format("Richard power %.1fs", ctx.PowerEnd - now), Color3.fromRGB(255, 80, 80)
        elseif ctx.PowerCD and now < ctx.PowerCD then
            pText, pColor, onCd = string.format("Power: %.1fs", ctx.PowerCD - now), Color3.fromRGB(255, 200, 60), true
        elseif mask == "Richard" then
            pText, pColor = "Power ready", Color3.fromRGB(90, 225, 130)
        end
        SetIf(ctx.Power, "Text", pText)
        SetIf(ctx.Power, "TextColor3", pColor)
        HudSetCD(ctx.Power, onCd)
        SetIf(ctx.Power, "Visible", pText ~= "")
        SetIf(ctx.Div2, "Visible", pText ~= "")
        SetIf(ctx.Div2, "BackgroundColor3", scheme.OutlineColor)
    end,
})

-- ===== HIDDEN =====
-- Атрибутов кулдауна у обычных умений нет (Powers считает их локально у киллера),
-- поэтому ловим момент начала анимации умения: она реплицируется на наш клиент.
local HIDDEN_ANIMS = {
    ["109928123357793"] = "leap", -- Leap (ability2)
    ["98163597193511"]  = "mark", -- Mark / M2 (ability1)
}

local function HiddenActive(e)
    local out = {}
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return out end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        local k = id and HIDDEN_ANIMS[id]
        if k then out[k] = true end
    end
    return out
end

-- Пассивка Hidden: стоит на месте -> невидим. Прозрачность ставит сервер, поэтому смотрим
-- на атрибуты (если игра их ставит) и на Transparency частей тела.
local INVIS_ATTRS = { "Invisible", "invisible", "IsInvisible", "Invis", "Cloaked" }
local BODY_PARTS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function IsInvisible(model, player)
    for _, k in ipairs(INVIS_ATTRS) do
        local v = ReadAttr(model, player, k)
        if v ~= nil then return Truthy(v) end
    end
    local checked = 0
    for _, name in ipairs(BODY_PARTS) do
        local p = model:FindFirstChild(name)
        if p and p:IsA("BasePart") then
            checked += 1
            if math.max(p.Transparency, p.LocalTransparencyModifier) < 0.9 then return false end
        end
    end
    return checked > 0
end

local function HiddenAbilityText(name, endTime, now)
    local left = endTime and (endTime - now) or 0
    if left > 0 then
        return string.format("%s: %.1fs", name, left), Color3.fromRGB(255, 200, 60)
    end
    return name .. " ready", Color3.fromRGB(90, 225, 130)
end

-- [NEW v5] Общий трекер кулдаунов Hidden на модель киллера: им пользуются и HUD, и трейсеры
-- (раньше состояние жило только в ctx HUD, трейсеры о кулдауне не знали).
-- Логика та же: старт анимации = умение использовано; HiddenPalletLeapCooldownUntil - серверное время.
-- MarkStart: когда началась анимация Mark - нужно, чтобы заморозить трейсер на время рывка.
local HiddenCD = setmetatable({}, { __mode = "k" })

local function HiddenCooldowns(e)
    local now = os.clock()
    local H = CONFIG.Hidden
    local st = HiddenCD[e.Model]
    if not st then
        st = { LeapEnd = nil, MarkEnd = nil, LastLeap = false, LastMark = false, MarkStart = nil }
        HiddenCD[e.Model] = st
    end
    local active = HiddenActive(e)
    if active.leap and not st.LastLeap then st.LeapEnd = now + H.LeapCooldown end
    if active.mark and not st.LastMark then
        st.MarkEnd = now + H.MarkCooldown
        st.MarkStart = now
        -- Powers.playM2Animation: рывок (HiddenMarkDash.start) через task.delay(u854 and 0.85 or 0.65)
        -- + task.wait(0.15); u854 = идёт Leap
        st.MarkDashAt = now + (active.leap and 0.85 or 0.65) + 0.15
    end
    if not active.mark then st.MarkStart, st.MarkFreeze = nil, nil end
    st.LastLeap, st.LastMark = active.leap == true, active.mark == true
    st.Leaping = st.LastLeap

    local untilTime = tonumber(ReadAttr(e.Model, e.Player, "HiddenPalletLeapCooldownUntil"))
    if untilTime then
        local remaining = untilTime - workspace:GetServerTimeNow()
        if remaining > 0 and (not st.LeapEnd or now + remaining > st.LeapEnd) then
            st.LeapEnd = now + remaining
        end
    end
    st.LeapLeft = st.LeapEnd and math.max(st.LeapEnd - now, 0) or 0
    st.MarkLeft = st.MarkEnd and math.max(st.MarkEnd - now, 0) or 0
    return st
end

KillerHUD.Register("Hidden", {
    Build = function(ctx)
        ctx.Div1 = HudDivider(ctx.Body, 2)
        ctx.Leap = HudLabel(ctx.Body, "Leap ready", 3)
        ctx.Div2 = HudDivider(ctx.Body, 4)
        ctx.Mark = HudLabel(ctx.Body, "Mark ready", 5)
        ctx.Div3 = HudDivider(ctx.Body, 6)
        ctx.Invis = HudLabel(ctx.Body, "Invisible", 7)
        ctx.Div3.Visible, ctx.Invis.Visible = false, false
        ctx.LeapEnd, ctx.MarkEnd = nil, nil
        ctx.LastLeap, ctx.LastMark = false, false
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        -- [CHANGED v5] кулдауны из общего трекера (та же логика, что была здесь)
        local st = HiddenCooldowns(e)

        local leapText, leapColor = HiddenAbilityText("Leap", st.LeapEnd, now)
        SetIf(ctx.Leap, "Text", leapText)
        SetIf(ctx.Leap, "TextColor3", leapColor)
        HudSetCD(ctx.Leap, st.LeapLeft > 0) -- [NEW v5]

        local markText, markColor = HiddenAbilityText("Mark", st.MarkEnd, now)
        SetIf(ctx.Mark, "Text", markText)
        SetIf(ctx.Mark, "TextColor3", markColor)
        HudSetCD(ctx.Mark, st.MarkLeft > 0) -- [NEW v5]

        local invis = IsInvisible(e.Model, e.Player)
        SetIf(ctx.Invis, "TextColor3", Color3.fromRGB(190, 160, 255))
        SetIf(ctx.Invis, "Visible", invis)
        SetIf(ctx.Div3, "Visible", invis)

        for _, d in ipairs({ ctx.Div1, ctx.Div2, ctx.Div3 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== STALKER =====
local STALKER_ROMAN = { "I", "II", "III" }
local STALKER_STAGE_COLORS = {
    Color3.fromRGB(235, 235, 235),
    Color3.fromRGB(255, 170, 60),
    Color3.fromRGB(255, 80, 80),
}

-- [NEW] Данные стака из PowersMyers.
-- Сервер шлёт Remotes.Killers.Stalker.UpdateStalking(progress 0..100, stage, ready, stalking).
-- В PowersMyers: u225 = progress, u226 = stage, u227 = (ready == true), stalking == false -> цель потеряна.
-- ВАЖНО: в PowersMyers это слушает клиент киллера. Доходит ли событие до клиента сурва - из файла не видно.
local StalkerNet = { Bound = false, Progress = nil, Ready = false, Active = false, At = -math.huge }

function StalkerNet.Bind()
    if StalkerNet.Bound then return end
    local rs = game:GetService("ReplicatedStorage")
    local r = rs:FindFirstChild("Remotes")
    r = r and r:FindFirstChild("Killers")
    r = r and r:FindFirstChild("Stalker")
    local remote = r and r:FindFirstChild("UpdateStalking")
    if not (remote and remote:IsA("RemoteEvent")) then return end
    StalkerNet.Bound = true
    GlobalMaid:Give(remote.OnClientEvent:Connect(function(progress, _stage, ready, stalking)
        local p = tonumber(progress)
        local prev = StalkerNet.Progress
        StalkerNet.Progress = p
        StalkerNet.Ready = ready == true
        StalkerNet.Active = stalking == true or (stalking == nil and p ~= nil and prev ~= nil and p > prev)
        StalkerNet.At = os.clock()
    end))
end

-- [NEW] Порт getTargetPlayer / hasLineOfSight2 из PowersMyers, но с позиции чужого киллера:
-- камеры киллера у нас нет, поэтому направление взгляда = Head.LookVector (как у Hidden-предикта).
local function StalkerLOS(killerModel, kRoot, tModel, tRoot)
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { killerModel, tModel }
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local from, to = kRoot.Position, tRoot.Position
    local dir = to - from
    for _ = 1, 10 do
        local hit = workspace:Raycast(from, dir, rp)
        if not hit then return true end
        local inst = hit.Instance
        if inst:IsDescendantOf(tModel) then return true end
        if inst.Transparency >= 0.99 and not inst:HasTag("TrueInvis") then
            from = hit.Position + dir.Unit * 0.01
            dir = to - from
        else
            return false
        end
    end
    return false
end

local function StalkerGuessTarget(e)
    local kRoot = e.Root
    if not kRoot or not kRoot.Parent then return nil end
    local head = e.Model:FindFirstChild("Head")
    local look = (head and head:IsA("BasePart")) and head.CFrame.LookVector or kRoot.CFrame.LookVector
    local best, bestName, bestDist = nil, nil, 100

    local function consider(model, name)
        local tRoot = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChild("Humanoid")
        if not (tRoot and hum) then return end
        if model:GetAttribute("IsHooked") or model:GetAttribute("IsDead") then return end
        if hum.Health <= 0 or hum.Health / hum.MaxHealth <= 0.5 then return end
        local dist = (tRoot.Position - kRoot.Position).Magnitude
        if dist > 100 or dist >= bestDist then return end
        if look:Dot((tRoot.Position - kRoot.Position).Unit) <= 0.8 then return end
        if not StalkerLOS(e.Model, kRoot, model, tRoot) then return end
        best, bestName, bestDist = model, name, dist
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= e.Player and plr.Character then consider(plr.Character, plr.Name) end
    end
    for _, m in ipairs(CollectionService:GetTagged("SurvivorBot")) do
        if m:IsDescendantOf(workspace) then consider(m, m.Name) end
    end
    return best, bestName
end

KillerHUD.Register("Stalker", {
    Build = function(ctx)
        ctx.Div1  = HudDivider(ctx.Body, 2)
        ctx.Stage = HudLabel(ctx.Body, "Stage I", 3)
        ctx.Div2  = HudDivider(ctx.Body, 4)
        ctx.Timer = HudLabel(ctx.Body, "", 5)
        ctx.Div3  = HudDivider(ctx.Body, 6)
        ctx.Grab  = HudLabel(ctx.Body, "", 7)
        -- [NEW] стак: % до Stage II, факт стака, цель
        ctx.Div4   = HudDivider(ctx.Body, 8)
        ctx.Stalk  = HudLabel(ctx.Body, "Stalk: ?", 9)
        ctx.Div5   = HudDivider(ctx.Body, 10)
        ctx.Target = HudLabel(ctx.Body, "", 11)
        ctx.RemEnd, ctx.LastRem = nil, nil
        StalkerNet.Bind()
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()

        local stage = math.clamp(math.floor(tonumber(ReadAttr(e.Model, e.Player, "Stage")) or 1), 1, 3)
        SetIf(ctx.Stage, "Text", "Stage " .. STALKER_ROMAN[stage])
        SetIf(ctx.Stage, "TextColor3", STALKER_STAGE_COLORS[stage])

        local rem = tonumber(ReadAttr(e.Model, e.Player, "StalkerStage2Remaining"))
        if stage == 2 then
            if rem and rem > 0 and rem ~= ctx.LastRem then
                ctx.LastRem = rem
                ctx.RemEnd = now + rem
            end
        else
            ctx.RemEnd, ctx.LastRem = nil, nil
        end
        local left = ctx.RemEnd and math.max(ctx.RemEnd - now, 0) or 0
        local timerText = left > 0 and string.format("Stage II: %ds", math.ceil(left)) or ""
        SetIf(ctx.Timer, "Text", timerText)
        SetIf(ctx.Timer, "TextColor3", left <= 10 and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 200, 60))
        SetIf(ctx.Timer, "Visible", timerText ~= "")
        SetIf(ctx.Div2, "Visible", timerText ~= "")

        local grab = ReadAttr(e.Model, e.Player, "StalkerGrabArmVisible") == true
        SetIf(ctx.Grab, "Text", grab and "Grab!" or "")
        SetIf(ctx.Grab, "TextColor3", Color3.fromRGB(255, 90, 90))
        SetIf(ctx.Grab, "Visible", grab)
        SetIf(ctx.Div3, "Visible", grab)

        -- [NEW] стак (StalkerNet = UpdateStalking из PowersMyers)
        StalkerNet.Bind()
        local fresh = now - StalkerNet.At < 1
        local stalking = fresh and StalkerNet.Active
        local stalkText, stalkColor
        if StalkerNet.Progress == nil then
            stalkText, stalkColor = "Stalk: ?", scheme.FontColor -- событие ни разу не пришло
        elseif StalkerNet.Ready then
            stalkText, stalkColor = "Stage II ready", Color3.fromRGB(255, 90, 90)
        else
            local pct = math.clamp(math.floor(StalkerNet.Progress + 0.5), 0, 100)
            stalkText = string.format("%sStage II: %d%%", stalking and "Stalking · " or "", pct)
            stalkColor = stalking and Color3.fromRGB(255, 170, 60) or scheme.FontColor
        end
        local showStalk = stage ~= 2 -- во 2-м стейдже стак недоступен (PowersMyers: Stage ~= 2), там таймер
        SetIf(ctx.Stalk, "Text", stalkText)
        SetIf(ctx.Stalk, "TextColor3", stalkColor)
        SetIf(ctx.Stalk, "Visible", showStalk)
        SetIf(ctx.Div4, "Visible", showStalk)

        -- цель показываем только пока известно, что он сталкерит
        local targetText, targetColor = "", scheme.FontColor
        if stalking and showStalk then
            local model, name = StalkerGuessTarget(e)
            if model then
                if model == LocalPlayer.Character then
                    targetText, targetColor = "Target: YOU", Color3.fromRGB(255, 80, 80)
                else
                    targetText, targetColor = "Target: " .. name, Color3.fromRGB(255, 200, 60)
                end
            end
        end
        SetIf(ctx.Target, "Text", targetText)
        SetIf(ctx.Target, "TextColor3", targetColor)
        SetIf(ctx.Target, "Visible", targetText ~= "")
        SetIf(ctx.Div5, "Visible", targetText ~= "")

        for _, d in ipairs({ ctx.Div1, ctx.Div2, ctx.Div3, ctx.Div4, ctx.Div5 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== BUTCHER ===== [NEW]
-- Источник: save.rbxmx -> LocalScript "Animations" (Powers Butcher'а).
-- Атрибуты персонажа: Beartraps (кол-во капканов), ChainMove1CD (кулдаун цепи, сек, 0 = готово),
-- ChainInUse (цепь в полёте), ChainLatched (цепь зацепилась). Установка капкана видна по анимации.
local BUTCHER_ANIMS = {
    ["132475036202731"] = "placetrap", -- animations.placetrap
}

local function ButcherActive(e)
    local out = {}
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return out end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        local k = id and BUTCHER_ANIMS[id]
        if k then out[k] = true end
    end
    return out
end

KillerHUD.Register("Butcher", {
    Build = function(ctx)
        ctx.Div1  = HudDivider(ctx.Body, 2)
        ctx.Traps = HudLabel(ctx.Body, "Traps: ?", 3)
        ctx.Div2  = HudDivider(ctx.Body, 4)
        ctx.Chain = HudLabel(ctx.Body, "Chain ready", 5)
        ctx.Div3  = HudDivider(ctx.Body, 6)
        ctx.State = HudLabel(ctx.Body, "", 7)
        ctx.LastTraps, ctx.TrapQueue, ctx.TrapEnd = nil, 0, nil
        ctx.LastCD, ctx.ChainEnd = nil, nil
        ctx.PlaceStart = nil
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        local B = CONFIG.Butcher

        -- капканы: как runQueuedCooldowns в Powers - каждый потраченный капкан = +45с в очередь,
        -- при Beartraps >= MaxTraps очередь сбрасывается
        local traps = tonumber(ReadAttr(e.Model, e.Player, "Beartraps"))
        if traps then
            if ctx.LastTraps and traps < ctx.LastTraps then
                ctx.TrapQueue += ctx.LastTraps - traps
                if not ctx.TrapEnd then ctx.TrapEnd = now + B.TrapRecharge end
            elseif ctx.LastTraps and traps > ctx.LastTraps then
                if traps >= B.MaxTraps then
                    ctx.TrapQueue, ctx.TrapEnd = 0, nil
                else
                    ctx.TrapQueue = math.max(ctx.TrapQueue - (traps - ctx.LastTraps), 0)
                    ctx.TrapEnd = ctx.TrapQueue > 0 and (now + B.TrapRecharge) or nil
                end
            end
            ctx.LastTraps = traps
        end
        local trapText
        if traps == nil then
            trapText = "Traps: ?"
        else
            trapText = string.format("Traps: %d/%d", traps, B.MaxTraps)
            if ctx.TrapEnd and traps < B.MaxTraps then
                trapText = string.format("%s · next %.1fs", trapText, math.max(ctx.TrapEnd - now, 0))
            end
        end
        SetIf(ctx.Traps, "Text", trapText)
        SetIf(ctx.Traps, "TextColor3", (traps or 1) > 0 and scheme.FontColor or Color3.fromRGB(255, 200, 60))
        HudSetCD(ctx.Traps, traps == 0) -- [NEW v5] капканов нет - всё в перезарядке

        -- цепь: ChainMove1CD > 0 -> кулдаун на столько секунд (Powers: makeMoveCooldown(..., ChainMove1CD))
        local cd = tonumber(ReadAttr(e.Model, e.Player, "ChainMove1CD")) or 0
        if cd > 0 then
            if cd ~= ctx.LastCD then ctx.ChainEnd = now + cd end
        else
            ctx.ChainEnd = nil
        end
        ctx.LastCD = cd
        local latched = ReadAttr(e.Model, e.Player, "ChainLatched") == true
        local inUse = ReadAttr(e.Model, e.Player, "ChainInUse") == true
        local chainText, chainColor
        if latched then
            chainText, chainColor = "Chain latched!", Color3.fromRGB(255, 80, 80)
        elseif inUse then
            chainText, chainColor = "Chain thrown", Color3.fromRGB(255, 170, 60)
        elseif ctx.ChainEnd and ctx.ChainEnd > now then
            chainText, chainColor = string.format("Chain: %.1fs", ctx.ChainEnd - now), Color3.fromRGB(255, 200, 60)
        elseif cd > 0 then
            chainText, chainColor = "Chain: cooldown", Color3.fromRGB(255, 200, 60)
        else
            chainText, chainColor = "Chain ready", Color3.fromRGB(90, 225, 130)
        end
        SetIf(ctx.Chain, "Text", chainText)
        SetIf(ctx.Chain, "TextColor3", chainColor)
        HudSetCD(ctx.Chain, not latched and not inUse and cd > 0) -- [NEW v5]

        -- установка капкана (анимация placetrap, длительность TrapPlaceTime)
        local active = ButcherActive(e)
        local stateText = ""
        if active.placetrap then
            if not ctx.PlaceStart then ctx.PlaceStart = now end
            stateText = string.format("Placing trap %.1fs", math.max(B.TrapPlaceTime - (now - ctx.PlaceStart), 0))
        else
            ctx.PlaceStart = nil
        end
        SetIf(ctx.State, "Text", stateText)
        SetIf(ctx.State, "TextColor3", Color3.fromRGB(255, 0, 255))
        SetIf(ctx.State, "Visible", stateText ~= "")
        SetIf(ctx.Div3, "Visible", stateText ~= "")

        for _, d in ipairs({ ctx.Div1, ctx.Div2, ctx.Div3 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== KILLER (Frenzy) ===== [NEW v5]
-- Источник: Workspace.<killer>.Powers (Remotes.Killers.Killer).
-- Атрибуты персонажа: Frenzy (вкл/выкл), FrenzyLungePending (рывок в полёте), FrenzyEnding (отмена).
-- Окно Frenzy в Powers: startFrenzyUI(13), перезапускается на FrenzyHitEvent (попадание).
-- Кулдаун приходит только через CooldownEvent(seconds) и FrenzyHitEvent - это события клиенту киллера.
-- Слушаем их на всякий случай: если до нас не доходят, кулдаун показывается как "?".
local KILLER_FRENZY_WINDOW = 13
local KillerNet = { Bound = false, CdEnd = nil, HitAt = nil }

function KillerNet.Bind()
    if KillerNet.Bound then return end
    local r = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    r = r and r:FindFirstChild("Killers")
    r = r and r:FindFirstChild("Killer")
    if not r then return end
    local cd, hit = r:FindFirstChild("CooldownEvent"), r:FindFirstChild("FrenzyHitEvent")
    if not cd and not hit then return end
    KillerNet.Bound = true
    if cd and cd:IsA("RemoteEvent") then
        GlobalMaid:Give(cd.OnClientEvent:Connect(function(seconds)
            local n = tonumber(seconds)
            if n then KillerNet.CdEnd = os.clock() + n end
        end))
    end
    if hit and hit:IsA("RemoteEvent") then
        GlobalMaid:Give(hit.OnClientEvent:Connect(function()
            KillerNet.HitAt = os.clock()
        end))
    end
end

KillerHUD.Register("Killer", {
    Build = function(ctx)
        ctx.Div1   = HudDivider(ctx.Body, 2)
        ctx.Frenzy = HudLabel(ctx.Body, "Frenzy off", 3)
        ctx.Div2   = HudDivider(ctx.Body, 4)
        ctx.Power  = HudLabel(ctx.Body, "Power: ?", 5)
        ctx.Div3   = HudDivider(ctx.Body, 6)
        ctx.Debug  = HudLabel(ctx.Body, "", 7)
        ctx.FrenzyStart, ctx.LastFrenzy, ctx.EndedAt = nil, false, nil
        KillerNet.Bind()
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        KillerNet.Bind()

        local frenzy = ReadAttr(e.Model, e.Player, "Frenzy") == true
        local lunge = ReadAttr(e.Model, e.Player, "FrenzyLungePending") == true
        local ending = ReadAttr(e.Model, e.Player, "FrenzyEnding") == true
        if frenzy and not ctx.LastFrenzy then ctx.FrenzyStart, ctx.EndedAt = now, nil end
        if not frenzy and ctx.LastFrenzy then ctx.FrenzyStart, ctx.EndedAt = nil, now end
        ctx.LastFrenzy = frenzy

        -- окно 13с от старта или от последнего попадания (если FrenzyHitEvent до нас доходит)
        local text, color
        if frenzy then
            local from = ctx.FrenzyStart or now
            if KillerNet.HitAt and KillerNet.HitAt > from then from = KillerNet.HitAt end
            text = string.format("Frenzy %.1fs", math.max(KILLER_FRENZY_WINDOW - (now - from), 0))
            color = Color3.fromRGB(255, 80, 80)
            if lunge then text = text .. " · Lunge!" end
            if ending then text = text .. " · Ending" end
        else
            text, color = "Frenzy off", scheme.FontColor
        end
        SetIf(ctx.Frenzy, "Text", text)
        SetIf(ctx.Frenzy, "TextColor3", color)

        -- кулдаун силы: известен только если CooldownEvent дошёл
        local cdLeft = KillerNet.CdEnd and (KillerNet.CdEnd - now) or nil
        local pText, pColor, onCd
        if frenzy then
            pText, pColor, onCd = "Power: active", Color3.fromRGB(255, 80, 80), false
        elseif cdLeft and cdLeft > 0 then
            pText, pColor, onCd = string.format("Power: %.1fs", cdLeft), Color3.fromRGB(255, 200, 60), true
        elseif KillerNet.CdEnd then
            pText, pColor, onCd = "Power ready", Color3.fromRGB(90, 225, 130), false
        else
            pText, pColor, onCd = "Power: ?", scheme.FontColor, false
        end
        SetIf(ctx.Power, "Text", pText)
        SetIf(ctx.Power, "TextColor3", pColor)
        HudSetCD(ctx.Power, onCd)

        -- дебаг: сырые атрибуты + сколько прошло после конца Frenzy
        local dbg = string.format("F=%s L=%s E=%s", tostring(frenzy), tostring(lunge), tostring(ending))
        if ctx.EndedAt then dbg = dbg .. string.format(" · ended %ds ago", math.floor(now - ctx.EndedAt)) end
        SetIf(ctx.Debug, "Text", dbg)
        SetIf(ctx.Debug, "TextColor3", scheme.FontColor)
        SetIf(ctx.Debug, "TextTransparency", 0.35)

        for _, d in ipairs({ ctx.Div1, ctx.Div2, ctx.Div3 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== ABYSSWALKER ===== [NEW v8]
-- Источник: save.rbxmx (luquinhasggs) -> LocalScript Animations (там же его абилки).
-- Slash (Move1): анимация slash, рывок 0.8с -> удар -> 0.2с + 2.6с замедления -> кулдаун 25с.
-- Corrupt (Move2): анимация corrupt, стоит на месте, выстрел через 1с, конец = конец анимации -> кулдаун 25с.
-- Стан (IsStunned) во время абилки -> кулдаун не начинается (u228/u241 = true).
local ABYSS = {
    SlashAnim = "100014992013740",
    CorruptAnim = "75613723058031",
    SlashActive = 0.8 + 0.2 + 2.6,
    SlashCooldown = 25,
    CorruptFire = 1,
    CorruptCooldown = 25,
}

local function AbyssActive(e)
    local out = {}
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return out end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        if id == ABYSS.SlashAnim then out.slash = true end
        if id == ABYSS.CorruptAnim then out.corrupt = true end
    end
    return out
end

KillerHUD.Register("Abysswalker", {
    Build = function(ctx)
        ctx.Div1    = HudDivider(ctx.Body, 2)
        ctx.Slash   = HudLabel(ctx.Body, "Slash ready", 3)
        ctx.Div2    = HudDivider(ctx.Body, 4)
        ctx.Corrupt = HudLabel(ctx.Body, "Corrupt ready", 5)
        ctx.SlashStart, ctx.SlashCD, ctx.LastSlash = nil, nil, false
        ctx.CorruptStart, ctx.CorruptCD, ctx.LastCorrupt = nil, nil, false
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        local active = AbyssActive(e)
        local stunned = ReadAttr(e.Model, e.Player, "IsStunned") == true

        -- Slash
        if active.slash and not ctx.LastSlash then ctx.SlashStart, ctx.SlashCD = now, nil end
        ctx.LastSlash = active.slash == true
        if ctx.SlashStart then
            if stunned then
                ctx.SlashStart = nil -- застанили: кулдауна нет
            elseif now >= ctx.SlashStart + ABYSS.SlashActive then
                ctx.SlashCD = ctx.SlashStart + ABYSS.SlashActive + ABYSS.SlashCooldown
                ctx.SlashStart = nil
            end
        end
        local text, color, onCd
        if ctx.SlashStart then
            text, color, onCd = "Slash!", Color3.fromRGB(255, 80, 80), false
        elseif ctx.SlashCD and now < ctx.SlashCD then
            text, color, onCd = string.format("Slash: %.1fs", ctx.SlashCD - now), Color3.fromRGB(255, 200, 60), true
        else
            text, color, onCd = "Slash ready", Color3.fromRGB(90, 225, 130), false
        end
        SetIf(ctx.Slash, "Text", text)
        SetIf(ctx.Slash, "TextColor3", color)
        HudSetCD(ctx.Slash, onCd)

        -- Corrupt
        if active.corrupt and not ctx.LastCorrupt then ctx.CorruptStart, ctx.CorruptCD = now, nil end
        if not active.corrupt and ctx.LastCorrupt and ctx.CorruptStart then
            ctx.CorruptCD = (not stunned) and (now + ABYSS.CorruptCooldown) or nil
            ctx.CorruptStart = nil
        end
        ctx.LastCorrupt = active.corrupt == true
        if ctx.CorruptStart then
            local toFire = ABYSS.CorruptFire - (now - ctx.CorruptStart)
            text = toFire > 0 and string.format("Corrupt: fire in %.1fs", toFire) or "Corrupt firing!"
            color, onCd = Color3.fromRGB(255, 80, 80), false
        elseif ctx.CorruptCD and now < ctx.CorruptCD then
            text, color, onCd = string.format("Corrupt: %.1fs", ctx.CorruptCD - now), Color3.fromRGB(255, 200, 60), true
        else
            text, color, onCd = "Corrupt ready", Color3.fromRGB(90, 225, 130), false
        end
        SetIf(ctx.Corrupt, "Text", text)
        SetIf(ctx.Corrupt, "TextColor3", color)
        HudSetCD(ctx.Corrupt, onCd)

        for _, d in ipairs({ ctx.Div1, ctx.Div2 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
})

-- ===== SLASHER ===== [NEW]
-- Источник: save.rbxmx (BAKY_750) -> LocalScript Powers + PursuitPalletPredict.
-- Move1 "Lake Mist" (невидимость): атрибут персонажа LakeMist, макс. 13с, потом КД 30с.
-- Move2 "Pursuit": атрибут Pursuit (его слушает PursuitPalletPredict), 22с, потом КД 60с.
-- Атрибутов кулдауна нет -> отсчёт начинается, когда мы видим смену атрибута (как у Hidden/Masked).
local function SlasherTimer(ctx, key, on, now, duration, cooldown)
    local last = ctx["Last" .. key]
    if on and not last then
        ctx[key .. "Start"], ctx[key .. "CD"] = now, nil
    elseif not on and last then
        ctx[key .. "Start"], ctx[key .. "CD"] = nil, now + cooldown
    end
    ctx["Last" .. key] = on
    if on then
        local start = ctx[key .. "Start"] or now
        return math.max(duration - (now - start), 0), nil
    end
    local cd = ctx[key .. "CD"]
    return nil, (cd and cd > now) and (cd - now) or nil
end

local SlasherHud = {
    Build = function(ctx)
        ctx.Div1    = HudDivider(ctx.Body, 2)
        ctx.Mist    = HudLabel(ctx.Body, "Mist ready", 3)
        ctx.Div2    = HudDivider(ctx.Body, 4)
        ctx.Pursuit = HudLabel(ctx.Body, "Pursuit ready", 5)
    end,

    Update = function(ctx, e)
        local scheme = Library.Scheme
        local now = os.clock()
        local C = CONFIG.Slasher

        local mist = ReadAttr(e.Model, e.Player, "LakeMist") == true
        local mLeft, mCd = SlasherTimer(ctx, "Mist", mist, now, C.MistDuration, C.MistCooldown)
        local text, color
        if mLeft then
            text, color = string.format("Invisible %.1fs", mLeft), Color3.fromRGB(190, 160, 255)
        elseif mCd then
            text, color = string.format("Mist: %.1fs", mCd), Color3.fromRGB(255, 200, 60)
        else
            text, color = "Mist ready", Color3.fromRGB(90, 225, 130)
        end
        SetIf(ctx.Mist, "Text", text)
        SetIf(ctx.Mist, "TextColor3", color)
        HudSetCD(ctx.Mist, mCd ~= nil) -- [NEW v5]

        local pursuit = ReadAttr(e.Model, e.Player, "Pursuit") == true
        local pLeft, pCd = SlasherTimer(ctx, "Pursuit", pursuit, now, C.PursuitDuration, C.PursuitCooldown)
        if pLeft then
            text, color = string.format("Pursuit %.1fs", pLeft), Color3.fromRGB(255, 80, 80)
        elseif pCd then
            text, color = string.format("Pursuit: %.1fs", pCd), Color3.fromRGB(255, 200, 60)
        else
            text, color = "Pursuit ready", Color3.fromRGB(90, 225, 130)
        end
        SetIf(ctx.Pursuit, "Text", text)
        SetIf(ctx.Pursuit, "TextColor3", color)
        HudSetCD(ctx.Pursuit, pCd ~= nil) -- [NEW v5]

        for _, d in ipairs({ ctx.Div1, ctx.Div2 }) do
            SetIf(d, "BackgroundColor3", scheme.OutlineColor)
        end
    end,
}
-- имя MorphedKiller в файле не видно: в GUI он "Slasher", в ремоутах "Jason" -> регистрируем оба
KillerHUD.Register("Slasher", SlasherHud)
KillerHUD.Register("Jason", SlasherHud)

-- [v55] «умный» детект: идёт ли киллер к тебе. Берём не мгновенную скорость (у игры она врёт, см. 16 при
-- починке), а смещение за последние ~0.6с: насколько сократилось расстояние (ст/с) и куда он реально
-- двигается (косинус между смещением и направлением на тебя). Видит ли тебя - луч от головы до головы.
-- Состояния с удержанием 0.5с, чтобы не мигало:
--   Chasing you (красный)      - сближается >= 5 ст/с, идёт на тебя, тебя видно; + время до тебя
--   Coming your way (оранжевый) - то же, но тебя не видно (за стеной)
--   Moving away (зелёный)       - удаляется >= 5 ст/с
function KillerHUD.LOS(from, to, ignore)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local filter = { Containers.Root }
    for _, x in ipairs(ignore) do if x then table.insert(filter, x) end end
    for _ = 1, 6 do
        rp.FilterDescendantsInstances = filter
        local hit = workspace:Raycast(from, to - from, rp)
        if not hit then return true end
        if hit.Instance.Transparency < 0.5 and hit.Instance.CanCollide then return false end
        table.insert(filter, hit.Instance)
    end
    return true
end

function KillerHUD.Approach(self, ctx, e)
    local myChar = LocalPlayer.Character
    local myRoot = GetRoot(myChar)
    local show = myRoot ~= nil and e.Root ~= nil and e.Root.Parent ~= nil
    SetIf(ctx.Dist, "Visible", show)
    SetIf(ctx.DistDiv, "Visible", show)
    if not show then
        SetIf(ctx.App, "Visible", false)
        SetIf(ctx.AppDiv, "Visible", false)
        return
    end
    local now = os.clock()
    local kPos, mPos = e.Root.Position, myRoot.Position
    local d = (kPos - mPos).Magnitude
    SetIf(ctx.Dist, "Text", FormatDist(d))
    SetIf(ctx.Dist, "TextColor3", Library.Scheme.FontColor)

    self.Hist = self.Hist or setmetatable({}, { __mode = "k" })
    local h = self.Hist[e.Model]
    if not h then h = { S = {} } self.Hist[e.Model] = h end
    table.insert(h.S, { T = now, D = d, P = kPos })
    while #h.S > 2 and now - h.S[1].T > 0.6 do table.remove(h.S, 1) end

    local state
    local old = h.S[1]
    local dt = now - old.T
    if dt >= 0.25 then
        local closing = (old.D - d) / dt
        local move = Vector3.new(kPos.X - old.P.X, 0, kPos.Z - old.P.Z)
        local toMe = Vector3.new(mPos.X - kPos.X, 0, mPos.Z - kPos.Z)
        local heading = (move.Magnitude > 0.5 and toMe.Magnitude > 0.1) and move.Unit:Dot(toMe.Unit) or 0
        if closing >= 5 and heading >= 0.7 then
            local head = e.Model:FindFirstChild("Head")
            local myHead = myChar:FindFirstChild("Head")
            local from = (head and head:IsA("BasePart")) and head.Position or kPos
            local to = (myHead and myHead:IsA("BasePart")) and myHead.Position or mPos
            local sees = KillerHUD.LOS(from, to, { e.Model, myChar })
            state = { Text = sees and "Chasing you" or "Coming your way",
                Color = sees and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 160, 60), Eta = d / closing }
        elseif closing <= -5 then
            state = { Text = "Moving away", Color = Color3.fromRGB(90, 225, 130) }
        end
    end
    if state then
        h.State, h.Until = state, now + 0.5
    elseif h.State and now > (h.Until or 0) then
        h.State = nil
    end
    local st = h.State
    local text = st and st.Text or ""
    if st and st.Eta and st.Eta < 15 then text = string.format("%s · %.1fs", text, st.Eta) end
    SetIf(ctx.App, "Text", text)
    if st then SetIf(ctx.App, "TextColor3", st.Color) end
    SetIf(ctx.App, "Visible", st ~= nil)
    SetIf(ctx.AppDiv, "Visible", st ~= nil)
    SetIf(ctx.DistDiv, "BackgroundColor3", Library.Scheme.OutlineColor)
    SetIf(ctx.AppDiv, "BackgroundColor3", Library.Scheme.OutlineColor)
end

DefineFeature({
    Id = "KillerHUD_",
    Toggle = "KillerHUD_Enabled",

    Enable = function(self)
        self.Gui = self.Maid:Give(NewOverlayGui())
        local pill = New("Frame", {
            Name = "Pill",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, CONFIG.HUDTop),
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BorderSizePixel = 0,
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.35,
            Active = true,
            Visible = false,
            Parent = self.Gui,
        })
        -- [v91] стиль ватермарки gamesense: тёмная полоса без углов и обводки, растворяется по краям
        New("UIGradient", { Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.25),
            NumberSequenceKeypoint.new(0.82, 0.25), NumberSequenceKeypoint.new(1, 1),
        }), Parent = pill })
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 34), PaddingRight = UDim.new(0, 34),
            PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0),
            Parent = pill,
        })
        self.Pill = pill

        local dragging, dragStart, startPos = false, nil, nil
        self.Maid:Give(pill.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, pill.Position
                local c
                c = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        c:Disconnect()
                    end
                end)
            end
        end))
        self.Maid:Give(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                pill.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end))
    end,

    Rebuild = function(self, def, e, title)
        if self.Body then self.Body:Destroy() end
        local body = New("Frame", {
            Name = "Body",
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Parent = self.Pill,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7), -- [v91] с невидимыми разделителями = ~14 px между пунктами, как у ватермарки
            Parent = body,
        })
        self.Body = body
        local ctx = { Body = body }
        ctx.Title = HudLabel(body, title, 1)
        if def.Build then def.Build(ctx) end
        -- [v55] всегда: расстояние до киллера + «идёт к тебе» (в конце панели)
        ctx.DistDiv = HudDivider(body, 90)
        ctx.Dist = HudLabel(body, "", 91)
        ctx.AppDiv = HudDivider(body, 92)
        ctx.App = HudLabel(body, "", 93)
        self.Ctx = ctx
    end,

    Update = function(self)
        local pill = self.Pill
        if not pill then return end

        local e = Targets.Killers[1]
        if not e then
            pill.Visible = false
            self.Key = nil
            return
        end

        local scheme = Library.Scheme

        local kt = ReadAttr(e.Model, e.Player, "MorphedKiller")
        kt = type(kt) == "string" and kt or ""
        local key = HudKey(kt)
        local def = KillerHUD.Defs[key] or KillerHUD.Defs.default
        local full = KillerTypeText(e.Model, e.Player)
        local title = full ~= "" and full or e.Name

        if self.Key ~= key or self.Model ~= e.Model then
            self.Key, self.Model = key, e.Model
            self:Rebuild(def, e, title)
        end

        local ctx = self.Ctx
        SetIf(ctx.Title, "Text", title)
        SetIf(ctx.Title, "TextColor3", scheme.AccentColor)
        if def.Update then def.Update(ctx, e) end
        KillerHUD.Approach(self, ctx, e)
        pill.Visible = true
    end,

    Disable = function(self)
        self.Gui, self.Pill, self.Body, self.Ctx, self.Stroke = nil, nil, nil, nil, nil
        self.Key, self.Model = nil, nil
    end,
})

------------------------------------------------------------
-- Hidden: предсказание Leap / Mark + тег Invisible
------------------------------------------------------------
-- Leap: физика из Powers (doAimableArchJump): горизонтальная скорость (cos(p)*0.3+0.7)*65,
-- вертикальная (max(0,sin(p))*30+20)*1.5, гравитация workspace.Gravity, приземление
-- когда падает и до земли <= 3.5 стад.
-- [CHANGED v5] В Powers и наклон (высота/длина), и горизонтальное направление берутся из камеры
-- (CurrentCamera.CFrame.LookVector). Для себя - камера. Для чужого киллера камера недоступна,
-- но Lookscript шлёт CurrentCamera.CFrame.LookVector на сервер (UpdateCharacterLook) и поворачивает
-- шею -> голова смотрит туда же, куда камера. Поэтому для чужого берём Head.LookVector целиком
-- (раньше из головы брался только наклон, а направление - из HRP, т.е. траектория не следовала за камерой).
local function HiddenLeapPath(root, model, camLook, rp)
    local pitch, dir
    local look = camLook
    if not look then
        local head = model:FindFirstChild("Head")
        look = (head and head:IsA("BasePart")) and head.CFrame.LookVector or nil
    end
    if look then
        pitch = math.asin(math.clamp(look.Y, -1, 1))
        dir = Vector3.new(look.X, 0, look.Z)
    else
        pitch = 0
    end
    if not dir or dir.Magnitude < 1e-3 then
        local l = root.CFrame.LookVector
        dir = Vector3.new(l.X, 0, l.Z)
    end
    if dir.Magnitude < 1e-3 then return nil end
    dir = dir.Unit

    local speed = (math.cos(pitch) * 0.3 + 0.7) * 65
    local vy = (math.max(0, math.sin(pitch)) * 30 + 20) * 1.5
    local g = workspace.Gravity
    local pos = root.Position
    local pts = { pos }
    local dt, t = 0.025, 0

    for _ = 1, 80 do
        t += dt
        vy -= g * dt
        local delta = Vector3.new(dir.X * speed * dt, vy * dt, dir.Z * speed * dt)
        local wall = workspace:Raycast(pos, delta, rp)
        if wall then
            pts[#pts + 1] = wall.Position
            return pts, wall.Position
        end
        pos += delta
        pts[#pts + 1] = pos
        if vy <= 0 and t > 0.15 then
            local ground = workspace:Raycast(pos, Vector3.new(0, -3.5, 0), rp)
            if ground then
                local land = Vector3.new(pos.X, ground.Position.Y, pos.Z)
                pts[#pts + 1] = land
                return pts, land
            end
        end
    end
    return pts, pos
end

DefineFeature({
    Id = "HiddenPredict_",
    Gate = { "HiddenLeap_Enabled", "HiddenMark_Enabled" },
    Watch = { "HiddenLeap_Color", "HiddenMark_Color", "HiddenPredict_Thickness" },
    Lines = {},
    Rings = {},
    Texts = {}, -- [NEW v5]

    Enable = function(self)
        self.Gui = self.Maid:Give(NewOverlayGui())
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.RespectCanCollide = true
        rp.IgnoreWater = true
        self.RayParams = rp
    end,

    Render = function(self)
        local gui, cam, rp = self.Gui, workspace.CurrentCamera, self.RayParams
        if not gui or not cam or not rp then return end

        local camCF = cam.CFrame
        local near = 0.1
        local thickness = Options.HiddenPredict_Thickness.Value
        local showLeap = Toggles.HiddenLeap_Enabled.Value
        local showMark = Toggles.HiddenMark_Enabled.Value
        local leapColor = Options.HiddenLeap_Color.Value
        local markColor = Options.HiddenMark_Color.Value
        -- [CHANGED v23] без настройки: HiddenMarkDash distanceAt(0.4) = (2t - t^2) * 41 при t = 1
        local markRange = 41
        local usedL, usedR = 0, 0

        local usedT = 0
        local alpha = 0 -- [NEW v5] прозрачность текущего трейсера (0.5 в кулдауне)

        local function line(a, b, color)
            local da = -camCF:PointToObjectSpace(a).Z
            local db = -camCF:PointToObjectSpace(b).Z
            if da < near and db < near then return end
            if da < near or db < near then
                local k = (near - da) / (db - da)
                if da < near then a = a + (b - a) * k else b = a + (b - a) * k end
            end
            local sa = cam:WorldToViewportPoint(a)
            local sb = cam:WorldToViewportPoint(b)
            usedL += 1
            local f = self.Lines[usedL]
            if not f then
                f = New("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    BorderSizePixel = 0,
                    Visible = false,
                    Parent = gui,
                })
                self.Lines[usedL] = f
            end
            SetLineFrame(f, Vector2.new(sa.X, sa.Y), Vector2.new(sb.X, sb.Y), color, thickness)
            SetIf(f, "BackgroundTransparency", alpha)
        end

        -- [NEW v5] секунды кулдауна по центру трейсера: цвет = цвет трейсера из его ColorPicker
        -- (HiddenLeap_Color / HiddenMark_Color), полупрозрачный
        local function cdText(p, seconds, color)
            local sp = cam:WorldToViewportPoint(p)
            if sp.Z <= 0 then return end
            usedT += 1
            local t = self.Texts[usedT]
            if not t then
                t = New("TextLabel", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.fromOffset(60, 18),
                    BackgroundTransparency = 1,
                    Font = CONFIG.TagFont,
                    TextSize = math.floor(15 * (Library.ESPTextK or 1) + 0.5), -- [v64]
                    TextStrokeTransparency = 0.6,
                    Visible = false,
                    Parent = gui,
                })
                Library:ApplyESPFont(t) -- [v62]
                self.Texts[usedT] = t
            end
            SetIf(t, "Position", UDim2.fromOffset(sp.X, sp.Y))
            SetIf(t, "Text", string.format("%.1fs", seconds))
            SetIf(t, "TextColor3", color)
            SetIf(t, "TextTransparency", HUD_CD_TRANSPARENCY)
            SetIf(t, "Visible", true)
        end

        local function ring(p, color)
            local sp = cam:WorldToViewportPoint(p)
            if sp.Z <= 0 then return end
            usedR += 1
            local r = self.Rings[usedR]
            if not r then
                local f = New("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Size = UDim2.fromOffset(16, 16),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Visible = false,
                    Parent = gui,
                })
                New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
                r = { Frame = f, Stroke = New("UIStroke", { Thickness = 2, Parent = f }) }
                self.Rings[usedR] = r
            end
            r.Frame.Position = UDim2.fromOffset(sp.X, sp.Y)
            r.Stroke.Color = color
            r.Stroke.Transparency = alpha
            r.Frame.Visible = true
        end

        local list = {}
        for _, e in ipairs(Targets.Killers) do
            if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == "hidden" then
                list[#list + 1] = { Root = e.Root, Model = e.Model, Player = e.Player, Humanoid = e.Humanoid }
            end
        end
        local myChar = LocalPlayer.Character
        if myChar and LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer
            and HudKey(ReadAttr(myChar, LocalPlayer, "MorphedKiller")) == "hidden" then
            local r = GetRoot(myChar)
            if r then
                list[#list + 1] = { Root = r, Model = myChar, Player = LocalPlayer,
                    Humanoid = myChar:FindFirstChildOfClass("Humanoid"), Self = true }
            end
        end

        for _, k in ipairs(list) do
            local root = k.Root
            if root and root.Parent then
                rp.FilterDescendantsInstances = { k.Model }
                local st = HiddenCooldowns(k) -- [NEW v5]
                local now = os.clock()

                if showLeap then
                    -- [CHANGED v23] чужой Hidden: направление камеры из атрибутов CamLook / CamDir (как у Veil),
                    -- голова - только запасной вариант (шея поворачивается на 0.75 угла камеры вверх и 0.075 вниз,
                    -- из-за этого дуга получалась ниже и короче, чем реальный прыжок)
                    local aim = k.Self and camCF.LookVector or nil
                    if not aim then
                        -- [v56] сначала CamDir, потом CamLook. Вектор длины ~1 - направление; длиннее - это ТОЧКА,
                        -- куда смотрит камера -> направление = точка - камера (CamPos) / голова. Раньше точку
                        -- брали как направление (.Unit от мировой позиции) и дуга уходила не туда.
                        local head = k.Model:FindFirstChild("Head")
                        local camPos = ReadAttr(k.Model, k.Player, "CamPos")
                        if typeof(camPos) == "CFrame" then camPos = camPos.Position end
                        if typeof(camPos) ~= "Vector3" then camPos = (head and head:IsA("BasePart")) and head.Position or root.Position end
                        for _, name in ipairs({ "CamDir", "CamLook" }) do
                            local v = ReadAttr(k.Model, k.Player, name)
                            if typeof(v) == "CFrame" then v = v.LookVector end
                            if typeof(v) == "Vector3" and v.Magnitude > 1e-3 then
                                if v.Magnitude > 1.5 then v = v - camPos end
                                if v.Magnitude > 1e-3 then aim = v.Unit break end
                            end
                        end
                    end
                    local pts, land = HiddenLeapPath(root, k.Model, aim, rp)
                    if pts then
                        alpha = st.LeapLeft > 0 and HUD_CD_TRANSPARENCY or 0
                        for i = 1, #pts - 1 do line(pts[i], pts[i + 1], leapColor) end
                        ring(land, leapColor)
                        if st.LeapLeft > 0 then cdText(pts[math.max(math.floor(#pts / 2), 1)], st.LeapLeft, leapColor) end
                    end
                end

                if showMark then
                    -- [CHANGED v5] только направление HRP по горизонтали (как HiddenMarkDash.start(Character,
                    -- HumanoidRootPart.CFrame.LookVector)), без камеры и без наклона.
                    local look = root.CFrame.LookVector
                    local flat = Vector3.new(look.X, 0, look.Z)
                    local origin, dirUnit
                    if flat.Magnitude > 1e-3 then
                        origin, dirUnit = root.Position, flat.Unit
                        -- [CHANGED v5] с момента рывка трейсер замирает на точке и направлении старта,
                        -- а не едет вместе с киллером
                        if st.MarkStart and st.MarkDashAt and now >= st.MarkDashAt then
                            st.MarkFreeze = st.MarkFreeze or { Origin = origin, Dir = dirUnit }
                            origin, dirUnit = st.MarkFreeze.Origin, st.MarkFreeze.Dir
                        end
                    end
                    if origin then
                        -- [CHANGED v9] стена как в HiddenMarkDash:step - лоб в лоб (-normal·dir >= HEAD_ON 0.75)
                        -- рывок останавливается; под углом - скользит вдоль стены на остаток длины
                        local dir = dirUnit * markRange
                        local hit = workspace:Raycast(origin, dir, rp)
                        local endPos = hit and hit.Position or (origin + dir)
                        local slideEnd
                        if hit then
                            local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
                            if n.Magnitude > 0.3 and -n.Unit:Dot(dirUnit) < 0.75 then
                                local along = dirUnit - n.Unit * dirUnit:Dot(n.Unit)
                                local left = (markRange - (hit.Position - origin).Magnitude) * along.Magnitude
                                if along.Magnitude > 1e-3 and left > 0.1 then
                                    local start = hit.Position + n.Unit * 0.5
                                    local d2 = along.Unit * left
                                    local hit2 = workspace:Raycast(start, d2, rp)
                                    slideEnd = hit2 and hit2.Position or (start + d2)
                                end
                            end
                        end
                        alpha = st.MarkLeft > 0 and HUD_CD_TRANSPARENCY or 0
                        line(origin, endPos, markColor)
                        if slideEnd then line(endPos, slideEnd, markColor) end
                        ring(slideEnd or endPos, markColor)
                        if st.MarkLeft > 0 then cdText((origin + endPos) / 2, st.MarkLeft, markColor) end
                    end
                end
            end
        end

        for i = usedL + 1, #self.Lines do self.Lines[i].Visible = false end
        for i = usedR + 1, #self.Rings do self.Rings[i].Frame.Visible = false end
        for i = usedT + 1, #self.Texts do self.Texts[i].Visible = false end
    end,

    Disable = function(self)
        table.clear(self.Lines)
        table.clear(self.Rings)
        table.clear(self.Texts)
        self.Gui, self.RayParams = nil, nil
    end,
})

DefineFeature({
    Id = "HiddenInvis_",
    Toggle = "HiddenInvis_Enabled",
    Watch = { "HiddenInvis_Color" },

    Update = function(self)
        local color = Options.HiddenInvis_Color.Value
        local size = Options.KillerESP_TextSize.Value
        local seen = {}
        for _, e in ipairs(Targets.Killers) do
            if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == "hidden" then
                if IsInvisible(e.Model, e.Player) then
                    seen[e.Model] = true
                    Tags.Set(e.Model, "Invis", "Invisible", size, color)
                end
            end
        end
        Tags.PruneSlot("Invis", seen)
    end,

    Disable = function(self)
        Tags.RemoveSlotAll("Invis")
    end,
})

------------------------------------------------------------
-- Object ESP (Highlight, видно через стены)
------------------------------------------------------------
local OBJECT_PRIORITY = 3 -- игроки (0-2) всегда раньше; объекты между собой - по дальности

local function ObjectStyle(c)
    return {
        FillColor = c,
        FillTransparency = Options.Object_Fill.Value,
        OutlineColor = c,
        OutlineTransparency = Options.Object_Outline.Value,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }
end

local OBJECT_WATCH = { "Object_Fill", "Object_Outline" }

local function WatchWith(...)
    local t = { ... }
    for _, w in ipairs(OBJECT_WATCH) do t[#t + 1] = w end
    return t
end

local function MakeObjectChams(p, collect, static)
    local group = HighlightGroup.new(function() return ObjectStyle(Options[p .. "Color"].Value) end, OBJECT_PRIORITY, static)
    return DefineFeature({
        Id = p,
        Toggle = p .. "Enabled",
        Watch = WatchWith(p .. "Color"),
        Update = function(self) group:Sync(collect()) end,
        Disable = function(self) group:Clear() end,
    })
end

do
    -- [v43] свой Highlight на каждый генератор (раньше - непрозрачные копии деталей: двоились)
    local active = HighlightGroup.new(function() return ObjectStyle(Options.GenChams_Color.Value) end, OBJECT_PRIORITY, false)
    local done = HighlightGroup.new(function() return ObjectStyle(Options.GenChams_DoneColor.Value) end, OBJECT_PRIORITY, false)
    -- [v54] градиент: 11 ступеней по 10% (свой Highlight-стиль на ступень), цвета как у бара генератора
    local RED, YEL, GRN = Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 205, 70), Color3.fromRGB(70, 230, 120)
    local steps = {}
    for i = 0, 10 do
        local t = i / 10
        local c = t < 0.5 and RED:Lerp(YEL, t * 2) or YEL:Lerp(GRN, (t - 0.5) * 2)
        steps[i] = HighlightGroup.new(function() return ObjectStyle(c) end, OBJECT_PRIORITY, false)
    end
    DefineFeature({
        Id = "GenChams_",
        Toggle = "GenChams_Enabled",
        Watch = WatchWith("GenChams_Color", "GenChams_DoneColor", "GenChams_Gradient"),
        Update = function(self)
            local a, d, st = {}, {}, {}
            local grad = Toggles.GenChams_Gradient.Value
            for i = 0, 10 do st[i] = {} end
            for _, g in ipairs(Collect.Generators()) do
                local v = math.clamp(tonumber(g:GetAttribute("RepairProgress")) or 0, 0, 100)
                if grad then
                    local list = st[math.floor(v / 10)]
                    list[#list + 1] = g
                elseif v >= 100 then
                    d[#d + 1] = g
                else
                    a[#a + 1] = g
                end
            end
            active:Sync(a)
            done:Sync(d)
            for i = 0, 10 do steps[i]:Sync(st[i]) end
        end,
        Disable = function(self)
            active:Clear()
            done:Clear()
            for i = 0, 10 do steps[i]:Clear() end
        end,
    })
end

-- [CHANGED v3] true = статичный объект -> один Highlight на тип; зомби двигаются -> свои Highlight
-- [v43] паллеты - свой Highlight на настоящей модели: копия деталей не повторяла анимацию падения
-- (AnimationController в Intact) и оставалась стоять «призраком»
MakeObjectChams("PalletChams_", Collect.Pallets, false)
MakeObjectChams("PumpkinChams_", Collect.Pumpkins, true)
MakeObjectChams("WindowChams_", Collect.Windows, true)
MakeObjectChams("ZombieChams_", Collect.Zombies, false)
MakeObjectChams("TrapChams_", Collect.Traps, true)
MakeObjectChams("HookChams_", Collect.Hooks, true) -- [v78] крюки не двигаются - один общий Highlight

------------------------------------------------------------
-- Generator progress (свой GUI)
------------------------------------------------------------
local function GeneratorAnchor(model)
    local part = model.PrimaryPart
    if not part then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") and d.Transparency < 1 then part = d break end
        end
    end
    part = part or model:FindFirstChildWhichIsA("BasePart", true)
    if not part then return nil end

    -- низ считаем по ВИДИМЫМ частям (невидимые триггеры раздувают bounding box и бар уезжал под землю)
    local minY, found = math.huge, false
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") and d.Transparency < 0.95 then
            local y = d.Position.Y - d.Size.Y / 2
            if y < minY then minY = y end
            found = true
        end
    end
    local pivot = model:GetPivot().Position
    local target
    if found then
        target = Vector3.new(pivot.X, minY, pivot.Z)
    else
        local ok, cf, size = pcall(model.GetBoundingBox, model)
        if ok then
            target = cf.Position - Vector3.new(0, math.min(size.Y / 2, 4), 0)
        else
            target = part.Position - Vector3.new(0, 2, 0)
        end
    end
    return part, target - part.Position
end

local BAR_RED    = Color3.fromRGB(255, 80, 80)
local BAR_YELLOW = Color3.fromRGB(255, 205, 70)
local BAR_GREEN  = Color3.fromRGB(70, 230, 120)

-- [v54] прогресс ворот: первый числовой атрибут с "progress" в имени (кроме IsBeingProgressed).
-- Значение <= 1 считаем долей (0..1), иначе процентами. Имя атрибута в дампах нет - ищем по имени.
function Collect.GateProgress(objs)
    for _, o in ipairs(objs) do
        if o then
            local ok, attrs = pcall(o.GetAttributes, o)
            if ok and type(attrs) == "table" then
                for k, v in pairs(attrs) do
                    if type(v) == "number" and k ~= "IsBeingProgressed" and string.find(string.lower(k), "progress", 1, true) then
                        return v <= 1 and v * 100 or v
                    end
                end
            end
        end
    end
    return 0
end

local function GenBarColor(v, gradient)
    -- [v53] без градиента - цвет ESP генератора (Generator Color / Done Color при 100%)
    if not gradient then
        return v >= 100 and Options.GenChams_DoneColor.Value or Options.GenChams_Color.Value
    end
    local t = math.clamp(v / 100, 0, 1)
    if t < 0.5 then return BAR_RED:Lerp(BAR_YELLOW, t * 2) end
    return BAR_YELLOW:Lerp(BAR_GREEN, (t - 0.5) * 2)
end

DefineFeature({
    Id = "GenProgress_",
    Gate = { "GenProgress_Enabled", "GateProgress_Enabled" }, -- [v69] + ворота выхода (из NL v54)
    Watch = { "GenProgress_Height", "GenProgress_Width", "GenProgress_Percent", "GenProgress_Gradient", "GenProgress_ETA",
        "GenChams_Color", "GenChams_DoneColor" },
    Bars = {},
    Offset = Vector3.zero,

    -- [v65] вид как слайдер меню skeet (вариант 1): полоса 5px + чёрная рамка, заливка сверху светлее,
    -- процент жирным у конца заливки (наезжает на полосу), сверху справа - время до конца («~12s»).
    -- Без плашки и надписи GENERATOR. Готовый генератор - «DONE».
    CreateBar = function(self, gen, w)
        local part, base = GeneratorAnchor(gen)
        if not part then return nil end
        local scheme = Library.Scheme
        local H = 26
        local gui = New("BillboardGui", {
            Name = RandomName(),
            Size = UDim2.fromOffset(w + 40, H),
            SizeOffset = Vector2.new(0, -0.5),
            AlwaysOnTop = true,
            LightInfluence = 0,
            MaxDistance = 5000,
            Adornee = part,
            StudsOffsetWorldSpace = base,
            Parent = Containers.World,
        })
        local holder = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(w + 2, 7),
            BackgroundColor3 = Color3.fromRGB(10, 10, 10), BorderSizePixel = 0, Parent = gui })
        local track = New("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0, Parent = holder })
        local trackGrad = New("UIGradient", { Rotation = 90, Parent = track })
        local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = track })
        local fillGrad = New("UIGradient", { Rotation = 90, Parent = fill })
        local bold = Font.new((scheme.Font and scheme.Font.Family) or "rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        local label = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(40, 10), BackgroundTransparency = 1,
            FontFace = bold, TextSize = 10, TextColor3 = Color3.fromRGB(213, 213, 213), TextStrokeTransparency = 0.15,
            Text = "0%", ZIndex = 3, Parent = holder })
        local eta = New("TextLabel", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 0, -1), Size = UDim2.fromOffset(60, 10),
            BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, TextSize = 10, TextColor3 = Color3.fromRGB(168, 168, 168),
            TextStrokeTransparency = 0.3, Text = "", Visible = false, ZIndex = 3, Parent = holder })
        Library:ApplyESPFont(eta)
        -- [v69] из NL v52-54: под полосой «Unavailable» (ProgressPaused) или «In progress» (IsBeingProgressed)
        local status = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 11), Size = UDim2.fromOffset(80, 10),
            BackgroundTransparency = 1, TextSize = 10, TextStrokeTransparency = 0.3, Text = "", Visible = false, ZIndex = 3, Parent = holder })
        Library:ApplyESPFont(status)
        local uiScale = New("UIScale", { Parent = holder }) -- [v65]
        local bar = {
            Gui = gui, Part = part, Base = base, Holder = holder, Track = track, TrackGrad = trackGrad,
            Fill = fill, FillGrad = fillGrad, Label = label, Eta = eta, W = w, Value = -1, UIScale = uiScale, Scale = 1, Status = status,
            LastV = nil, LastT = nil, Rate = nil, ChangedAt = nil,
        }
        self.Bars[gen] = bar
        return bar
    end,

    Update = function(self)
        local w = Options.GenProgress_Width.Value
        local showPercent = Toggles.GenProgress_Percent.Value
        local showEta = Toggles.GenProgress_ETA.Value
        local gradient = Toggles.GenProgress_Gradient.Value
        local scheme = Library.Scheme
        self.Offset = Vector3.new(0, Options.GenProgress_Height.Value, 0)
        local now = os.clock()

        -- [v69] из NL v54: генераторы (RepairProgress) + рычаги ворот выхода (ExitLever: прогресс - числовой
        -- атрибут с "progress" в имени на Main / ExitLever / воротах)
        local items = {}
        if Toggles.GenProgress_Enabled.Value then
            for _, gen in ipairs(Collect.Generators()) do
                items[#items + 1] = { Model = gen, V = tonumber(gen:GetAttribute("RepairProgress")) or 0, Attr = { gen } }
            end
        end
        if Toggles.GateProgress_Enabled and Toggles.GateProgress_Enabled.Value then
            for lever in pairs(MapIndex.Sets.Levers) do
                if lever.Parent then
                    local main = lever:FindFirstChild("Main")
                    local attr = { main, lever, lever.Parent }
                    items[#items + 1] = { Model = lever, V = Collect.GateProgress(attr), Attr = attr }
                end
            end
        end
        local function flag(attr, name)
            for _, o in ipairs(attr) do
                if o and o:GetAttribute(name) == true then return true end
            end
            return false
        end

        local seen = {}
        for _, it in ipairs(items) do
            local gen = it.Model
            seen[gen] = true
            local bar = self.Bars[gen]
            -- якорная часть пропала (стриминг) или поменялась ширина -> пересоздаём
            if bar and (not bar.Gui.Parent or not bar.Part.Parent or bar.W ~= w) then
                pcall(bar.Gui.Destroy, bar.Gui)
                self.Bars[gen] = nil
                bar = nil
            end
            bar = bar or self:CreateBar(gen, w)
            if bar then
                local v = math.clamp(tonumber(it.V) or 0, 0, 100)
                local paused, busy = flag(it.Attr, "ProgressPaused"), flag(it.Attr, "IsBeingProgressed") -- [v69]
                SetIf(bar.Status, "Visible", paused or busy)
                SetIf(bar.Status, "Text", paused and "Unavailable" or "In progress")
                SetIf(bar.Status, "TextColor3", paused and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(120, 230, 140))
                -- скорость починки: по изменениям RepairProgress (сглаженно); стоит дольше 2.5 с - не чинят
                if bar.LastV and v > bar.LastV and bar.LastT and now - bar.LastT < 4 then
                    local inst = (v - bar.LastV) / math.max(now - bar.LastT, 1e-3)
                    bar.Rate = bar.Rate and (bar.Rate * 0.6 + inst * 0.4) or inst
                    bar.ChangedAt = now
                elseif bar.LastV and v < bar.LastV then
                    bar.Rate, bar.ChangedAt = nil, nil
                end
                if v ~= bar.LastV then bar.LastV, bar.LastT = v, now end
                local color = GenBarColor(v, gradient)
                if v ~= bar.Value then
                    bar.Value = v
                    bar.Fill.Size = UDim2.fromScale(v / 100, 1)
                    bar.Fill.Visible = v > 0
                    local a = v / 100
                    bar.Label.Text = v >= 100 and "DONE" or string.format("%d%%", math.floor(v + 0.5))
                    bar.Label.AnchorPoint = Vector2.new(a <= 0.08 and 0 or 0.5, 0)
                    bar.Label.Position = UDim2.new(a, a <= 0.08 and -1 or 0, 0, 2)
                end
                SetIf(bar.Label, "Visible", showPercent)
                local etaText = ""
                if showEta and v < 100 and bar.Rate and bar.Rate > 0 and bar.ChangedAt and now - bar.ChangedAt < 2.5 then
                    etaText = string.format("~%ds", math.max(1, math.floor((100 - v) / bar.Rate + 0.5)))
                end
                SetIf(bar.Eta, "Text", etaText)
                SetIf(bar.Eta, "Visible", etaText ~= "")
                local t = scheme.TrackColor or Color3.fromRGB(52, 52, 52)
                SetIf(bar.TrackGrad, "Color", ColorSequence.new(t, t:Lerp(Color3.new(1, 1, 1), 0.074)))
                SetIf(bar.FillGrad, "Color", ColorSequence.new(color, Color3.new(color.R * 0.67, color.G * 0.67, color.B * 0.67)))
                SetIf(bar.Gui, "StudsOffsetWorldSpace", bar.Base + self.Offset)
            end
        end
        for gen, bar in pairs(self.Bars) do
            if not seen[gen] then
                pcall(bar.Gui.Destroy, bar.Gui)
                self.Bars[gen] = nil
            end
        end
    end,

    Render = function(self)
        local cam = workspace.CurrentCamera
        if not cam then return end
        local camPos = cam.CFrame.Position
        for _, bar in pairs(self.Bars) do
            local part = bar.Part
            if part and part.Parent then
                local pos = part.Position + bar.Base + self.Offset
                local dist = math.max((camPos - pos).Magnitude, 1)
                local target = math.clamp(CONFIG.GenBarRefDistance / dist, CONFIG.GenBarMinScale, CONFIG.GenBarMaxScale)
                bar.Scale = bar.Scale + (target - bar.Scale) * 0.3
                SetIf(bar.UIScale, "Scale", math.floor(bar.Scale * 20 + 0.5) / 20) -- [v65] масштаб по дистанции шагами 5%
            end
        end
    end,

    Disable = function(self)
        for _, bar in pairs(self.Bars) do pcall(bar.Gui.Destroy, bar.Gui) end
        table.clear(self.Bars)
    end,
})

------------------------------------------------------------
-- World
------------------------------------------------------------
local PropertyLock = {}
PropertyLock.__index = PropertyLock

function PropertyLock.new(maid)
    return setmetatable({ Originals = {}, Maid = maid }, PropertyLock)
end

function PropertyLock:Lock(inst, prop, value)
    local per = self.Originals[inst]
    if not per then
        per = {}
        self.Originals[inst] = per
    end
    if per[prop] ~= nil then return end
    per[prop] = inst[prop]
    pcall(function() inst[prop] = value end)
    self.Maid:Give(inst:GetPropertyChangedSignal(prop):Connect(function()
        local current = inst[prop]
        if current ~= value then
            per[prop] = current
            pcall(function() inst[prop] = value end)
        end
    end))
end

function PropertyLock:RestoreAll()
    for inst, props in pairs(self.Originals) do
        for prop, v in pairs(props) do
            pcall(function() inst[prop] = v end)
        end
    end
    table.clear(self.Originals)
end

DefineFeature({
    Id = "World_NoFog",
    Toggle = "World_NoFog",
    Enable = function(self)
        local lock = PropertyLock.new(self.Maid)
        self.Lock = lock

        local function killAtmosphere(a)
            lock:Lock(a, "Density", 0)
            lock:Lock(a, "Haze", 0)
            lock:Lock(a, "Glare", 0)
            lock:Lock(a, "Offset", 0)
        end

        lock:Lock(Lighting, "FogStart", 0)
        lock:Lock(Lighting, "FogEnd", 100000)
        for _, d in ipairs(Lighting:GetDescendants()) do
            if d:IsA("Atmosphere") then killAtmosphere(d) end
        end
        self.Maid:Give(Lighting.DescendantAdded:Connect(function(d)
            if d:IsA("Atmosphere") then task.defer(killAtmosphere, d) end
        end))
    end,
    Disable = function(self)
        if self.Lock then self.Lock:RestoreAll() end
        self.Lock = nil
    end,
})

local function IsBlur(inst)
    if inst == ESPUI.OwnBlur then return false end -- [v81] свой Blur effect не прячем
    return inst:IsA("BlurEffect")
        or (inst:IsA("PostEffect") and string.find(string.lower(inst.Name), "blur", 1, true) ~= nil)
end

DefineFeature({
    Id = "World_NoBlur",
    Toggle = "World_NoBlur",
    Store = Stash.new(),
    Enable = function(self)
        local function watch(container)
            if not container then return end
            for _, c in ipairs(container:GetChildren()) do
                if IsBlur(c) then self.Store:Hide(c) end
            end
            self.Maid:Give(container.ChildAdded:Connect(function(c)
                if IsBlur(c) then task.defer(self.Store.Hide, self.Store, c) end
            end))
        end
        watch(Lighting)
        watch(workspace.CurrentCamera)
    end,
    Disable = function(self)
        self.Store:RestoreAll()
    end,
})

DefineFeature({
    Id = "World_NoShadows",
    Toggle = "World_NoShadows",
    Enable = function(self)
        self.Lock = PropertyLock.new(self.Maid)
        self.Lock:Lock(Lighting, "GlobalShadows", false)
    end,
    Disable = function(self)
        if self.Lock then self.Lock:RestoreAll() end
        self.Lock = nil
    end,
})

local function IsRain(inst)
    return string.lower(inst.Name) == "rain"
end

DefineFeature({
    Id = "World_NoRain",
    Toggle = "World_NoRain",
    Store = Stash.new(),
    Update = function(self)
        for inst in pairs(MapIndex.Sets.Rain) do
            if inst.Parent then self.Store:Hide(inst) end
        end
        for _, c in ipairs(workspace:GetChildren()) do
            if IsRain(c) then self.Store:Hide(c) end
        end
        local cam = workspace.CurrentCamera
        if cam then
            for _, c in ipairs(cam:GetChildren()) do
                if IsRain(c) then self.Store:Hide(c) end
            end
        end
    end,
    Disable = function(self)
        self.Store:RestoreAll()
    end,
})

------------------------------------------------------------
-- НОВОЕ: AMBIENCE (как World > Ambience у NL CS2). Только клиент, только Lighting.
-- Профили: Global + текущая игра (аналог «Map Selection» у NL: в Roblox нет карт CS,
-- поэтому отдельный профиль - на плейс). Эффекты берутся из профиля игры, если он
-- добавлен, иначе из Global. Профили хранятся в <ScriptName>/ambience.json.
------------------------------------------------------------
local Ambience = { Edit = "Global", Loading = false, State = {} }
do
    local PLACE_KEY = "place:" .. tostring(game.PlaceId)
    local placeName = "This game"
    task.spawn(function()
        local ok, info = pcall(function()
            return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        end)
        if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
            placeName = info.Name
            if Ambience.List then Ambience.List:Refresh() end
        end
    end)

    -- id = { тип, значение по умолчанию }
    local DEF = {
        Amb_Night = { "bool", false },        Amb_NightColor = { "color", Color3.fromRGB(120, 125, 165) },
        Amb_NightMode = { "str", "Atmosphere" }, Amb_NightStrength = { "num", 50 }, -- [v67]
        Amb_Full = { "bool", false },         Amb_FullColor = { "color", Color3.fromRGB(205, 205, 205) },
        Amb_Sky = { "bool", false },          Amb_SkyTime = { "num", 0 },            Amb_SkyHide = { "bool", false },
        Amb_Sun = { "bool", false },          Amb_SunColor = { "color", Color3.fromRGB(255, 214, 170) }, Amb_SunBright = { "num", 2 },
        Amb_Fog = { "bool", false },          Amb_FogColor = { "color", Color3.fromRGB(205, 205, 205) },
        Amb_FogRadius = { "num", 0 },         Amb_FogGlow = { "num", 0 },            Amb_FogIntensity = { "num", 30 }, Amb_FogDensity = { "num", 35 },
        Amb_DoF = { "bool", false },          Amb_DoFFar = { "bool", true },         Amb_DoFNear = { "bool", false },  Amb_DoFIntensity = { "num", 50 },
        Amb_Rain = { "bool", false },         Amb_Snow = { "bool", false },          Amb_WeatherDensity = { "num", 50 },
        Amb_WeatherSize = { "num", 100 },     Amb_WeatherWind = { "num", 0 },
        -- [v75] свой скайбокс, цикл дня, экспозиция, цветокоррекция, bloom, лучи солнца, частицы в воздухе
        Amb_Skybox = { "bool", false },       Amb_SkyboxName = { "str", "Night" },   Amb_SkyboxSpin = { "num", 0 },
        Amb_SkyboxBodies = { "bool", false }, Amb_SkyboxClear = { "bool", true },    Amb_SkyCycle = { "num", 0 },
        Amb_Exposure = { "num", 0 },
        Amb_Grade = { "bool", false },        Amb_GradeTint = { "color", Color3.new(1, 1, 1) },
        Amb_GradeSat = { "num", 0 },          Amb_GradeContrast = { "num", 0 },      Amb_GradeBright = { "num", 0 },
        Amb_Bloom = { "bool", false },        Amb_BloomIntensity = { "num", 40 },    Amb_BloomSize = { "num", 24 },
        Amb_BloomThreshold = { "num", 90 },
        Amb_SunRays = { "bool", false },      Amb_SunRaysIntensity = { "num", 25 },
        Amb_Particles = { "str", "None" },    Amb_ParticlesColor = { "color", Color3.fromRGB(255, 190, 120) },
        Amb_ParticlesDensity = { "num", 50 },
    }
    local IDS = {}
    for id in pairs(DEF) do table.insert(IDS, id) end
    table.sort(IDS)
    Ambience.Ids = IDS

    local Profiles = { Global = {} }
    local FILE = CONFIG.ScriptName .. "/ambience.json"
    local function canFS() return writefile and readfile and isfile and true or false end
    pcall(function()
        if canFS() and isfile(FILE) then
            local data = HttpService:JSONDecode(readfile(FILE))
            if type(data) == "table" and type(data.Global) == "table" then Profiles = data end
        end
    end)
    local saveToken = 0
    local function saveSoon()
        saveToken += 1
        local my = saveToken
        task.delay(0.5, function()
            if my ~= saveToken or not canFS() then return end
            pcall(function()
                if isfolder and makefolder and not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
                writefile(FILE, HttpService:JSONEncode(Profiles))
            end)
        end)
    end

    local function encode(id, v)
        if DEF[id][1] == "color" and typeof(v) == "Color3" then return v:ToHex() end
        return v
    end
    local function decode(id, v)
        local kind, def = DEF[id][1], DEF[id][2]
        if v == nil then return def end
        if kind == "color" then
            local ok, c = pcall(Color3.fromHex, tostring(v))
            return ok and c or def
        end
        if kind == "bool" then return v == true end
        if kind == "str" then return type(v) == "string" and v or def end -- [v67]
        return tonumber(v) or def
    end
    local function active()
        return Profiles.Global -- [v75] выбора игры больше нет: один профиль на всё
    end

    -- [v75] скайбоксы: встроенные (SKYBOX_DATA) + свои из workspace/VisualsHub/skybox:
    --   skybox/<имя>/bk|dn|ft|lf|rt|up.png (или .jpg) - шесть граней; skybox/<имя>.png - одна картинка на все грани
    local SKY_DIR = CONFIG.ScriptName .. "/skybox"
    local SkyCache = {}
    local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }
    local function ensureSkyDir()
        pcall(function()
            if isfolder and makefolder then
                if not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
                if not isfolder(SKY_DIR) then makefolder(SKY_DIR) end
            end
        end)
    end
    function Ambience.SkyNames()
        local out = {}
        for _, n in ipairs(SKYBOX_ORDER or {}) do out[#out + 1] = n end
        if listfiles and isfolder then
            ensureSkyDir()
            local ok, files = pcall(listfiles, SKY_DIR)
            if ok and type(files) == "table" then
                local mine = {}
                for _, f in ipairs(files) do
                    local base = string.match(tostring(f), "([^/\\]+)$") or ""
                    local n = string.match(base, "^(.-)%.[pP][nN][gG]$") or string.match(base, "^(.-)%.[jJ][pP][eE]?[gG]$")
                    if not n and base ~= "_builtin" and isfolder(f) then n = base end
                    if n and n ~= "" and not table.find(out, n) and not table.find(mine, n) then mine[#mine + 1] = n end
                end
                table.sort(mine)
                for _, n in ipairs(mine) do out[#out + 1] = n end
            end
        end
        return out
    end
    function Ambience.SkyFaces(name)
        if SkyCache[name] ~= nil then return SkyCache[name] or nil end
        local load = getcustomasset or getsynasset
        local res = nil
        pcall(function()
            if not load then return end
            ensureSkyDir()
            local data = SKYBOX_DATA and SKYBOX_DATA[name]
            if data and writefile and Library.B64Decode then
                local dir = SKY_DIR .. "/_builtin"
                if isfolder and makefolder and not isfolder(dir) then makefolder(dir) end
                res = {}
                for _, f in ipairs(FACES) do
                    local path = dir .. "/" .. name .. "_" .. f .. ".png"
                    if not (isfile and isfile(path)) then writefile(path, Library.B64Decode(data[f])) end
                    res[f] = load(path)
                end
                return
            end
            local function find(base)
                for _, ext in ipairs({ ".png", ".jpg", ".jpeg", ".PNG", ".JPG" }) do
                    if isfile and isfile(base .. ext) then return base .. ext end
                end
                return nil
            end
            local single = find(SKY_DIR .. "/" .. name)
            if single then
                local id = load(single)
                res = {}
                for _, f in ipairs(FACES) do res[f] = id end
                return
            end
            local dir = SKY_DIR .. "/" .. name
            if isfolder and isfolder(dir) then
                local t = {}
                for _, f in ipairs(FACES) do
                    local file = find(dir .. "/" .. string.lower(f)) or find(dir .. "/" .. f)
                    if not file then return end
                    t[f] = load(file)
                end
                res = t
            end
        end)
        SkyCache[name] = res or false
        return res
    end
    function Ambience.ClearSkyCache() table.clear(SkyCache) end
    local function get(id) return decode(id, active()[id]) end

    -- снятие всех эффектов: сначала отключаем «сторожей» свойств, потом возвращаем оригиналы
    function Ambience.Clear()
        local st = Ambience.State
        Ambience.State = {}
        if st.Maid then st.Maid:Clean() end
        if st.Lock then st.Lock:RestoreAll() end
        if st.Stash then st.Stash:RestoreAll() end
    end

    function Ambience.Apply()
        Ambience.Clear()
        if Library.Unloaded then return end
        local maid = Maid.new()
        local lock = PropertyLock.new(maid)
        local stash = Stash.new()
        Ambience.State = { Maid = maid, Lock = lock, Stash = stash }
        local function new(class, props, parent)
            local inst = Instance.new(class)
            inst.Name = RandomName()
            for k, v in pairs(props) do pcall(function() inst[k] = v end) end
            maid:Give(inst)
            if parent then inst.Parent = parent end
            return inst
        end

        -- Nightmode: тёмный цветной фильтр поверх мира (цвет = оттенок, чем темнее - тем темнее ночь)
        -- [v67] режим: Atmosphere - фильтр на весь экран (как было), Props - красим только детали карты
        -- (игроки, ESP и небо не темнеют), Both - оба. Strength 50% = прежняя сила фильтра.
        local nightMode = get("Amb_NightMode")
        local nightK = get("Amb_NightStrength") / 100
        if get("Amb_Night") and nightMode ~= "Props" then
            new("ColorCorrectionEffect", { TintColor = Color3.new(1, 1, 1):Lerp(get("Amb_NightColor"), math.min(nightK * 2, 1)),
                Brightness = -0.08 * nightK, Contrast = 0.12 * nightK }, Lighting)
        end
        if get("Amb_Night") and nightMode ~= "Atmosphere" then
            local tint = get("Amb_NightColor")
            local saved = {} -- [inst] = { prop, исходное }
            local alive = true
            local function shade(c)
                local t = Color3.new(c.R * tint.R, c.G * tint.G, c.B * tint.B)
                t = t:Lerp(Color3.new(0, 0, 0), 0.5 * nightK)
                return c:Lerp(t, math.min(0.35 + nightK, 1))
            end
            local function paint(inst)
                if saved[inst] then return end
                local prop = (inst:IsA("BasePart") and "Color") or ((inst:IsA("Decal") or inst:IsA("Texture")) and "Color3")
                    or (inst:IsA("SurfaceAppearance") and "Color") or nil
                if not prop then return end
                local ok, cur = pcall(function() return inst[prop] end)
                if not ok or typeof(cur) ~= "Color3" then return end
                saved[inst] = { prop, cur }
                pcall(function() inst[prop] = shade(cur) end)
            end
            local map = MapIndex.Map or workspace:FindFirstChild("Map")
            if map then
                task.spawn(function()
                    local list = map:GetDescendants()
                    for i, d in ipairs(list) do
                        if not alive then return end
                        paint(d)
                        if i % 1500 == 0 then task.wait() end
                    end
                end)
                maid:Give(map.DescendantAdded:Connect(function(d) if alive then task.defer(paint, d) end end))
            end
            maid:Give(function()
                alive = false
                for inst, v in pairs(saved) do pcall(function() inst[v[1]] = v[2] end) end
                table.clear(saved)
            end)
        end
        -- Fullbright: равномерный свет (цвет = цвет подсветки теней)
        if get("Amb_Full") then
            local c = get("Amb_FullColor")
            lock:Lock(Lighting, "Ambient", c)
            lock:Lock(Lighting, "OutdoorAmbient", c)
            lock:Lock(Lighting, "Brightness", 2)
        end
        -- Override Sunlight: цвет солнечного света + яркость
        if get("Amb_Sun") then
            lock:Lock(Lighting, "ColorShift_Top", get("Amb_SunColor"))
            if not get("Amb_Full") then lock:Lock(Lighting, "Brightness", get("Amb_SunBright")) end
            if get("Amb_Exposure") ~= 0 then lock:Lock(Lighting, "ExposureCompensation", get("Amb_Exposure") / 10) end -- [v75]
        end
        -- [v75] цветокоррекция / bloom / лучи солнца: свои эффекты в Lighting (игровые не трогаем)
        if get("Amb_Grade") then
            new("ColorCorrectionEffect", { TintColor = get("Amb_GradeTint"), Saturation = get("Amb_GradeSat") / 100,
                Contrast = get("Amb_GradeContrast") / 100, Brightness = get("Amb_GradeBright") / 200 }, Lighting)
        end
        if get("Amb_Bloom") then
            new("BloomEffect", { Intensity = get("Amb_BloomIntensity") / 100 * 2, Size = get("Amb_BloomSize"),
                Threshold = get("Amb_BloomThreshold") / 100 * 2 }, Lighting)
        end
        if get("Amb_SunRays") then
            new("SunRaysEffect", { Intensity = get("Amb_SunRaysIntensity") / 100, Spread = 0.6 }, Lighting)
        end
        -- Override Sky: время суток (небо, солнце, звёзды) + стандартное небо Roblox вместо скайбокса игры
        -- [v75] свой скайбокс: прячем скайбоксы игры, ставим свой Sky (можно вращать); дымка Atmosphere скрывает небо -
        -- по умолчанию её Haze / Glare = 0, пока включён свой скайбокс
        local skyFaces = get("Amb_Skybox") and Ambience.SkyFaces(get("Amb_SkyboxName")) or nil
        if skyFaces then
            for _, c in ipairs(Lighting:GetChildren()) do
                if c:IsA("Sky") then stash:Hide(c) end
            end
            local props = { CelestialBodiesShown = get("Amb_SkyboxBodies"), StarCount = get("Amb_SkyboxBodies") and 3000 or 0 }
            for _, f in ipairs(FACES) do props["Skybox" .. f] = skyFaces[f] end
            local sky = new("Sky", props, Lighting)
            maid:Give(Lighting.ChildAdded:Connect(function(c)
                if c:IsA("Sky") and c ~= sky then task.defer(stash.Hide, stash, c) end
            end))
            local spin = get("Amb_SkyboxSpin")
            if spin ~= 0 then
                local ang = 0
                maid:Give(RunService.RenderStepped:Connect(function(dt)
                    ang = (ang + spin * dt) % 360
                    pcall(function() sky.SkyboxOrientation = Vector3.new(0, ang, 0) end)
                end))
            end
            if get("Amb_SkyboxClear") and not get("Amb_Fog") then
                local atm = Lighting:FindFirstChildOfClass("Atmosphere")
                if atm then
                    lock:Lock(atm, "Haze", 0)
                    lock:Lock(atm, "Glare", 0)
                end
            end
        end
        if get("Amb_Sky") then
            local cycle = get("Amb_SkyCycle") -- [v75] часы игры в минуту (0 = время стоит)
            if cycle > 0 then
                local t = get("Amb_SkyTime")
                maid:Give(RunService.Heartbeat:Connect(function(dt)
                    t = (t + cycle * dt / 60) % 24
                    pcall(function() Lighting.ClockTime = t end)
                end))
            else
                lock:Lock(Lighting, "ClockTime", get("Amb_SkyTime"))
            end
            if get("Amb_SkyHide") and not skyFaces then
                for _, c in ipairs(Lighting:GetChildren()) do
                    if c:IsA("Sky") then stash:Hide(c) end
                end
                maid:Give(Lighting.ChildAdded:Connect(function(c)
                    if c:IsA("Sky") then task.defer(stash.Hide, stash, c) end
                end))
            end
        end
        -- Override Fog: Atmosphere (в Roblox она главнее старого FogStart/FogEnd).
        -- Не работает одновременно с Environment > Delete Fog (они правят одни и те же свойства).
        if get("Amb_Fog") and not (Toggles.World_NoFog and Toggles.World_NoFog.Value) then
            local c = get("Amb_FogColor")
            local atm = Lighting:FindFirstChildOfClass("Atmosphere") or new("Atmosphere", {}, Lighting)
            lock:Lock(atm, "Color", c)
            lock:Lock(atm, "Decay", c)
            lock:Lock(atm, "Density", get("Amb_FogDensity") / 100)
            lock:Lock(atm, "Offset", get("Amb_FogRadius") / 100)
            lock:Lock(atm, "Haze", get("Amb_FogIntensity") / 10)
            lock:Lock(atm, "Glare", get("Amb_FogGlow") / 10)
            lock:Lock(Lighting, "FogColor", c)
        end
        -- Override DoF: размытие дальнего / ближнего плана
        if get("Amb_DoF") then
            local k = get("Amb_DoFIntensity") / 100
            new("DepthOfFieldEffect", {
                FarIntensity = get("Amb_DoFFar") and k or 0, NearIntensity = get("Amb_DoFNear") and k or 0,
                FocusDistance = 20, InFocusRadius = 20,
            }, Lighting)
        end
        -- Weather: дождь/снег частицами над камерой (стандартная текстура частиц Roblox).
        -- ФИКС: раньше капли были 0.07 студа и разворачивались по направлению полёта, поэтому
        -- выглядели мелкими плоскими чёрточками. Теперь частицы всегда смотрят в камеру и стоят
        -- вертикально, капли вытянуты, хлопья крупнее; Size и Wind настраиваются.
        local rain, snow = get("Amb_Rain"), get("Amb_Snow")
        local dust = get("Amb_Particles") -- [v75] Dust / Embers / Fireflies вокруг камеры
        if dust == "None" then dust = nil end
        if rain or snow or dust then
            local dens = get("Amb_WeatherDensity") / 100
            local sc = math.max(get("Amb_WeatherSize"), 10) / 100
            local wind = get("Amb_WeatherWind") / 100
            local function fade(alpha)
                return NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, alpha),
                    NumberSequenceKeypoint.new(0.85, alpha), NumberSequenceKeypoint.new(1, 1),
                })
            end
            local cam = workspace.CurrentCamera
            local part = new("Part", {
                Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
                Transparency = 1, Size = Vector3.new(70, 1, 70),
            }, cam or workspace)
            if rain then
                new("ParticleEmitter", {
                    Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = math.floor(200 + 1300 * dens),
                    Lifetime = NumberRange.new(1.4, 1.8), Speed = NumberRange.new(45, 55), EmissionDirection = Enum.NormalId.Bottom,
                    Size = NumberSequence.new(0.4 * sc), Squash = NumberSequence.new(2.5),
                    Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
                    Transparency = fade(0.3), Color = ColorSequence.new(Color3.fromRGB(200, 210, 225)), LightEmission = 0.15,
                    Acceleration = Vector3.new(25 * wind, 0, 0),
                }, part)
            end
            if snow then
                new("ParticleEmitter", {
                    Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = math.floor(60 + 540 * dens),
                    Lifetime = NumberRange.new(8, 10), Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Bottom,
                    SpreadAngle = Vector2.new(30, 30),
                    Size = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.4 * sc, 0.15 * sc), NumberSequenceKeypoint.new(1, 0.4 * sc, 0.15 * sc),
                    }),
                    Orientation = Enum.ParticleOrientation.FacingCamera,
                    Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
                    Transparency = fade(0.05), Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.4,
                    Acceleration = Vector3.new(6 * wind, 0, 2 * wind),
                }, part)
            end
            if dust then
                local pd = get("Amb_ParticlesDensity") / 100
                local P = ({
                    Dust = { Rate = 20 + 120 * pd, Life = NumberRange.new(6, 10), Speed = NumberRange.new(0.2, 0.8), Size = 0.12, Light = 0.1, Acc = Vector3.new(0.3, -0.1, 0.2), Alpha = 0.45 },
                    Embers = { Rate = 10 + 70 * pd, Life = NumberRange.new(3, 6), Speed = NumberRange.new(1, 3), Size = 0.15, Light = 1, Acc = Vector3.new(0.5, 1.6, 0.3), Alpha = 0.1 },
                    Fireflies = { Rate = 4 + 30 * pd, Life = NumberRange.new(4, 7), Speed = NumberRange.new(0.3, 1.2), Size = 0.22, Light = 1, Acc = Vector3.new(0, 0.2, 0), Alpha = 0.05 },
                    -- [v81] Sakura: падающие лепестки (своя картинка fx_petal, свои розовые цвета - Particles color не влияет)
                    Sakura = { Rate = 6 + 40 * pd, Life = NumberRange.new(6, 10), Speed = NumberRange.new(0.5, 1.5), Size = 0.35, Light = 0, Acc = Vector3.new(1.2, -1.2, 0.5), Alpha = 0.05,
                        Tex = Library:GetIcon("fx_petal"), Color = ColorSequence.new(Color3.fromRGB(255, 205, 220), Color3.fromRGB(255, 240, 245)), Rot = 120 },
                })[dust]
                if P then
                    local box = new("Part", {
                        Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
                        Transparency = 1, Size = Vector3.new(60, 30, 60),
                    }, cam or workspace)
                    new("ParticleEmitter", {
                        Texture = P.Tex or "rbxasset://textures/particles/sparkles_main.dds", Rate = math.floor(P.Rate), Lifetime = P.Life, -- [v81] P.Tex
                        Speed = P.Speed, SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Box,
                        ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Size = NumberSequence.new(P.Size * sc),
                        Transparency = fade(P.Alpha), Color = P.Color or ColorSequence.new(get("Amb_ParticlesColor")), LightEmission = P.Light, -- [v81] P.Color
                        LightInfluence = 0, Acceleration = P.Acc, RotSpeed = NumberRange.new(-(P.Rot or 30), P.Rot or 30), -- [v81] P.Rot
                        Rotation = NumberRange.new(0, 360),
                    }, box)
                    maid:Give(RunService.RenderStepped:Connect(function()
                        local c = workspace.CurrentCamera
                        if c then box.CFrame = CFrame.new(c.CFrame.Position) end
                    end))
                end
            end
            maid:Give(RunService.RenderStepped:Connect(function()
                local c = workspace.CurrentCamera
                if c then
                    if part.Parent ~= c then pcall(function() part.Parent = c end) end
                    part.CFrame = CFrame.new(c.CFrame.Position + Vector3.new(0, 20, 0))
                end
            end))
        end
    end

    -- профили <-> элементы UI
    -- ФИКС ловушки профилей: подсказка, какой профиль правишь и какой реально работает
    function Ambience.UpdateHint()
        if not Ambience.Hint then return end
        local text
        if Ambience.Edit == "Global" and Profiles[PLACE_KEY] then
            text = "Editing Global. This game has its own profile, so these changes do not show here."
        elseif Ambience.Edit == PLACE_KEY then
            text = "Editing this game's profile (active now)."
        else
            text = "Editing Global (active now). Add this game to give it its own settings."
        end
        Ambience.Hint:SetText(text)
    end
    function Ambience.LoadIntoUI(name)
        Ambience.Edit = Profiles[name] and name or "Global"
        local p = Profiles[Ambience.Edit]
        Ambience.Loading = true
        for _, id in ipairs(IDS) do
            local v = decode(id, p[id])
            local el = Toggles[id] or Options[id]
            if el then
                pcall(function()
                    if DEF[id][1] == "color" then el:SetValueRGB(v) else el:SetValue(v) end
                end)
            end
        end
        Ambience.Loading = false
        Ambience.Apply()
        Ambience.UpdateHint()
    end
    function Ambience.OnElementChanged(id)
        if Ambience.Loading then return end
        local el = Toggles[id] or Options[id]
        if not el then return end
        Profiles[Ambience.Edit][id] = encode(id, el.Value)
        saveSoon()
        Ambience.Apply()
    end
    function Ambience.Items()
        return {
            { Name = "Global", Text = "Global", Added = true, Selected = Ambience.Edit == "Global" },
            { Name = PLACE_KEY, Text = placeName, Added = Profiles[PLACE_KEY] ~= nil, Selected = Ambience.Edit == PLACE_KEY },
        }
    end
    function Ambience.Add(name)
        if name ~= PLACE_KEY or Profiles[name] then return end
        Profiles[name] = table.clone(Profiles.Global) -- новый профиль начинается с копии Global
        saveSoon()
        Ambience.LoadIntoUI(name)
    end
    function Ambience.Menu(name)
        local acts = {
            { Text = "Reset", Func = function()
                Profiles[name] = {}
                saveSoon()
                Ambience.LoadIntoUI(name)
            end },
        }
        if name ~= "Global" then
            table.insert(acts, { Text = "Remove", Func = function()
                Profiles[name] = nil
                saveSoon()
                Ambience.LoadIntoUI("Global")
            end })
        end
        return acts
    end
    Ambience.InitialProfile = function() return Profiles[PLACE_KEY] and PLACE_KEY or "Global" end
end

-- UI Ambience (World > Environment). [v75] Отдельной панели и выбора игры нет: всё - в групбоксе Environment.
do
    local fx = ESPUI.EnvBox
    fx:AddCheckbox("Amb_Night", { Text = "Nightmode", Default = false, Tooltip = "Darker tinted world. Color = night tint." })
        :AddColorPicker("Amb_NightColor", { Default = Color3.fromRGB(120, 125, 165), Title = "Nightmode" })
        :AddSettings({ Title = "Nightmode", Build = function(g) -- [v67]
            g:AddDropdown("Amb_NightMode", { Text = "Apply to", Values = { "Atmosphere", "Props", "Both" }, Default = "Atmosphere",
                Tooltip = "Atmosphere: tint filter over the whole screen. Props: only the map parts get darker (players, ESP and sky stay bright). Both: both." })
            g:AddSlider("Amb_NightStrength", { Text = "Strength", Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    fx:AddCheckbox("Amb_Full", { Text = "Fullbright", Default = false, Tooltip = "Even lighting. Color = shadow light color." })
        :AddColorPicker("Amb_FullColor", { Default = Color3.fromRGB(205, 205, 205), Title = "Fullbright" })
    fx:AddCheckbox("Amb_Sky", { Text = "Override Sky", Default = false, Tooltip = "Time of day and sky" })
        :AddSettings({ Title = "Override Sky", Build = function(g)
            g:AddSlider("Amb_SkyTime", { Text = "Time of Day", Default = 0, Min = 0, Max = 24, Rounding = 1, Suffix = "h" })
            g:AddSlider("Amb_SkyCycle", { Text = "Day cycle", Default = 0, Min = 0, Max = 60, Rounding = 0, Suffix = " h/min", -- [v75]
                Tooltip = "Time runs by itself: game hours per real minute (0 = time stands still)." })
            g:AddCheckbox("Amb_SkyHide", { Text = "Roblox Sky", Default = false, Tooltip = "Standard Roblox sky instead of the game's skybox" })
        end })
    -- [v75] свой скайбокс: встроенные + свои картинки из workspace/VisualsHub/skybox
    fx:AddCheckbox("Amb_Skybox", { Text = "Custom skybox", Default = false,
        Tooltip = "Your own sky (only you see it). Own pictures: workspace/" .. CONFIG.ScriptName .. "/skybox/<name>.png (one picture for all sides) or skybox/<name>/ with bk, dn, ft, lf, rt, up .png" })
        :AddSettings({ Title = "Custom skybox", Build = function(g)
            g:AddSlider("Amb_SkyboxSpin", { Text = "Rotation speed", Default = 0, Min = -20, Max = 20, Rounding = 1, Suffix = " deg/s" })
            g:AddCheckbox("Amb_SkyboxBodies", { Text = "Sun, moon and stars", Default = false })
            g:AddCheckbox("Amb_SkyboxClear", { Text = "Remove sky haze", Default = true,
                Tooltip = "Atmosphere haze / glare hide the skybox; they are set to 0 while the custom skybox is on (not with Override Fog)." })
            g:AddButton({ Text = "Refresh list", Func = function()
                Ambience.ClearSkyCache()
                Options.Amb_SkyboxName:SetValues(Ambience.SkyNames())
                Ambience.Apply()
            end })
        end })
    fx:AddDropdown("Amb_SkyboxName", { Text = "Skybox", Values = Ambience.SkyNames(), Default = "Night" })
    fx:AddCheckbox("Amb_Sun", { Text = "Override Sunlight", Default = false })
        :AddColorPicker("Amb_SunColor", { Default = Color3.fromRGB(255, 214, 170), Title = "Sunlight" })
        :AddSettings({ Title = "Override Sunlight", Build = function(g)
            g:AddSlider("Amb_SunBright", { Text = "Brightness", Default = 2, Min = 0, Max = 6, Rounding = 1 })
            g:AddSlider("Amb_Exposure", { Text = "Exposure", Default = 0, Min = -30, Max = 30, Rounding = 0 }) -- [v75]
        end })
    fx:AddCheckbox("Amb_Fog", { Text = "Override Fog", Default = false, Tooltip = "Turns off Environment > Delete Fog" })
        :AddColorPicker("Amb_FogColor", { Default = Color3.fromRGB(205, 205, 205), Title = "Fog" })
        :AddSettings({ Title = "Override Fog", Build = function(g)
            g:AddSlider("Amb_FogRadius", { Text = "Radius", Default = 0, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_FogGlow", { Text = "Glow Radius", Default = 0, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_FogIntensity", { Text = "Intensity", Default = 30, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_FogDensity", { Text = "Density", Default = 35, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    fx:AddCheckbox("Amb_DoF", { Text = "Override DoF", Default = false })
        :AddSettings({ Title = "Override DoF", Build = function(g)
            g:AddCheckbox("Amb_DoFFar", { Text = "Far Blurry", Default = true })
            g:AddCheckbox("Amb_DoFNear", { Text = "Near Blurry", Default = false })
            g:AddSlider("Amb_DoFIntensity", { Text = "Intensity", Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    -- [v75] цветокоррекция, bloom, лучи
    fx:AddCheckbox("Amb_Grade", { Text = "Color grading", Default = false })
        :AddColorPicker("Amb_GradeTint", { Default = Color3.new(1, 1, 1), Title = "Tint" })
        :AddSettings({ Title = "Color grading", Build = function(g)
            g:AddSlider("Amb_GradeSat", { Text = "Saturation", Default = 0, Min = -100, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_GradeContrast", { Text = "Contrast", Default = 0, Min = -100, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_GradeBright", { Text = "Brightness", Default = 0, Min = -100, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    fx:AddCheckbox("Amb_Bloom", { Text = "Bloom", Default = false, Tooltip = "Glow around bright parts (neon, lights, sky)." })
        :AddSettings({ Title = "Bloom", Build = function(g)
            g:AddSlider("Amb_BloomIntensity", { Text = "Intensity", Default = 40, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
            g:AddSlider("Amb_BloomSize", { Text = "Size", Default = 24, Min = 0, Max = 56, Rounding = 0 })
            g:AddSlider("Amb_BloomThreshold", { Text = "Threshold", Default = 90, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    fx:AddCheckbox("Amb_SunRays", { Text = "Sun rays", Default = false })
        :AddSettings({ Title = "Sun rays", Build = function(g)
            g:AddSlider("Amb_SunRaysIntensity", { Text = "Intensity", Default = 25, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        end })
    fx:AddSubmenu("Weather", { Build = function(g)
        g:AddCheckbox("Amb_Rain", { Text = "Rain", Default = false })
        g:AddCheckbox("Amb_Snow", { Text = "Snow", Default = false })
        g:AddSlider("Amb_WeatherDensity", { Text = "Density", Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
        g:AddSlider("Amb_WeatherSize", { Text = "Size", Default = 100, Min = 25, Max = 300, Rounding = 0, Suffix = "%" })
        g:AddSlider("Amb_WeatherWind", { Text = "Wind", Default = 0, Min = -100, Max = 100, Rounding = 0, Suffix = "%" })
        g:AddDropdown("Amb_Particles", { Text = "Air particles", Values = { "None", "Dust", "Embers", "Fireflies", "Sakura" }, Default = "None" }) -- [v75] [v81] + Sakura
            :AddColorPicker("Amb_ParticlesColor", { Default = Color3.fromRGB(255, 190, 120), Title = "Particles" })
        g:AddSlider("Amb_ParticlesDensity", { Text = "Particles density", Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = "%" })
    end })

    -- [v75] Removals (дубль Delete Fog / No Blur / ...) убран: эти галочки и так в Environment

    -- Delete Fog и Override Fog правят одни и те же свойства: одновременно не работают.
    -- Callback срабатывает раньше самой фичи, поэтому наш туман снимается до её включения.
    if Toggles.World_NoFog then
        local prev = Toggles.World_NoFog.Callback
        Toggles.World_NoFog.Callback = function(v)
            if prev then pcall(prev, v) end
            Ambience.Apply()
        end
    end
    for _, id in ipairs(Ambience.Ids) do
        local el = Toggles[id] or Options[id]
        if el then
            el:OnChanged(function()
                if id == "Amb_Fog" and el.Value and not Ambience.Loading
                    and Toggles.World_NoFog and Toggles.World_NoFog.Value then
                    Toggles.World_NoFog:SetValue(false)
                end
                Ambience.OnElementChanged(id)
            end)
        end
    end

    -- профили живут в ambience.json, конфиги их не трогают
    local ignore = {}
    for _, id in ipairs(Ambience.Ids) do table.insert(ignore, id) end
    SaveManager:SetIgnoreIndexes(ignore)

    Library:OnUnload(function() Ambience.Clear() end)
    Ambience.LoadIntoUI("Global") -- [v75]
end

------------------------------------------------------------
-- НОВОЕ: SKINCHANGER (Visuals > Skinchanger). Только у тебя на экране: чужой аватар по нику
-- (аксессуары, одежда, цвета тела, лицо) + предметы по ID + пресеты с автоприменением.
-- По save.rbxmx: персонаж R6, костюм киллера - детали "Hat" (не Accessory), их не трогаем.
-- Слоёная 3D-одежда (куртки и т.п.) на R6 не надевается - пропускается.
------------------------------------------------------------
local Skin = { Look = nil, Extra = {}, Active = false, Applied = nil, Token = 0,
    Specials = { Korblox = false, Headless = false }, -- [v43] Add Korblox / Add Headless
    Removed = {}, -- [v43] имена аксессуаров, снятых с аутфита
}
do
    local FILE = CONFIG.ScriptName .. "/skins.json"
    local Store = { presets = {} }
    pcall(function()
        if readfile and isfile and isfile(FILE) then
            local d = HttpService:JSONDecode(readfile(FILE))
            if type(d) == "table" and type(d.presets) == "table" then Store = d end
        end
    end)
    local function save()
        pcall(function()
            if not writefile then return end
            if isfolder and makefolder and not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
            writefile(FILE, HttpService:JSONEncode(Store))
        end)
    end
    function Skin.PresetNames()
        local names = {}
        for n in pairs(Store.presets) do table.insert(names, n) end
        table.sort(names)
        return names
    end
    function Skin.GetPreset(n) return Store.presets[n] end
    function Skin.SavePreset(n, data) Store.presets[n] = data save() end
    function Skin.DeletePreset(n) Store.presets[n] = nil save() end

    local ACCESSORY = {
        Hat = true, HairAccessory = true, FaceAccessory = true, NeckAccessory = true, ShoulderAccessory = true,
        FrontAccessory = true, BackAccessory = true, WaistAccessory = true,
    }
    local function notify(text) pcall(function() Library:Notify({ Title = "Skinchanger", Description = text, Time = 4 }) end) end
    Skin.Notify = notify

    -- [v43] «пустой» образ: только предметы по ID / Korblox / Headless / снятие аксов.
    -- Свои вещи, одежду и цвета тела при этом НЕ трогаем (раньше Add Item снимал всё своё).
    function Skin.ItemsLook(name) return { User = name or "Items", Assets = {}, Colors = {}, ItemsOnly = true } end
    function Skin.HasEdits()
        return #Skin.Extra > 0 or Skin.Specials.Korblox or Skin.Specials.Headless or next(Skin.Removed) ~= nil
    end
    -- Korblox для R6: ассет «Korblox Deathspeaker Right Leg» (R6-версия внутри - CharacterMesh);
    -- если экзекутор не грузит ассеты - тот же CharacterMesh напрямую по MeshId/текстуре
    Skin.KORBLOX_ASSET, Skin.KORBLOX_MESH, Skin.KORBLOX_TEX = 139607718, 101851696, 101851254

    -- ассет из каталога: game:GetObjects (функция экзекьютора)
    local cache = {}
    local function loadAll(id)
        id = tonumber(id)
        if not id then return {} end
        if cache[id] == nil then
            local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
            cache[id] = (ok and type(objs) == "table" and #objs > 0) and objs or false
        end
        local out = {}
        for _, proto in ipairs(cache[id] or {}) do
            local ok, copy = pcall(function() return proto:Clone() end)
            if ok and copy then table.insert(out, copy) end
        end
        return out
    end
    local function loadAsset(id)
        local all = loadAll(id)
        for i = 2, #all do all[i]:Destroy() end
        return all[1]
    end
    -- НОВОЕ: части тела R6 (пакеты): тип ассета -> Enum.BodyPart
    local PART_UI = { Head = "Head", Torso = "Torso", ["Left Arm"] = "LeftArm", ["Right Arm"] = "RightArm",
        ["Left Leg"] = "LeftLeg", ["Right Leg"] = "RightLeg" }
    Skin.PartNames = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
    -- R6-вариант внутри ассета пакета: CharacterMesh / SpecialMesh (папка "R6" в приоритете)
    local function findIn(objs, class)
        local best
        for _, o in ipairs(objs) do
            local list = { o }
            for _, d in ipairs(o:GetDescendants()) do table.insert(list, d) end
            for _, d in ipairs(list) do
                if d:IsA(class) then
                    if d.Parent and d.Parent.Name == "R6" then return d end
                    best = best or d
                end
            end
        end
        return best
    end

    -- ник (или UserId) -> образ: список ассетов + цвета тела
    function Skin.Fetch(name)
        name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return nil, "Enter a username" end
        local uid = tonumber(name)
        if not uid then
            local ok, res = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
            if not ok or not res then return nil, "User not found: " .. name end
            uid = res
        end
        local ok, info = pcall(function() return Players:GetCharacterAppearanceInfoAsync(uid) end)
        if not ok or type(info) ~= "table" then return nil, "Could not load avatar" end
        local look = { User = name, UserId = uid, Assets = {}, Colors = {} }
        for _, a in ipairs(info.assets or {}) do
            local t = a.assetType and a.assetType.name
            if t then table.insert(look.Assets, { Id = a.id, Type = t, Name = a.name }) end
        end
        for k, v in pairs(info.bodyColors or {}) do look.Colors[k] = v end
        return look
    end

    function Skin.Thumb(uid)
        local ok, img = pcall(function()
            return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
        end)
        return ok and img or nil
    end

    -- снять скин: вернуть своё
    function Skin.Reset()
        Skin.Token += 1
        local st = Skin.Applied
        Skin.Applied = nil
        if not st then return end
        st.Maid:Clean()
        for inst, parent in pairs(st.Hidden) do
            if parent and parent.Parent then pcall(function() inst.Parent = parent end) end
        end
        if st.Face and st.Face.Decal.Parent then pcall(function() st.Face.Decal.Texture = st.Face.Old end) end
        for _, r in ipairs(st.Restore or {}) do pcall(function() r[1][r[2]] = r[3] end) end
    end

    -- приклеить аксессуар к персонажу по одноимённому Attachment (как делает Roblox)
    local function attach(char, acc, anchor)
        local handle = acc:FindFirstChild("Handle")
        if not handle then return false end
        for _, d in ipairs(handle:GetDescendants()) do
            if d:IsA("BasePart") then d.CanCollide, d.Massless, d.Anchored = false, true, false end
        end
        handle.CanCollide, handle.Massless, handle.Anchored = false, true, false
        pcall(function() handle.CanQuery, handle.CanTouch = false, false end)
        local accAtt = handle:FindFirstChildOfClass("Attachment")
        local charAtt
        if accAtt then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Attachment") and d.Name == accAtt.Name and not d:IsDescendantOf(acc) and d.Parent:IsA("BasePart") then
                    charAtt = d
                    break
                end
            end
        end
        acc.Parent = char
        if charAtt then
            -- сразу ставим на место (в превью детали закреплены и сварка не двигает их)
            pcall(function() handle.CFrame = charAtt.WorldCFrame * accAtt.CFrame:Inverse() end)
            local w = Instance.new("Weld")
            w.Name = "AccessoryWeld"
            w.Part0, w.Part1 = charAtt.Parent, handle
            w.C0, w.C1 = charAtt.CFrame, accAtt.CFrame
            w.Parent = handle
            if anchor then handle.Anchored = true end
            return true
        end
        -- старые шапки без Attachment: Roblox сажает их на голову
        local head = char:FindFirstChild("Head")
        if head then
            return (pcall(function()
                local w = Instance.new("Weld")
                w.Part0, w.Part1 = head, handle
                local hy = (head.Size and head.Size.Y or 1) / 2
                w.C0 = CFrame.new(0, hy, 0) * (acc.AttachmentPoint and acc.AttachmentPoint:Inverse() or CFrame.new())
                pcall(function() handle.CFrame = head.CFrame * w.C0 end)
                w.Parent = handle
                if anchor then handle.Anchored = true end
            end))
        end
        return false
    end

    -- одеть модель: прячет свои вещи, ставит цвета, грузит ассеты в фоне.
    -- st = { Maid, Hidden, Made, Preview }, alive() - этот вызов ещё актуален
    local function dress(char, look, extra, st, alive, onDone)
        local itemsOnly = look.ItemsOnly == true
        local optAcc = not itemsOnly and Toggles.Skin_Acc and Toggles.Skin_Acc.Value
        local optClothes = not itemsOnly and Toggles.Skin_Clothes and Toggles.Skin_Clothes.Value
        local optBody = not itemsOnly and Toggles.Skin_Body and Toggles.Skin_Body.Value
        local optFace = not itemsOnly and Toggles.Skin_Face and Toggles.Skin_Face.Value
        local keepAcc = Toggles.Skin_KeepAcc and Toggles.Skin_KeepAcc.Value
        local wantPart = {}
        local sel = Options.Skin_Parts and Options.Skin_Parts.Value or {}
        if not itemsOnly then
            for ui, t in pairs(PART_UI) do if sel[ui] then wantPart[t] = true end end
        end
        local specials = Skin.Specials
        local removed = Skin.Removed
        st.Opts = { Acc = optAcc, Clothes = optClothes, Body = optBody, Keep = keepAcc, Parts = wantPart }
        st.Restore = st.Restore or {}
        local function setProp(inst, prop, value)
            if not st.Preview then table.insert(st.Restore, { inst, prop, inst[prop] }) end
            pcall(function() inst[prop] = value end)
        end
        local function hide(inst)
            if st.Preview then pcall(function() inst:Destroy() end) return end -- у копии просто удаляем
            if st.Hidden[inst] == nil and inst.Parent then
                st.Hidden[inst] = inst.Parent
                pcall(function() inst.Parent = nil end)
            end
        end
        local function own(inst)
            st.Maid:Give(inst)
            table.insert(st.Made, inst)
        end
        st.Own = own

        -- свои вещи прячем сразу (костюм киллера - детали "Hat", не Accessory - остаётся)
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Accessory") and removed[c.Name] then hide(c) end -- [v43] снятые вручную
            if specials.Korblox and c:IsA("CharacterMesh") then
                local okK, bpK = pcall(function() return c.BodyPart.Name end)
                if okK and bpK == "RightLeg" then hide(c) end
            end
            if optAcc and not keepAcc and c:IsA("Accessory") then hide(c) end
            if optClothes and (c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic")) then hide(c) end
            if optBody and c:IsA("BodyColors") then hide(c) end
            -- части тела: свой пакет на выбранных частях снимаем (у цели может быть обычное тело)
            if c:IsA("CharacterMesh") then
                local okP, bp = pcall(function() return c.BodyPart.Name end)
                if okP and wantPart[bp] then hide(c) end
            end
        end
        -- голова: своя форма головы -> обычная (если у цели своя - она заменит ниже); headless снимается
        local head = char:FindFirstChild("Head")
        if wantPart.Head and head then
            local hm = head:FindFirstChildOfClass("SpecialMesh")
            local custom = hm and (hm.MeshType ~= Enum.MeshType.Head or (hm.MeshId and hm.MeshId ~= ""))
            if hm and custom then
                hide(hm)
                local m = Instance.new("SpecialMesh")
                m.MeshType = Enum.MeshType.Head
                m.Scale = Vector3.new(1.25, 1.25, 1.25)
                own(m)
                m.Parent = head
                st.HeadMesh = m
            end
            if (tonumber(head.Transparency) or 0) >= 1 then setProp(head, "Transparency", 0) end
        end
        if optBody then
            local bc = Instance.new("BodyColors")
            local map = {
                headColorId = "HeadColor3", torsoColorId = "TorsoColor3", leftArmColorId = "LeftArmColor3",
                rightArmColorId = "RightArmColor3", leftLegColorId = "LeftLegColor3", rightLegColorId = "RightLegColor3",
            }
            for k, prop in pairs(map) do
                local v = look.Colors and look.Colors[k]
                if v then pcall(function() bc[prop] = BrickColor.new(v).Color end) end
            end
            bc.Name = "Body Colors"
            own(bc)
            bc.Parent = char
        end
        -- [v43] Headless: голова и лицо прозрачные (шапки/волосы остаются)
        if specials.Headless then
            local hd = char:FindFirstChild("Head")
            if hd then
                setProp(hd, "Transparency", 1)
                for _, c in ipairs(hd:GetChildren()) do
                    if c:IsA("Decal") then setProp(c, "Transparency", 1) end
                end
            end
        end

        -- загрузка ассетов идёт с ожиданием, поэтому в отдельном потоке
        task.spawn(function()
            local count, failed = 0, 0
            local list = {}
            for _, a in ipairs(look.Assets or {}) do table.insert(list, a) end
            for _, id in ipairs(extra or {}) do table.insert(list, { Id = id, Type = "Extra" }) end
            for _, a in ipairs(list) do
                -- копия для превью попадает на экран чуть позже, поэтому для неё родителя не проверяем
                if not alive() or (not st.Preview and char.Parent == nil) then return end
                local t = a.Type
                local want = (t == "Extra") or (optAcc and ACCESSORY[t]) or (optClothes and (t == "Shirt" or t == "Pants" or t == "TShirt"))
                    or (optFace and t == "Face")
                if wantPart[t] then
                    -- пакет: R6-версия части тела (CharacterMesh) или форма головы (SpecialMesh)
                    want = false
                    local objs = loadAll(a.Id)
                    if not alive() then for _, o in ipairs(objs) do o:Destroy() end return end
                    if #objs == 0 then failed += 1 end
                    if t == "Head" then
                        local hd = char:FindFirstChild("Head")
                        local nm = string.lower(tostring(a.Name or ""))
                        if hd and string.find(nm, "headless", 1, true) then
                            -- headless: голова и лицо прозрачные
                            setProp(hd, "Transparency", 1)
                            local fc = hd:FindFirstChildOfClass("Decal")
                            if fc then setProp(fc, "Transparency", 1) end
                            count += 1
                        else
                            local sm = findIn(objs, "SpecialMesh")
                            if hd and sm then
                                for _, c in ipairs(hd:GetChildren()) do
                                    if c:IsA("SpecialMesh") and not table.find(st.Made, c) then hide(c) end
                                end
                                if st.HeadMesh then pcall(function() st.HeadMesh:Destroy() end) st.HeadMesh = nil end
                                local m = sm:Clone()
                                own(m)
                                m.Parent = hd
                                count += 1
                            end
                        end
                    else
                        local cm = findIn(objs, "CharacterMesh")
                        if cm then
                            local m = cm:Clone()
                            own(m)
                            m.Parent = char
                            count += 1
                        end
                    end
                    for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
                end
                if want then
                    local obj = loadAsset(a.Id)
                    if not alive() then if obj then obj:Destroy() end return end
                    if not obj then
                        failed += 1
                    elseif obj:IsA("Accessory") and removed[obj.Name] then
                        obj:Destroy() -- [v43] этот акс снят вручную
                    elseif obj:IsA("Accessory") then
                        if obj:FindFirstChildWhichIsA("WrapLayer", true) then
                            obj:Destroy() -- слоёная одежда: на R6 не работает
                        else
                            own(obj) -- сначала пометить своим, потом в персонажа (иначе сторож решит, что это игра)
                            if attach(char, obj, st.Preview) then count += 1 else obj:Destroy() end
                        end
                    elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
                        for _, c in ipairs(char:GetChildren()) do
                            if c.ClassName == obj.ClassName and not table.find(st.Made, c) then hide(c) end
                        end
                        own(obj)
                        obj.Parent = char
                        count += 1
                    elseif obj:IsA("Decal") then
                        local head = char:FindFirstChild("Head")
                        local face = head and head:FindFirstChildOfClass("Decal")
                        if face then
                            if not st.Face then st.Face = { Decal = face, Old = face.Texture } end
                            face.Texture = obj.Texture
                            count += 1
                        end
                        obj:Destroy()
                    else
                        obj:Destroy()
                    end
                end
            end
            -- [v43] Korblox: R6 CharacterMesh правой ноги
            if specials.Korblox and alive() then
                local objs = loadAll(Skin.KORBLOX_ASSET)
                local cm = findIn(objs, "CharacterMesh")
                local m
                if cm then
                    m = cm:Clone()
                else
                    m = Instance.new("CharacterMesh")
                    pcall(function()
                        m.BodyPart = Enum.BodyPart.RightLeg
                        m.MeshId = Skin.KORBLOX_MESH
                        m.OverlayTextureId = Skin.KORBLOX_TEX
                    end)
                end
                for _, o in ipairs(objs) do pcall(function() o:Destroy() end) end
                if alive() then
                    own(m)
                    m.Parent = char
                    count += 1
                else
                    m:Destroy()
                end
            end
            if alive() and onDone then onDone(count, failed) end
        end)
    end

    -- надеть образ (look) + предметы по ID (extra) на своего персонажа
    function Skin.Apply(look, extra)
        Skin.Reset()
        local char = LocalPlayer.Character
        if not char or not look then return end
        Skin.Token += 1
        local my = Skin.Token
        local maid = Maid.new()
        local st = { Maid = maid, Hidden = {}, Made = {} }
        Skin.Applied = st
        dress(char, look, extra, st, function() return Skin.Token == my end, function(count, failed)
            notify(string.format("%s: %d items on%s", tostring(look.User or "look"), count,
                failed > 0 and string.format(", %d not loaded (executor can't load assets?)", failed) or ""))
        end)
        local o = st.Opts

        -- вид от первого лица: наши аксессуары прозрачны так же, как голова
        maid:Give(RunService.RenderStepped:Connect(function()
            local head = char:FindFirstChild("Head")
            if not head then return end
            local m = head.LocalTransparencyModifier
            for _, inst in ipairs(st.Made) do
                if inst:IsA("Accessory") then
                    for _, d in ipairs(inst:GetDescendants()) do
                        if d:IsA("BasePart") then d.LocalTransparencyModifier = m end
                    end
                end
            end
        end))
        -- игра переодела персонажа (свои вещи вернулись) - надеваем скин заново
        local pending = false
        maid:Give(char.ChildAdded:Connect(function(c)
            if pending or table.find(st.Made, c) then return end
            if (o.Acc and not o.Keep and c:IsA("Accessory")) or (c:IsA("Accessory") and Skin.Removed[c.Name])
                or (o.Clothes and (c:IsA("Shirt") or c:IsA("Pants")))
                or (o.Body and c:IsA("BodyColors")) then
                pending = true
                task.delay(0.3, function() if Skin.Applied == st then Skin.Apply(look, extra) end end)
            end
        end))
        Skin.Active = true
    end

    -- 3D-превью: копия твоего персонажа (без скриптов, звуков, подсветок), одетая в образ
    -- тем же кодом, что и Apply - показывает ровно то, что наденется в игре
    Skin.PreviewToken = 0
    local CLEAN = { "LuaSourceContainer", "Sound", "AudioPlayer", "AudioEmitter", "AudioListener", "Light", "BillboardGui",
        "SurfaceGui", "Highlight", "SelectionBox", "ParticleEmitter", "Beam", "Trail", "ForceField", "Tool", "BodyMover", "Constraint" }
    function Skin.BuildPreview(look, extra)
        Skin.PreviewToken += 1
        local my = Skin.PreviewToken
        local char = LocalPlayer.Character
        if not char or not look then return nil end
        local ok, clone = pcall(function()
            local was = char.Archivable
            char.Archivable = true
            local c = char:Clone()
            char.Archivable = was
            return c
        end)
        if not ok or not clone then return nil end
        for _, d in ipairs(clone:GetDescendants()) do
            for _, cls in ipairs(CLEAN) do
                if d:IsA(cls) then pcall(function() d:Destroy() end) break end
            end
        end
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = true
                d.LocalTransparencyModifier = 0 -- в первом лице оригинал прозрачен, копия - нет
            elseif d:IsA("Humanoid") then
                pcall(function() d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
            end
        end
        pcall(ESPUI.FlatPose, clone) -- [v43] флат-поза, аксессуары цепляются уже к ней
        local st = { Maid = Maid.new(), Hidden = {}, Made = {}, Preview = true }
        dress(clone, look, extra, st, function() return Skin.PreviewToken == my end)
        return clone
    end

    -- после смерти/респавна: снова надеть (если включено автоприменение)
    GlobalMaid:Give(LocalPlayer.CharacterAdded:Connect(function()
        Skin.Applied = nil
        task.delay(1, function()
            if Library.Unloaded then return end
            if Toggles.Skin_Auto and Toggles.Skin_Auto.Value and Skin.AutoLook then
                Skin.Apply(Skin.AutoLook, Skin.AutoExtra)
            end
        end)
    end))
    Library:OnUnload(function() Skin.Reset() end)
end

-- UI вкладки Skinchanger
do
    local tab = Tabs.Skins
    local av = tab:AddLeftGroupbox("Avatar")
    av:AddInput("Skin_User", { Text = "Username", Placeholder = "nick or UserId", Default = "" })
    local preview = av:AddImage({ Height = 220, Placeholder = "Enter a username and press Load" })
    local status = av:AddLabel("Nothing loaded", true)
    av:AddButton({ Text = "Load", Func = function()
        local name = Options.Skin_User.Value
        status:SetText("Loading " .. tostring(name) .. "...")
        task.spawn(function()
            local look, err = Skin.Fetch(name)
            if not look then
                status:SetText(err)
                return
            end
            Skin.Look = look
            local acc, clothes, parts = 0, 0, 0
            for _, a in ipairs(look.Assets) do
                if a.Type == "Shirt" or a.Type == "Pants" or a.Type == "TShirt" then clothes += 1
                elseif string.find(a.Type, "Accessory") or a.Type == "Hat" then acc += 1
                elseif a.Type == "Head" or a.Type == "Torso" or string.find(a.Type, "Arm") or string.find(a.Type, "Leg") then parts += 1 end
            end
            status:SetText(string.format("%s: %d accessories, %d clothes, %d body parts", look.User, acc, clothes, parts))
            preview:SetImage(Skin.Thumb(look.UserId)) -- картинка - запасной вариант, если нет персонажа
            Skin.RefreshPreview()
        end)
    end })
    -- 3D-превью пересобирается при смене образа, галочек и предметов по ID
    function Skin.RefreshPreview()
        if not Skin.Look and not Skin.HasEdits() then return end
        local m = Skin.BuildPreview(Skin.Look or Skin.ItemsLook(), Skin.Extra)
        preview:SetModel(m)
    end
    av:AddCheckbox("Skin_Acc", { Text = "Accessories", Default = true })
    av:AddCheckbox("Skin_Clothes", { Text = "Clothes", Default = true })
    av:AddCheckbox("Skin_Body", { Text = "Body Colors", Default = true })
    av:AddCheckbox("Skin_Face", { Text = "Face", Default = true })
    av:AddDropdown("Skin_Parts", {
        Text = "Body Parts", Values = Skin.PartNames, Multi = true, Default = Skin.PartNames,
        Tooltip = "R6 packages: head shape (incl. headless), torso, arms, legs (incl. korblox)",
    })
    av:AddCheckbox("Skin_KeepAcc", { Text = "Keep My Accessories", Default = false, Tooltip = "Add the new accessories on top of yours" })
    for _, id in ipairs({ "Skin_Acc", "Skin_Clothes", "Skin_Body", "Skin_Face", "Skin_Parts", "Skin_KeepAcc" }) do
        local el = Toggles[id] or Options[id]
        el:OnChanged(function() Skin.RefreshPreview() end)
    end
    av:AddButton({ Text = "Apply", Func = function()
        if not Skin.Look then Skin.Notify("Load a username first") return end
        Skin.Apply(Skin.Look, Skin.Extra)
    end })
    av:AddButton({ Text = "Reset To My Avatar", Func = function() Skin.Reset() Skin.Notify("Back to your avatar") end })

    local items = tab:AddRightGroupbox("Items by ID")
    items:AddInput("Skin_ItemId", { Text = "Asset ID", Placeholder = "catalog id", Default = "" })
    local itemsLabel = items:AddLabel("Added: none", true)
    local function showItems()
        local parts = {}
        for _, id in ipairs(Skin.Extra) do parts[#parts + 1] = tostring(id) end
        if Skin.Specials.Korblox then parts[#parts + 1] = "Korblox" end
        if Skin.Specials.Headless then parts[#parts + 1] = "Headless" end
        itemsLabel:SetText(#parts > 0 and ("Added: " .. table.concat(parts, ", ")) or "Added: none")
    end
    -- [v43] надеть текущие правки: образ (если загружен) или только предметы поверх своего аватара
    local function applyEdits()
        Skin.RefreshPreview()
        if Skin.Look or Skin.HasEdits() then
            Skin.Apply(Skin.Look or Skin.ItemsLook(), Skin.Extra)
        else
            Skin.Reset()
        end
    end
    Skin.ApplyEdits = applyEdits
    items:AddButton({ Text = "Add Item", Func = function()
        local id = tonumber((tostring(Options.Skin_ItemId.Value):gsub("%D", "")))
        if not id then Skin.Notify("Enter a numeric asset ID") return end
        table.insert(Skin.Extra, id)
        showItems()
        applyEdits()
    end })
    -- [v43] Korblox / Headless
    items:AddButton({ Text = "Add Korblox", Func = function()
        Skin.Specials.Korblox = true
        showItems()
        applyEdits()
    end })
    items:AddButton({ Text = "Add Headless", Func = function()
        Skin.Specials.Headless = true
        showItems()
        applyEdits()
    end })
    items:AddButton({ Text = "Add Korblox + Headless", Func = function()
        Skin.Specials.Korblox, Skin.Specials.Headless = true, true
        showItems()
        applyEdits()
    end })
    items:AddButton({ Text = "Clear Items", Func = function()
        table.clear(Skin.Extra)
        Skin.Specials.Korblox, Skin.Specials.Headless = false, false
        showItems()
        applyEdits()
    end })

    -- [v43] снять аксессуары с аутфита (свои или из загруженного образа) - видно только тебе
    local rm = tab:AddRightGroupbox("Remove Accessories")
    local function wornNames()
        local names, seenN = {}, {}
        local char = LocalPlayer.Character
        for _, c in ipairs(char and char:GetChildren() or {}) do
            if c:IsA("Accessory") and not seenN[c.Name] then seenN[c.Name] = true names[#names + 1] = c.Name end
        end
        for n in pairs(Skin.Removed) do if not seenN[n] then seenN[n] = true names[#names + 1] = n end end
        table.sort(names)
        return names
    end
    local rmList = rm:AddDropdown("Skin_RemoveList", { Text = "Accessories", Values = wornNames(), Multi = true, Default = {} })
    local rmLabel = rm:AddLabel("Removed: none", true)
    local function showRemoved()
        local n = {}
        for k in pairs(Skin.Removed) do n[#n + 1] = k end
        table.sort(n)
        rmLabel:SetText(#n > 0 and ("Removed: " .. table.concat(n, ", ")) or "Removed: none")
    end
    rm:AddButton({ Text = "Refresh List", Func = function() rmList:SetValues(wornNames()) end })
    rm:AddButton({ Text = "Remove Selected", Func = function()
        local any = false
        for name, on in pairs(rmList.Value or {}) do
            if on then Skin.Removed[name] = true any = true end
        end
        if not any then Skin.Notify("Pick accessories in the list first") return end
        showRemoved()
        applyEdits()
        rmList:SetValues(wornNames())
    end })
    rm:AddButton({ Text = "Restore Removed", Func = function()
        table.clear(Skin.Removed)
        showRemoved()
        applyEdits()
        rmList:SetValues(wornNames())
    end })

    local pr = tab:AddRightGroupbox("Presets")
    pr:AddInput("Skin_PresetName", { Text = "Preset Name", Placeholder = "name", Default = "" })
    local list = pr:AddDropdown("Skin_Preset", { Text = "Preset", Values = Skin.PresetNames(), Default = nil })
    pr:AddButton({ Text = "Save Preset", Func = function()
        local n = tostring(Options.Skin_PresetName.Value)
        if n == "" then n = Skin.Look and Skin.Look.User or "" end
        if n == "" or not (Skin.Look or Skin.HasEdits()) then Skin.Notify("Load a look or add items first") return end
        local removedList = {}
        for k in pairs(Skin.Removed) do removedList[#removedList + 1] = k end
        Skin.SavePreset(n, { Look = Skin.Look, Extra = table.clone(Skin.Extra),
            Korblox = Skin.Specials.Korblox, Headless = Skin.Specials.Headless, Removed = removedList })
        list:SetValues(Skin.PresetNames())
        list:SetValue(n)
        Skin.Notify("Saved preset " .. n)
    end })
    pr:AddButton({ Text = "Load Preset", Func = function()
        local p = list.Value and Skin.GetPreset(list.Value)
        if not p then Skin.Notify("Pick a preset") return end
        Skin.Look = p.Look
        Skin.Extra = table.clone(p.Extra or {})
        Skin.Specials.Korblox, Skin.Specials.Headless = p.Korblox == true, p.Headless == true
        table.clear(Skin.Removed)
        for _, k in ipairs(p.Removed or {}) do Skin.Removed[k] = true end
        showItems()
        showRemoved()
        if p.Look then
            Options.Skin_User:SetValue(p.Look.User or "")
            status:SetText(tostring(p.Look.User) .. " (preset)")
            task.spawn(function() preview:SetImage(Skin.Thumb(p.Look.UserId)) end)
        end
        Skin.RefreshPreview()
        Skin.Apply(Skin.Look or Skin.ItemsLook(list.Value), Skin.Extra)
    end })
    pr:AddButton({ Text = "Delete Preset", Func = function()
        if not list.Value then return end
        Skin.DeletePreset(list.Value)
        list:SetValues(Skin.PresetNames())
        list:SetValue(nil)
    end })
    pr:AddCheckbox("Skin_Auto", { Text = "Auto Apply", Default = false, Tooltip = "Wear the selected preset after every respawn and on script start" })

    -- автоприменение: выбранный пресет
    local function syncAuto()
        local p = list.Value and Skin.GetPreset(list.Value)
        Skin.AutoLook = p and (p.Look or Skin.ItemsLook(list.Value)) or nil
        Skin.AutoExtra = p and p.Extra or nil
    end
    list:OnChanged(syncAuto)
    Toggles.Skin_Auto:OnChanged(function(v)
        syncAuto()
        if v and Skin.AutoLook and not Skin.Applied then Skin.Apply(Skin.AutoLook, Skin.AutoExtra) end
    end)
    syncAuto()
end

DefineFeature({
    Id = "FOV_",
    Toggle = "FOV_Enabled",
    Enable = function(self)
        local cam = workspace.CurrentCamera
        self.Cam = cam
        self.Original = cam and cam.FieldOfView or 70

        local bindName = RandomName()

        RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
            if Library.Unloaded then return end
            local c = workspace.CurrentCamera
            if not c then return end
            if c ~= self.Cam then
                self.Cam = c
                self.Original = c.FieldOfView
            end
            c.FieldOfView = Options.FOV_Value.Value
        end)
        self.Maid:Give(function() RunService:UnbindFromRenderStep(bindName) end)
    end,
    Disable = function(self)
        if self.Cam and self.Cam.Parent and self.Original then
            self.Cam.FieldOfView = self.Original
        end
        self.Cam, self.Original = nil, nil
    end,
})

-- CROSSHAIR: крест / T / круг / точка, зазор, толщина, обводка. По умолчанию - прежний кружок.
DefineFeature({
    Id = "Crosshair_",
    Toggle = "Crosshair_Enabled",
    Watch = {
        "Crosshair_Size", "Crosshair_Color", "Crosshair_Cross", "Crosshair_TShape", "Crosshair_Circle",
        "Crosshair_Dot", "Crosshair_Outline", "Crosshair_Gap", "Crosshair_Thickness", "Crosshair_Transparency",
    },
    Enable = function(self)
        self.Gui = self.Maid:Give(NewOverlayGui())
        self.Root = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self.Gui,
        })
        self.Circle = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = self.Root,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Circle })
        self.CircleOutline = New("UIStroke", { Color = Color3.new(0, 0, 0), Parent = self.Circle })
        self.CircleInner = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = self.Circle,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.CircleInner })
        self.CircleStroke = New("UIStroke", { Parent = self.CircleInner })
        self.Arms = {}
        for i = 1, 4 do
            local arm = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 3, Parent = self.Root })
            self.Arms[i] = { Frame = arm, Stroke = New("UIStroke", { Color = Color3.new(0, 0, 0), Parent = arm }) }
        end
        self.Dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BorderSizePixel = 0, ZIndex = 4, Parent = self.Root })
        self.DotStroke = New("UIStroke", { Color = Color3.new(0, 0, 0), Parent = self.Dot })
    end,
    Update = function(self)
        if not self.Circle then return end
        local color = Options.Crosshair_Color.Value
        local size = Options.Crosshair_Size.Value
        local gap = Options.Crosshair_Gap.Value
        local th = Options.Crosshair_Thickness.Value
        local tr = Options.Crosshair_Transparency.Value
        local outline = Toggles.Crosshair_Outline.Value
        local outlineTr = outline and math.min(tr + 0.2, 1) or 1

        -- круг (как раньше: радиус = Size)
        local circle = Toggles.Crosshair_Circle.Value
        SetIf(self.Circle, "Visible", circle)
        SetIf(self.Circle, "Size", UDim2.fromOffset(size * 2, size * 2))
        SetIf(self.CircleStroke, "Color", color)
        SetIf(self.CircleStroke, "Thickness", th)
        SetIf(self.CircleStroke, "Transparency", tr)
        SetIf(self.CircleOutline, "Thickness", th + 2)
        SetIf(self.CircleOutline, "Transparency", outlineTr)

        -- линии: право, низ, лево, верх (у T-Shape верхней нет)
        local cross = Toggles.Crosshair_Cross.Value or Toggles.Crosshair_TShape.Value
        local len = math.max(size, 1)
        local off = gap + len / 2
        local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
        for i, a in ipairs(self.Arms) do
            local d = dirs[i]
            local show = cross and not (i == 4 and Toggles.Crosshair_TShape.Value)
            SetIf(a.Frame, "Visible", show)
            SetIf(a.Frame, "Position", UDim2.fromOffset(d[1] * off, d[2] * off))
            SetIf(a.Frame, "Size", d[1] ~= 0 and UDim2.fromOffset(len, th) or UDim2.fromOffset(th, len))
            SetIf(a.Frame, "BackgroundColor3", color)
            SetIf(a.Frame, "BackgroundTransparency", tr)
            SetIf(a.Stroke, "Transparency", outlineTr)
        end

        local dot = Toggles.Crosshair_Dot.Value
        SetIf(self.Dot, "Visible", dot)
        SetIf(self.Dot, "Size", UDim2.fromOffset(th + 1, th + 1))
        SetIf(self.Dot, "BackgroundColor3", color)
        SetIf(self.Dot, "BackgroundTransparency", tr)
        SetIf(self.DotStroke, "Transparency", outlineTr)
    end,
    Disable = function(self)
        self.Gui, self.Root, self.Circle, self.CircleStroke, self.CircleOutline, self.CircleInner = nil, nil, nil, nil, nil, nil
        self.Arms, self.Dot, self.DotStroke, self.Scale = nil, nil, nil, nil -- [v80] + Scale
        self.Img, self.DotCorner = nil, nil -- [v81]
        if self.IconWas ~= nil then UserInputService.MouseIconEnabled = self.IconWas self.IconWas = nil end -- [v80]
    end,
    -- [v78] Only when aiming: видимость каждый кадр (атрибуты читаются дёшево, без задержки 0.1 с)
    Render = function(self)
        if not self.Root then return end
        local show = true
        if Toggles.Crosshair_OnlyAim.Value then
            local char = LocalPlayer.Character
            local spear = char ~= nil and char:GetAttribute("spearmode") == true
            show = spear or (char ~= nil and char:GetAttribute("Aiming") == true)
            if show and not spear and Toggles.Crosshair_AimTOF.Value then
                show = tostring(LocalPlayer:GetAttribute("EquippedItem")) == "Twist of Fate"
            end
        end
        SetIf(self.Root, "Visible", show)
        -- [v80] вращение / пульс / радуга / цвет меню / скрыть курсор игры
        local now = os.clock()
        local spin = Options.Crosshair_Spin.Value
        local rot0 = Options.Crosshair_StaticRot.Value -- [v81] постоянный угол
        SetIf(self.Root, "Rotation", (rot0 + (spin > 0 and now * spin or 0)) % 360)
        -- [v81] позиция: центр или курсор + смещение
        local ox, oy = Options.Crosshair_OffsetX.Value, Options.Crosshair_OffsetY.Value
        if Options.Crosshair_Position.Value == "Mouse" then
            local m = UserInputService:GetMouseLocation()
            self.Root.Position = UDim2.fromOffset(m.X + ox, m.Y + oy)
        else
            SetIf(self.Root, "Position", UDim2.new(0.5, ox, 0.5, oy))
        end
        if Toggles.Crosshair_Pulse.Value then
            self.Scale = self.Scale or New("UIScale", { Parent = self.Root })
            self.Scale.Scale = 1 + (Options.Crosshair_PulseAmp.Value / 100) * math.sin(now * Options.Crosshair_PulseSpeed.Value * 2 * math.pi)
        elseif self.Scale then
            SetIf(self.Scale, "Scale", 1)
        end
        -- [v81] форма точки
        if Options.Crosshair_DotShape.Value == "Circle" then
            self.DotCorner = self.DotCorner or New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Dot })
        elseif self.DotCorner then
            self.DotCorner:Destroy() self.DotCorner = nil
        end
        -- [v81] Dynamic movement: зазор растёт со скоростью персонажа
        if Toggles.Crosshair_Dynamic.Value then
            local root = GetRoot(LocalPlayer.Character)
            local v = root and root.AssemblyLinearVelocity or Vector3.zero
            local speed = Vector3.new(v.X, 0, v.Z).Magnitude
            local len = math.max(Options.Crosshair_Size.Value, 1)
            local off = Options.Crosshair_Gap.Value + math.clamp(speed / 16, 0, 2) * Options.Crosshair_Spread.Value + len / 2
            local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
            for i, a in ipairs(self.Arms) do a.Frame.Position = UDim2.fromOffset(dirs[i][1] * off, dirs[i][2] * off) end
        end
        -- [v81] картинка вместо линий / круга / точки
        if Toggles.Crosshair_Image.Value then
            if not self.Img then
                self.Img = New("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                    BackgroundTransparency = 1, ZIndex = 5, Parent = self.Root })
            end
            local id = tostring(Options.Crosshair_ImageId.Value or ""):match("%d+")
            SetIf(self.Img, "Image", id and ("rbxassetid://" .. id) or "")
            local sz = Options.Crosshair_ImageSize.Value
            SetIf(self.Img, "Size", UDim2.fromOffset(sz, sz))
            SetIf(self.Img, "ImageColor3", Options.Crosshair_ImageTint.Value)
            SetIf(self.Img, "ImageTransparency", 1 - Options.Crosshair_ImageOpacity.Value / 100)
            SetIf(self.Img, "Visible", true)
            SetIf(self.Circle, "Visible", false)
            for _, a in ipairs(self.Arms) do SetIf(a.Frame, "Visible", false) end
            SetIf(self.Dot, "Visible", false)
        elseif self.Img then
            SetIf(self.Img, "Visible", false)
        end
        local col = (Toggles.Crosshair_Rainbow.Value and Color3.fromHSV(now * Options.Crosshair_RainbowSpeed.Value / 100 % 1, 0.85, 1))
            or (Toggles.Crosshair_Accent.Value and Library.Scheme.AccentColor) or nil
        if col then
            SetIf(self.CircleStroke, "Color", col)
            for _, a in ipairs(self.Arms) do SetIf(a.Frame, "BackgroundColor3", col) end
            SetIf(self.Dot, "BackgroundColor3", col)
        end
        local hide = Toggles.Crosshair_HideCursor.Value and show and not Library.Toggled
        if hide then
            if self.IconWas == nil then self.IconWas = UserInputService.MouseIconEnabled end
            UserInputService.MouseIconEnabled = false
        elseif self.IconWas ~= nil then
            UserInputService.MouseIconEnabled = self.IconWas
            self.IconWas = nil
        end
    end,
})

------------------------------------------------------------
-- KILLER: Anti Blind / No Blind VFX
------------------------------------------------------------
local function FindBlind()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local slasher = pg and pg:FindFirstChild("Slasher")
    return slasher and slasher:FindFirstChild("Blind")
end

DefineFeature({
    Id = "AntiBlind_",
    Toggle = "AntiBlind_Enabled",
    Changed = {},

    Update = function(self)
        local blind = FindBlind()
        local scr = blind and blind:FindFirstChild("blinded")
        if scr and scr:IsA("LocalScript") and self.Changed[scr] == nil then
            local ok, original = pcall(function() return scr.Enabled end)
            if ok then
                self.Changed[scr] = original
                pcall(function() scr.Enabled = false end)
            end
        end
        for s in pairs(self.Changed) do
            if s.Parent then
                local ok, en = pcall(function() return s.Enabled end)
                if ok and en then pcall(function() s.Enabled = false end) end
            else
                self.Changed[s] = nil
            end
        end
    end,

    Disable = function(self)
        for s, original in pairs(self.Changed) do
            if s.Parent then pcall(function() s.Enabled = original end) end
        end
        table.clear(self.Changed)
    end,
})

DefineFeature({
    Id = "NoBlindVFX_",
    Toggle = "NoBlindVFX_Enabled",

    Enable = function(self)
        self.Lock = PropertyLock.new(self.Maid)
    end,

    Update = function(self)
        local blind = FindBlind()
        if not blind or not self.Lock then return end
        if blind:IsA("GuiObject") then
            self.Lock:Lock(blind, "Visible", false)
        elseif blind:IsA("ScreenGui") then
            self.Lock:Lock(blind, "Enabled", false)
        end
    end,

    Disable = function(self)
        if self.Lock then self.Lock:RestoreAll() end
        self.Lock = nil
    end,
})

------------------------------------------------------------
-- SURVIVOR: Auto SkillCheck
------------------------------------------------------------
local ASC = {
    TouchID = 8822,
    ActionPath = "Survivor-mob.Controls.action.check",
    -- зона попадания относительно Goal.Rotation
    ZoneStart = 102,
    ZoneEnd = 116,
    -- кадр длиннее этого = Roblox притормозили (альт-таб) -> смотрим положение стрелки с упреждением
    SlowFrame = 1 / 30,
    -- повторное нажатие, пока стрелка всё ещё в зоне
    RepressDelay = 0.02,
}

local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local function ASC_GetActionTarget()
    local current = LocalPlayer:FindFirstChild("PlayerGui")
    for segment in string.gmatch(ASC.ActionPath, "[^%.]+") do
        current = current and current:FindFirstChild(segment)
    end
    return current
end


-- виден ли объект с учётом всех предков (Visible у родителей + ScreenGui.Enabled)
local function GuiShown(obj)
    local o = obj
    while o and o ~= game do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("LayerCollector") then return o.Enabled end
        o = o.Parent
    end
    return true
end

-- [FIX] GUI скилчека. Раньше брался ПЕРВЫЙ найденный SkillCheckPromptGui. В PlayerGui их бывает
-- несколько (SkillCheckPromptGui + SkillCheckPromptGui-con, плюс копии, оставшиеся с прошлых раундов).
-- Если первым оказывался неактивный - скиллчеки "не работали на этом сервере".
-- Теперь перебираем все SkillCheckPromptGui* и берём тот, у которого Check реально на экране.
local function ASC_FindCheck()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local firstPrompt, firstCheck
    for _, gui in ipairs(pg:GetChildren()) do
        if string.sub(gui.Name, 1, 19) == "SkillCheckPromptGui" then
            local check = gui:FindFirstChild("Check") or gui:FindFirstChild("Check", true)
            if check and GuiShown(check) then return gui, check end
            if not firstPrompt then firstPrompt, firstCheck = gui, check end
        end
    end
    if firstPrompt then return firstPrompt, firstCheck end
    -- запасной путь как раньше (GUI вложен глубже)
    local prompt = pg:FindFirstChild("SkillCheckPromptGui", true)
    if not prompt then return nil end
    return prompt, prompt:FindFirstChild("Check") or prompt:FindFirstChild("Check", true)
end

-- Альт-таб: глушим обработчики WindowFocusReleased и сообщаем игре, что окно в фокусе.
-- Возвращает функцию отката (она отдаётся в Maid фичи).
local function SpoofWindowFocus()
    local disabled = {}
    if getconnections then
        pcall(function()
            for _, c in ipairs(getconnections(UserInputService.WindowFocusReleased)) do
                if pcall(function() c:Disable() end) then table.insert(disabled, c) end
            end
        end)
    end
    if firesignal then pcall(firesignal, UserInputService.WindowFocused) end
    return function()
        for _, c in ipairs(disabled) do pcall(function() c:Enable() end) end
    end
end

-- Нажатие: тач по мобильной кнопке, только если она реально видна, иначе Space
local function ASC_Press()
    task.spawn(function()
        local b = ASC_GetActionTarget()
        if b and b:IsA("GuiObject") and GuiShown(b) then
            local p, s, i = b.AbsolutePosition, b.AbsoluteSize, GuiService:GetGuiInset()
            local cx, cy = p.X + (s.X / 2) + i.X, p.Y + (s.Y / 2) + i.Y
            pcall(function()
                VirtualInputManager:SendTouchEvent(ASC.TouchID, 0, cx, cy)
                task.wait(0.002)
                VirtualInputManager:SendTouchEvent(ASC.TouchID, 2, cx, cy)
            end)
        else
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.002)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
        end
    end)
end

DefineFeature({
    Id = "AutoSkillCheck_",
    Toggle = "AutoSkillCheck_Enabled",
    Busy = false,
    LastRot = nil,
    LastClock = nil,

    Enable = function(self)
        self.Maid:Give(SpoofWindowFocus())
        self.Maid:Give(RunService.Heartbeat:Connect(function()
            SafeRun(self, "Tick")
        end))
    end,

    Tick = function(self)
        local team = LocalPlayer.Team
        local teamName = team and string.lower(team.Name) or ""
        if not string.find(teamName, "survivor", 1, true) then
            self.Busy, self.LastRot, self.LastClock, self.Plan = false, nil, nil, nil
            return
        end

        local _, check = ASC_FindCheck()
        if not check or not GuiShown(check) then
            self.Busy, self.LastRot, self.LastClock, self.Plan = false, nil, nil, nil
            return
        end

        local line = check:FindFirstChild("Line") or check:FindFirstChild("Line", true)
        local goal = check:FindFirstChild("Goal") or check:FindFirstChild("Goal", true)
        -- [FIX] Капкан: в SkillCheckPromptGui.Check есть отдельная зона TrapGoal (скриншот Explorer),
        -- а Line общий (отдельного TrapLine в поиске "Trap" нет). Раньше зона всегда считалась от Goal,
        -- поэтому на капкане промахивалось. Берём TrapGoal только когда он на экране, а обычный Goal - нет:
        -- на генераторе (Goal виден) поведение не меняется.
        local trapGoal = check:FindFirstChild("TrapGoal") or check:FindFirstChild("TrapGoal", true)
        if trapGoal and GuiShown(trapGoal) and not (goal and GuiShown(goal)) then
            goal = trapGoal
        end
        if not line or not goal then return end

        local now = os.clock()
        local dt = self.LastClock and (now - self.LastClock) or 0
        self.LastClock = now

        local lr = line.Rotation % 360
        local gr = goal.Rotation % 360
        local ss = (gr + ASC.ZoneStart) % 360
        local se = (gr + ASC.ZoneEnd) % 360

        -- [NEW] режим Legit (Default ниже - без изменений)
        if Options.AutoSkillCheck_Mode and Options.AutoSkillCheck_Mode.Value == "Legit" then
            self:LegitTick(lr, gr, ss, dt)
            return
        end

        local function inZone(r)
            if ss > se then return r >= ss or r <= se end
            return r >= ss and r <= se
        end

        local hit = inZone(lr)

        -- В альт-табе кадры редкие: стрелка может перескочить узкую зону между двумя кадрами.
        -- Если кадр медленный, проверяем ещё и положение стрелки к следующему кадру.
        if not hit and self.LastRot and dt > ASC.SlowFrame then
            local delta = ((lr - self.LastRot + 540) % 360) - 180
            hit = inZone((lr + delta) % 360)
        end
        self.LastRot = lr

        if not hit then
            self.Busy = false
            return
        end
        if self.Busy then return end

        self.Busy = true
        ASC_Press()
        task.delay(ASC.RepressDelay, function()
            self.Busy = false
        end)
    end,

    -- [NEW] Legit: на каждый скиллчек один план и одно нажатие.
    --   Great (шанс из слайдера): жмём не на первом тике, а в случайной точке 30-80% белой зоны.
    --   Good: жмём в серой части после белой (ширина - слайдер "Good zone width").
    -- Новый скиллчек = Check снова появился или сменился поворот Goal.
    LegitTick = function(self, lr, gr, ss, dt)
        local great = (ASC.ZoneEnd - ASC.ZoneStart) % 360
        if not self.Plan or self.PlanGoal ~= gr then
            local r = math.random()
            if math.random() * 100 < Options.AutoSkillCheck_LegitGreat.Value then
                self.Plan = { Target = great * (0.3 + 0.5 * r), Last = great }
            else
                local good = Options.AutoSkillCheck_LegitGood.Value
                self.Plan = { Target = great + good * (0.25 + 0.5 * r), Last = great + good }
            end
            self.PlanGoal = gr
        end
        local plan = self.Plan

        -- угол стрелки относительно начала зоны (отрицательный = ещё не дошла)
        local function rel(rot)
            local x = (rot - ss) % 360
            if x > 300 then x -= 360 end
            return x
        end
        local cur = rel(lr)
        local hit = cur >= plan.Target and cur <= plan.Last
        -- медленный кадр (альт-таб): если к следующему кадру стрелка перескочит цель - жмём сейчас
        if not hit and self.LastRot and dt > ASC.SlowFrame then
            local delta = ((lr - self.LastRot + 540) % 360) - 180
            hit = cur < plan.Target and cur + delta >= plan.Target
        end
        self.LastRot = lr

        if hit and not plan.Done then
            plan.Done = true
            ASC_Press()
        end
    end,

    Disable = function(self)
        self.Busy, self.LastRot, self.LastClock, self.Plan = false, nil, nil, nil
    end,
})

------------------------------------------------------------
-- [NEW v7] SURVIVOR: Dodge
------------------------------------------------------------
-- Триггер доджа = анимация абилки на Animator киллера (она реплицируется всем клиентам),
-- окно доджа = пока этот трек играет. Так работают HUD Hidden/Butcher/Masked.
-- [v8] ID взяты из Animations Abysswalker (save.rbxmx luquinhasggs).
local DODGE_KNIGHT = {
    Killer = "abysswalker",   -- HudKey(MorphedKiller); по уведомлению игры: "<name> is Abysswalker"
    -- [CHANGED v10] было наоборот
    SlashAnims   = {          -- абилка 1 Slash: рывок 35 ст/с -> Ctrl зажат, пока трек играет
        ["100014992013740"] = true,
    },
    CorruptAnims = {          -- абилка 2 Corrupt: стоит, волна через 1с -> уход вбок с линии
        ["75613723058031"] = true,
    },
    CrouchKey = Enum.KeyCode.LeftControl,
}

-- [NEW v9] Волна Corrupt (Modules.Killers.Abysswalker.Visuals): сервер шлёт
-- Remotes.Killers.Abysswalker.visualize(CFrame, direction, speed, range); модуль запущен у всех
-- клиентов (KillerVisualsLoader), значит событие приходит и сурвайвору. Волна летит по прямой
-- со скоростью speed на range (по умолчанию speed * 3.5). Считаем, когда она дойдёт до нас.
-- [v37] Снаряды киллеров по точным данным сервера + общая наводка (мышью / маркер) для копья, цепи, фонарика.
--  * Cure: Remotes.Killers.Cure.VisualizeFlask("launch", { Points, StartedAt, Owner, Source, Sequence, Skin }) -
--    сервер шлёт ВЕСЬ путь колбы; она идёт по нему со скоростью FlaskTrajectory.TravelSpeed = 70 ст/с.
--  * Butcher: Remotes.Killers.Butcher.ChainState(owner, points, length, ..., phase, { Origin, Direction, LaunchTime })
--    в фазе "flying": цепь летит прямо от Origin со скоростью 140 до 50 стад (ChainProjectile: START_OFFSET 4, HIT_RADIUS 1).
local Projectiles = {
    Bound = false, Flasks = {}, Chains = {}, Spears = {},
    FLASK_SPEED = 70, CHAIN_SPEED = 140, CHAIN_RANGE = 50, CHAIN_START = 4, CHAIN_RADIUS = 1,
}

function Projectiles.Bind()
    if Projectiles.Bound then return end
    local now = os.clock()
    if now - (Projectiles.TriedAt or -10) < 2 then return end -- ремоуты могут появиться позже: пробуем раз в 2с
    Projectiles.TriedAt = now
    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local killers = remotes and remotes:FindFirstChild("Killers")
    if not killers then return end
    local B = Projectiles.Got or {}
    Projectiles.Got = B
    local cure = killers:FindFirstChild("Cure")
    local flaskEv = cure and cure:FindFirstChild("VisualizeFlask")
    if not B.Flask and flaskEv and flaskEv:IsA("RemoteEvent") then
        B.Flask = true
        GlobalMaid:Give(flaskEv.OnClientEvent:Connect(function(kind, d)
            if kind ~= "launch" or type(d) ~= "table" or type(d.Points) ~= "table" or #d.Points < 2 then return end
            local pts, dist = {}, { 0 }
            for i, p in ipairs(d.Points) do
                if typeof(p) ~= "Vector3" then return end
                pts[i] = p
                if i > 1 then dist[i] = dist[i - 1] + (p - pts[i - 1]).Magnitude end
            end
            table.insert(Projectiles.Flasks, {
                Points = pts, Dist = dist, Total = dist[#dist],
                StartedAt = tonumber(d.StartedAt) or workspace:GetServerTimeNow(),
                Source = d.Source,
            })
        end))
    end
    local butcher = killers:FindFirstChild("Butcher")
    local chainEv = butcher and butcher:FindFirstChild("ChainState")
    if not B.Chain and chainEv and chainEv:IsA("RemoteEvent") then
        B.Chain = true
        GlobalMaid:Give(chainEv.OnClientEvent:Connect(function(owner, points, length, a4, a5, latch, a7, phase, info)
            if typeof(owner) ~= "Instance" then return end
            local char = owner:IsA("Player") and owner.Character or owner
            if phase == "flying" and type(info) == "table" and typeof(info.Origin) == "Vector3" and typeof(info.Direction) == "Vector3"
                and info.Direction.Magnitude > 1e-3 then
                local dir = info.Direction.Unit
                local launch = tonumber(info.LaunchTime) or workspace:GetServerTimeNow()
                local c = Projectiles.Chains[char]
                if c and c.LaunchTime == launch then return end
                -- стена на пути (как castSkippingInvisible: прозрачное пропускаем, персонажей не считаем)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                local filter = { Containers.Root }
                for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(filter, plr.Character) end end
                local reach = Projectiles.CHAIN_RANGE
                for _ = 1, 8 do
                    rp.FilterDescendantsInstances = filter
                    local hit = workspace:Raycast(info.Origin, dir * Projectiles.CHAIN_RANGE, rp)
                    if not hit then break end
                    if hit.Instance.Transparency < 0.95 then reach = (hit.Position - info.Origin).Magnitude break end
                    table.insert(filter, hit.Instance)
                end
                Projectiles.Chains[char] = { Origin = info.Origin, Dir = dir, LaunchTime = launch, Reach = reach }
            else
                Projectiles.Chains[char] = nil -- зацепила / упала / тянется: полёт закончен
            end
        end))
    end
    local chainClear = butcher and butcher:FindFirstChild("ChainClear")
    if not B.Clear and chainClear and chainClear:IsA("RemoteEvent") then
        B.Clear = true
        GlobalMaid:Give(chainClear.OnClientEvent:Connect(function(owner)
            if typeof(owner) ~= "Instance" then return end
            Projectiles.Chains[owner:IsA("Player") and owner.Character or owner] = nil
        end))
    end
    -- Veil: Remotes.Killers.Veil.SpearState("launch", { Id, Source = персонаж, Origin, Direction, Speed, LaunchTime, Piercing })
    -- и ("stop", { Id, Impact, Reason }) - точный бросок с сервера (ProjectileVisualsClient)
    local veil = killers:FindFirstChild("Veil")
    local spearEv = veil and veil:FindFirstChild("SpearState")
    if not B.Spear and spearEv and spearEv:IsA("RemoteEvent") then
        B.Spear = true
        GlobalMaid:Give(spearEv.OnClientEvent:Connect(function(kind, d)
            if type(d) ~= "table" then return end
            if kind == "launch" and typeof(d.Source) == "Instance" and typeof(d.Origin) == "Vector3"
                and typeof(d.Direction) == "Vector3" and tonumber(d.Speed) and tonumber(d.LaunchTime) then
                Projectiles.Spears[d.Source] = { Id = d.Id, Origin = d.Origin, Vel = d.Direction * d.Speed,
                    LaunchTime = d.LaunchTime, Pierce = d.Piercing == true }
            elseif kind == "stop" then
                for src, sp in pairs(Projectiles.Spears) do
                    if sp.Id == d.Id then Projectiles.Spears[src] = nil end
                end
            end
        end))
    end
    Projectiles.Bound = B.Flask and B.Chain and B.Clear and B.Spear or false
end

-- колба: текущая точка и оставшийся путь { {Pos=...}, ... } (nil - уже упала)
-- [v56] предсказание колбы до броска: FlaskTrajectory.trace (ThrowSpeed 95, UpBias 0.35, 80 шагов по 0.04с,
-- гравитация 196.2) от позиции/направления камеры Cure. Камера - атрибуты CamPos / CamLook (KillerLookController
-- шлёт их серверу), иначе голова. Анимации: flaskcharge, flaskidle, flaskthrow (Animations.lua Cure).
Projectiles.FLASK_AIM_ANIMS = { ["121108316060822"] = true, ["79390410596403"] = true, ["99210996402874"] = true }
function Projectiles.FlaskPredict(e)
    local pos = ReadAttr(e.Model, e.Player, "CamPos")
    local look = ReadAttr(e.Model, e.Player, "CamLook")
    if typeof(pos) == "CFrame" then pos = pos.Position end
    if typeof(look) == "CFrame" then look = look.LookVector end
    local head = e.Model:FindFirstChild("Head")
    if typeof(pos) ~= "Vector3" then pos = (head and head:IsA("BasePart")) and head.Position or nil end
    if typeof(look) ~= "Vector3" or look.Magnitude < 1e-3 then look = (head and head:IsA("BasePart")) and head.CFrame.LookVector or nil end
    if not pos or not look then return nil end
    local v = (look.Unit + Vector3.new(0, 0.35, 0)).Unit * 95
    local g = Vector3.new(0, -196.2, 0)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local filter = { Containers.Root, e.Model }
    for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then filter[#filter + 1] = plr.Character end end
    rp.FilterDescendantsInstances = filter
    local pts, prev = { { Pos = pos } }, pos
    for i = 1, 80 do
        local t = i * 0.04
        local p = pos + v * t + g * (0.5 * t * t)
        -- как FlaskTrajectory.blocks: останавливают только непрозрачные детали (или с тегом TrueInvis)
        local hit
        for _ = 1, 8 do
            hit = workspace:Raycast(prev, p - prev, rp)
            if not hit then break end
            local inst = hit.Instance
            if inst.Transparency <= 0.01 or inst:HasTag("TrueInvis") then break end
            filter[#filter + 1] = inst
            rp.FilterDescendantsInstances = filter
            hit = nil
        end
        if hit then pts[#pts + 1] = { Pos = hit.Position } return pts end
        pts[#pts + 1] = { Pos = p }
        prev = p
    end
    return pts
end

function Projectiles.FlaskLeft(f, now)
    local d = (now - f.StartedAt) * Projectiles.FLASK_SPEED
    if d >= f.Total then return nil end
    local out = {}
    for i = 2, #f.Points do
        if d <= f.Dist[i] then
            local a = (d - f.Dist[i - 1]) / math.max(f.Dist[i] - f.Dist[i - 1], 1e-6)
            if #out == 0 then out[1] = { Pos = f.Points[i - 1]:Lerp(f.Points[i], math.max(a, 0)) } end
            out[#out + 1] = { Pos = f.Points[i] }
        end
    end
    return out
end

-- цепь: кончик сейчас и конец (nil - долетела)
function Projectiles.ChainNow(c, now)
    local travelled = math.min(Projectiles.CHAIN_START + (now - c.LaunchTime) * Projectiles.CHAIN_SPEED, c.Reach)
    if travelled >= c.Reach then return nil end
    return c.Origin + c.Dir * travelled, c.Origin + c.Dir * c.Reach
end

function Projectiles.Prune(now)
    for i = #Projectiles.Flasks, 1, -1 do
        local f = Projectiles.Flasks[i]
        if now - f.StartedAt > f.Total / Projectiles.FLASK_SPEED + 1 then table.remove(Projectiles.Flasks, i) end
    end
    for char, c in pairs(Projectiles.Chains) do
        if now - c.LaunchTime > c.Reach / Projectiles.CHAIN_SPEED + 1 then Projectiles.Chains[char] = nil end
    end
end

-- выживший ближе всего к прицелу в пределах FOV (полный угол), не сбит / не на крюке
function Projectiles.PickTarget(cam, fovDeg, maxDist, origin)
    local best, bestAng
    local look = cam.CFrame.LookVector
    for _, e in ipairs(Targets.AllSurvivors) do
        if e.Root and e.Root.Parent and not ReadAttr(e.Model, e.Player, "Knocked") and not ReadAttr(e.Model, e.Player, "IsHooked") then
            local to = e.Root.Position - cam.CFrame.Position
            if to.Magnitude > 1 and (not maxDist or (e.Root.Position - (origin or cam.CFrame.Position)).Magnitude <= maxDist) then
                local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
                if ang <= math.rad(fovDeg) / 2 and (not bestAng or ang < bestAng) then best, bestAng = e, ang end
            end
        end
    end
    return best
end

-- [v26] наводка «мышью» (mousemoverel): двигается сама камера игры, после броска ничего не прыгает.
-- Пиксели на радиан меряются на ходу; если мышь камеру не крутит - плавный поворот камеры напрямую.
-- st - таблица состояния (PxPerRad, NoResp, LastCmd).
function Projectiles.MouseAim(st, cam, dir, smooth)
    st.PxPerRad = st.PxPerRad or 600
    local look = cam.CFrame.LookVector
    local function yawOf(v) return math.atan2(-v.X, -v.Z) end
    local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
    local yaw, pitch = yawOf(look), math.asin(math.clamp(look.Y, -1, 1))
    local dYaw = wrap(yawOf(dir) - yaw)
    local dPitch = math.asin(math.clamp(dir.Y, -1, 1)) - pitch
    local f = 1 - smooth
    local mmr = mousemoverel or (Input and Input.MouseMove)
    if mmr and (st.NoResp or 0) < 10 then
        local last = st.LastCmd
        if last then
            local movedYaw, movedPitch = wrap(yaw - last.Yaw), pitch - last.Pitch
            if math.abs(last.X) >= 3 and math.abs(movedYaw) > 1e-4 then
                local k = -last.X / movedYaw
                if k > 30 and k < 30000 then st.PxPerRad = st.PxPerRad * 0.7 + k * 0.3 end
                st.NoResp = 0
            elseif math.abs(last.Y) >= 3 and math.abs(movedPitch) > 1e-4 then
                local k = -last.Y / movedPitch
                if k > 30 and k < 30000 then st.PxPerRad = st.PxPerRad * 0.7 + k * 0.3 end
                st.NoResp = 0
            elseif math.abs(last.X) + math.abs(last.Y) >= 3 then
                st.NoResp = (st.NoResp or 0) + 1
            end
        end
        local dx = math.floor(math.clamp(-dYaw * st.PxPerRad * f, -500, 500) + 0.5)
        local dy = math.floor(math.clamp(-dPitch * st.PxPerRad * f, -500, 500) + 0.5)
        st.LastCmd = { X = dx, Y = dy, Yaw = yaw, Pitch = pitch }
        if dx ~= 0 or dy ~= 0 then pcall(mmr, dx, dy) end
        return
    end
    local p = cam.CFrame.Position
    local want = look:Lerp(dir, math.max(f, 0.05))
    if want.Magnitude > 1e-3 then cam.CFrame = CFrame.lookAt(p, p + want.Unit) end
end

-- Legit: камера не трогается, на экране кружок - куда навести прицел (точка далеко по нужному направлению)
function Projectiles.Marker(st, cam, dir, color)
    if not st.MarkGui or not st.MarkGui.Parent then
        st.MarkGui = NewOverlayGui()
        local ring = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1,
            Visible = false, Parent = st.MarkGui })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
        st.MarkStroke = New("UIStroke", { Thickness = 2, Parent = ring })
        local dot = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4),
            BorderSizePixel = 0, Parent = ring })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = dot })
        st.MarkRing, st.MarkDot = ring, dot
    end
    if not dir then st.MarkRing.Visible = false return end
    local p = cam.CFrame.Position + dir * 300
    local sp, on = cam:WorldToViewportPoint(p)
    st.MarkRing.Visible = on and sp.Z > 0
    st.MarkRing.Position = UDim2.fromOffset(sp.X, sp.Y)
    st.MarkStroke.Color, st.MarkDot.BackgroundColor3 = color, color
end

function Projectiles.ClearMarker(st)
    if st.MarkGui then pcall(function() st.MarkGui:Destroy() end) end
    st.MarkGui, st.MarkRing, st.MarkDot, st.MarkStroke = nil, nil, nil, nil
end

local AbyssWaves = { Bound = false, List = {} }
local WAVE_TAIL = 0.3 -- сек: волна прошла через нас + запас -> угрозы больше нет

function AbyssWaves.Bind()
    if AbyssWaves.Bound then return end
    local r = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    r = r and r:FindFirstChild("Killers")
    r = r and r:FindFirstChild("Abysswalker")
    local ev = r and r:FindFirstChild("visualize")
    if not (ev and ev:IsA("RemoteEvent")) then return end
    AbyssWaves.Bound = true
    -- ширина волны - по модели ReplicatedStorage.Killers.Abysswalker.Wave
    local half = 4
    pcall(function()
        local wave = game:GetService("ReplicatedStorage").Killers.Abysswalker.Wave
        local size = wave:IsA("Model") and wave:GetExtentsSize() or wave.Size
        half = math.max(size.X, size.Z) / 2
    end)
    AbyssWaves.Half = half
    GlobalMaid:Give(ev.OnClientEvent:Connect(function(cf, direction, speed, range)
        if typeof(cf) ~= "CFrame" or typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then return end
        speed = tonumber(speed) or 0
        if speed <= 0 then return end
        table.insert(AbyssWaves.List, {
            Origin = cf.Position, Dir = direction.Unit, Speed = speed,
            Range = tonumber(range) or speed * 3.5, At = os.clock(),
        })
        -- [NEW v12] скорость/дальность волны до вылета неизвестны (их шлёт только сервер) -> запоминаем
        AbyssWaves.LastSpeed = speed
        AbyssWaves.LastRange = tonumber(range) or speed * 3.5
        AbyssWaves.LastAt = os.clock()
    end))
end

-- [NEW v13] Сами модели волн. Abysswalker.Visuals делает Wave:Clone() -> Parent = Workspace и каждый
-- Heartbeat Model:PivotTo(CFrame.new(pos, pos + dir)). Значит у живой модели есть ТЕКУЩАЯ позиция
-- и направление полёта (LookVector пивота) - не нужно ни угадывать, ни ждать remote.
AbyssWaves.Models = {}

local function WaveModelAdded(m)
    if m.Name == "Wave" and m:IsA("Model") then
        local ok, cf = pcall(m.GetPivot, m)
        table.insert(AbyssWaves.Models, { Model = m, At = os.clock(), Origin = ok and cf.Position or nil })
    end
end

function AbyssWaves.BindModels()
    if AbyssWaves.ModelsBound then return end
    AbyssWaves.ModelsBound = true
    GlobalMaid:Give(workspace.ChildAdded:Connect(WaveModelAdded))
    for _, c in ipairs(workspace:GetChildren()) do WaveModelAdded(c) end
    -- ширина волны (то же, что в Bind, если remote не найден)
    if not AbyssWaves.Half then
        pcall(function()
            local wave = game:GetService("ReplicatedStorage").Killers.Abysswalker.Wave
            local size = wave:IsA("Model") and wave:GetExtentsSize() or wave.Size
            AbyssWaves.Half = math.max(size.X, size.Z) / 2
        end)
    end
end

-- живые волны: { Model, Pos, Dir, Origin, Range }
function AbyssWaves.Live()
    local out = {}
    for i = #AbyssWaves.Models, 1, -1 do
        local w = AbyssWaves.Models[i]
        if not w.Model.Parent then
            table.remove(AbyssWaves.Models, i)
        else
            local ok, cf = pcall(w.Model.GetPivot, w.Model)
            if ok then
                local d = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
                if d.Magnitude > 1e-3 then
                    out[#out + 1] = {
                        Model = w.Model, Pos = cf.Position, Dir = d.Unit,
                        Origin = w.Origin or cf.Position, Range = AbyssWaves.LastRange or 60,
                    }
                end
            end
        end
    end
    return out
end

-- [CHANGED v10] направление ухода из коридора волны, которая ещё не прошла через нас (или nil)
function AbyssWaves.Escape(myPos, myHalf)
    local now = os.clock()
    local escape, escDir, escKey, escSide
    -- [NEW v13] сначала по реальным моделям волн (позиция/направление прямо сейчас)
    for _, w in ipairs(AbyssWaves.Live()) do
        local rel = myPos - w.Pos
        rel = Vector3.new(rel.X, 0, rel.Z)
        local along = rel:Dot(w.Dir)
        local side = rel - w.Dir * along
        local left = w.Range - ((w.Pos - w.Origin) * Vector3.new(1, 0, 1)).Magnitude
        if along >= -2 and along <= left + 2 and side.Magnitude <= (AbyssWaves.Half or 4) + myHalf + 1 then
            local right = Vector3.new(-w.Dir.Z, 0, w.Dir.X)
            escape = right * ((side:Dot(right) >= 0) and 1 or -1)
            escDir, escKey, escSide = w.Dir, w.Model or w, side -- [v43] для выбора стороны
        end
    end
    for i = #AbyssWaves.List, 1, -1 do
        local w = AbyssWaves.List[i]
        if now - w.At > w.Range / w.Speed + 1 then
            table.remove(AbyssWaves.List, i)
        else
            local rel = myPos - w.Origin
            local along = rel:Dot(w.Dir)
            local side = rel - w.Dir * along
            side = Vector3.new(side.X, 0, side.Z)
            local passed = now > w.At + along / w.Speed + WAVE_TAIL
            if not passed and along >= -2 and along <= w.Range + 2
                and side.Magnitude <= (AbyssWaves.Half or 4) + myHalf + 1 then
                -- уходим в ту сторону от оси волны, где уже стоим
                local flat = Vector3.new(w.Dir.X, 0, w.Dir.Z)
                if flat.Magnitude > 1e-3 then
                    local right = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
                    escape = right * ((side:Dot(right) >= 0) and 1 or -1)
                    escDir, escKey, escSide = flat.Unit, w, side
                end
            end
        end
    end
    return escape, escDir, escKey, escSide
end

-- [NEW v11] Тайминг Slash из Animations Abysswalker: старт анимации -> task.wait(0.8) рывка (35 ст/с)
-- -> fireBasicAttack (удар) -> task.wait(0.2). Значит удар = 0.8с от старта, окно удара ~0.2с.
local CROUCH_RETRY = 0.08 -- [NEW v18] сек между повторными нажатиями приседа, пока Crouching не стал true
local SLASH_HIT_AT  = 0.8
local SLASH_HIT_WIN = 0.2
local SLASH_TAIL    = 0.1  -- запас после окна удара
local SLASH_SPEED   = 35   -- humanoid.WalkSpeed во время рывка
local SLASH_REACH   = 7    -- запас на хитбокс удара (studs)

-- [NEW v12] Corrupt до вылета волны (windup).
-- Из Animations Abysswalker: анимация corrupt -> через CORRUPT_FIRE = 1с corrupt:FireServer("fire") -> волна.
-- Во время каста киллер Immobile и целится камерой; камеру повторяет голова (KillerLookController),
-- поэтому линию волны предсказываем от HRP по горизонтальному Head.LookVector (нет головы -> HRP).
-- Как сервер выбирает направление, в файлах нет - это допущение.
local CORRUPT_FIRE   = 1
-- [CHANGED v23] без настроек дальности/ширины: дальность волны шлёт сервер (visualize range, по умолчанию
-- speed * 3.5) - берём последнюю виденную; до первой волны - 60 (прежнее значение по умолчанию)
local CORRUPT_RANGE  = 60
local SLASH_FRONT_COS = math.cos(math.rad(35)) -- рывок Slash: цель перед рыцарем (прежние 35°)
local CORRUPT_MARGIN = 1.5 -- studs запаса к ширине коридора волны
local CORRUPT_WALL   = 3   -- studs: стена ближе этого в сторону ухода -> уходим в другую сторону

local function CorruptAim(e)
    local head = e.Model:FindFirstChild("Head")
    local lv = (head and head:IsA("BasePart")) and head.CFrame.LookVector or e.Root.CFrame.LookVector
    local f = Vector3.new(lv.X, 0, lv.Z)
    if f.Magnitude < 1e-3 then
        lv = e.Root.CFrame.LookVector
        f = Vector3.new(lv.X, 0, lv.Z)
    end
    return f.Magnitude > 1e-3 and f.Unit or nil
end

-- угроза от линии (origin, dir): возвращает (угрожает, боковой вектор от оси к нам, расстояние вдоль)
local function LaneThreat(origin, dir, range, myPos, width)
    local rel = myPos - origin
    rel = Vector3.new(rel.X, 0, rel.Z)
    local along = rel:Dot(dir)
    local side = rel - dir * along
    return along >= -2 and along <= range + 2 and side.Magnitude <= width, side, along
end

local function KillerTracks(e, ids)
    local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
        if id and ids[id] then return true end
    end
    return false
end

local function FlatUnit(v)
    local f = Vector3.new(v.X, 0, v.Z)
    return f.Magnitude > 1e-3 and f.Unit or nil
end

-- [NEW v14] Копьё Veil (Modules.Killers.Veil.SpearMath / SpearWorld, Animations Veil).
-- Бросок: origin = позиция камеры, направление = LookVector камеры (у чужого киллера - голова),
-- скорость = power(время заряда) = clamp(t * 180, 1, 180), позиция(t) = o + v*t + 0.5*g*t^2, g = -98.1.
-- Мир (SpearWorld.cast): персонажи, детали с прозрачностью >= 0.05 (без тега TrueInvis) и "Plant"
-- копьё пролетает; всё остальное (стены, крыши) - останавливает.
-- Попадание (SpearWorld.characterHit): отрезок пути против коробок частей тела (Head/Torso/руки/ноги).
-- Заряд = анимации startcharge/charge loop/startpower/power loop, выпуск = старт spearthrow1/2.
-- Нет в данных: ProjectileVisualsClient и поля события "launch" -> выпуск ловим по анимации броска.
-- [v82] SpearMath обновился (дамп пользователя, 01.11.2026): Speed 180 -> 165, MinimumChargeTime 0.3 -> 0.4,
-- новое MaxChargeTime = 7. Формулы те же: power(заряд) = clamp(заряд * Speed, 1, Speed), position = o + v*t + g*t²/2.
local SPEAR = {
    Speed = 165, Gravity = Vector3.new(0, -98.1, 0), SpawnOffset = 3,
    MinCharge = 0.4, MaxCharge = 7, MaxLife = 4, Step = 1 / 30,
}
-- [v82] значения берутся из модуля игры (Modules.Killers.Veil.SpearMath), если он доступен: следующая правка
-- игры подхватится сама. Числа выше - запасные.
task.spawn(function()
    local ok, M = pcall(function()
        local mod = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
        mod = mod and mod:FindFirstChild("Killers")
        mod = mod and mod:FindFirstChild("Veil")
        mod = mod and mod:FindFirstChild("SpearMath")
        return mod and mod:IsA("ModuleScript") and require(mod)
    end)
    if not ok or type(M) ~= "table" then return end
    local function num(v) return type(v) == "number" and v == v and math.abs(v) < math.huge end
    if num(M.Speed) and M.Speed > 0 then SPEAR.Speed = M.Speed end
    if typeof(M.Gravity) == "Vector3" then SPEAR.Gravity = M.Gravity end
    if num(M.SpawnOffset) then SPEAR.SpawnOffset = M.SpawnOffset end
    if num(M.MinimumChargeTime) then SPEAR.MinCharge = M.MinimumChargeTime end
    if num(M.MaxChargeTime) then SPEAR.MaxCharge = M.MaxChargeTime end
    if num(M.MaxLife) then SPEAR.MaxLife = M.MaxLife end
end)
local VEIL_CHARGE_SET = {
    ["77303734522729"] = true, ["87436543050891"] = true,   -- startcharge / charge loop
    ["79809716042968"] = true, ["122765810542358"] = true,  -- startpower / power loop
}
-- [NEW v19] усиленный заряд (Animations Veil: playPowerSpearChargeAnims -> startpower / power loop)
local VEIL_POWER_SET = { ["79809716042968"] = true, ["122765810542358"] = true }
local VEIL_THROW_SET = { ["101443662521580"] = true, ["127622545856523"] = true } -- spearthrow1/2
local SPEAR_BODY = { "Head", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local VeilSpear = setmetatable({}, { __mode = "k" })

-- [CHANGED v16] Направление камеры Veil берём из Neck.C0, а НЕ из мировой позы головы.
-- KillerLookController пишет взгляд камеры только в Neck.C0 = Angles(pitch, yaw, 0) * C0нейтр.
-- (и шлёт его на сервер -> реплицируется нам), а анимации (дыхание, заряд) идут через Neck.Transform.
-- Мировая поза головы = C0 * Transform -> раньше дыхание раскачивало траекторию, а обращение
-- наклона вниз (x / 0.075) усиливало эти колебания в ~13 раз.
--   pitch: вверх  x = 0.75 * угол камеры;  вниз  x = 0.075 * угол (pitchDownScale 0.1)
--   yaw:   y = 0.75 * Y3, Y3 = cos(pitch) * sin(угол камеры от HRP), y > 0 = влево
-- Сверху - сглаживание (VEIL_AIM_SMOOTH), чтобы мелкие колебания не дёргали путь.
local VEIL_NECK_NEUTRAL = CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0).Rotation -- стандартный R6 Neck.C0
local VEIL_AIM_SMOOTH = 0.12 -- сек

local function VeilRawAim(e)
    local head = e.Model:FindFirstChild("Head")
    local torso = e.Model:FindFirstChild("Torso")
    local neck = torso and torso:FindFirstChild("Neck")
    if not (head and head:IsA("BasePart")) then return nil end
    local rl = e.Root.CFrame.LookVector
    local rootFlat = Vector3.new(rl.X, 0, rl.Z)
    if rootFlat.Magnitude < 1e-3 then return nil end
    rootFlat = rootFlat.Unit

    local pitch, yaw = 0, 0
    local x, y = 0, 0
    if neck and neck:IsA("Motor6D") then
        x, y = (neck.C0.Rotation * VEIL_NECK_NEUTRAL:Inverse()):ToEulerAnglesXYZ()
    end
    if math.abs(x) < 1e-5 and math.abs(y) < 1e-5 then
        -- Neck.C0 в нейтрали (не реплицировался) -> запасной путь: взгляд головы как есть
        return head.Position, head.CFrame.LookVector
    end
    do
        pitch = x >= 0 and x / 0.75 or x / 0.075
        pitch = math.clamp(pitch, -math.rad(89), math.rad(89))
        local c = math.max(math.cos(pitch), 0.05)
        yaw = math.asin(math.clamp(y / 0.75 / c, -1, 1))
    end
    local flat = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(rootFlat)
    local look = (flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
    return head.Position, look
end

-- [NEW v17] Основной источник: атрибуты CamPos / CamLook персонажа (или игрока) - реальная позиция и
-- направление камеры Veil. Бросок в Animations идёт именно от camera.CFrame (Origin/Direction).
-- CamLook может быть Vector3 или CFrame (берём LookVector). Нет атрибутов -> запасной путь VeilRawAim.
local function VeilCamAim(e)
    local pos = ReadAttr(e.Model, e.Player, "CamPos")
    if typeof(pos) == "CFrame" then pos = pos.Position end
    if typeof(pos) ~= "Vector3" then return nil end
    -- [v69] как в NL v56 (Hidden): сначала CamDir, потом CamLook. Вектор длины ~1 - направление; длиннее -
    -- это ТОЧКА, куда смотрит камера -> направление = точка - CamPos. Раньше точку брали за направление
    -- (.Unit от мировой позиции) и дуга копья уходила не туда.
    for _, name in ipairs({ "CamDir", "CamLook" }) do
        local v = ReadAttr(e.Model, e.Player, name)
        if typeof(v) == "CFrame" then v = v.LookVector end
        if typeof(v) == "Vector3" and v.Magnitude > 1e-3 then
            if v.Magnitude > 1.5 then v = v - pos end
            if v.Magnitude > 1e-3 then return pos, v.Unit end
        end
    end
    return nil
end

local function VeilAim(e)
    local headPos, raw = VeilCamAim(e) -- [CHANGED v17] сначала CamPos/CamLook
    if not headPos then headPos, raw = VeilRawAim(e) end
    if not headPos then return nil end
    local st = VeilSpear[e.Model]
    if not st then
        st = {}
        VeilSpear[e.Model] = st
    end
    local now = os.clock()
    if st.AimLook and st.AimAt then
        local k = 1 - math.exp(-(now - st.AimAt) / VEIL_AIM_SMOOTH)
        st.AimLook = (st.AimLook:Lerp(raw, k)).Unit
    else
        st.AimLook = raw
    end
    st.AimAt = now
    return headPos + st.AimLook * SPEAR.SpawnOffset, st.AimLook
end

-- состояние копья киллера: заряд (ChargeStart) и летящее копьё (Flight)
local function VeilSpearTrack(e)
    local now = os.clock()
    local st = VeilSpear[e.Model]
    if not st then
        st = {}
        VeilSpear[e.Model] = st
    end
    local charging = KillerTracks(e, VEIL_CHARGE_SET)
    local throwing = KillerTracks(e, VEIL_THROW_SET)
    if charging and not st.ChargeStart then st.ChargeStart, st.PowerSeen = now, false end
    -- [NEW v19] усиленный заряд (абилка): анимации startpower/power loop или атрибут EmpoweredSpear
    if charging and (KillerTracks(e, VEIL_POWER_SET) or ReadAttr(e.Model, e.Player, "EmpoweredSpear") ~= nil) then
        st.PowerSeen = true
    end
    st.Empowered = charging and st.PowerSeen or false
    -- [v37] точный бросок с сервера (SpearState "launch") важнее предсказания по анимации; "stop" - копьё упало
    Projectiles.Bind()
    local exact = Projectiles.Spears[e.Model]
    if exact and workspace:GetServerTimeNow() - exact.LaunchTime > SPEAR.MaxLife then
        Projectiles.Spears[e.Model], exact = nil, nil
    end
    if exact and not (st.Flight and st.Flight.Id == exact.Id) then
        st.Flight = { Origin = exact.Origin, Vel = exact.Vel, Pierce = exact.Pierce, Exact = true, Id = exact.Id,
            At = now - math.max(workspace:GetServerTimeNow() - exact.LaunchTime, 0) }
    elseif not exact and st.Flight and st.Flight.Exact then
        st.Flight = nil
    end
    if throwing and not st.LastThrow and not (st.Flight and st.Flight.Exact) then
        local charge = st.ChargeStart and math.max(now - st.ChargeStart, SPEAR.MinCharge) or 1
        local o, d = VeilAim(e)
        if o then
            st.Flight = { Origin = o, Vel = d * math.clamp(charge * SPEAR.Speed, 1, SPEAR.Speed), At = now,
                Pierce = st.PowerSeen == true } -- [NEW v19] усиленное копьё пробивает карту
        end
        st.ChargeStart = nil
    end
    if not charging and not throwing then st.ChargeStart = nil end
    st.LastThrow = throwing
    if st.Flight and now - st.Flight.At > SPEAR.MaxLife then st.Flight = nil end
    return st
end

local SpearRay = RaycastParams.new()
SpearRay.FilterType = Enum.RaycastFilterType.Exclude

-- путь копья: точки {pos, t} до препятствия (правила SpearWorld.cast) или MaxLife
-- [CHANGED v19] pierce = усиленное копьё (абилка "Through the Veil"): летит сквозь стены/крыши,
-- путь не обрывается о мир, только по MaxLife (SpearMath.MaxLife = 4с)
local function VeilSpearPath(origin, vel, pierce)
    local filter = { Containers.Root }
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then filter[#filter + 1] = plr.Character end
    end
    for _, m in ipairs(CollectionService:GetTagged("SurvivorBot")) do filter[#filter + 1] = m end
    local cam = workspace.CurrentCamera
    if cam then filter[#filter + 1] = cam end
    local pts = { { Pos = origin, T = 0 } }
    local prev = origin
    local t = 0
    while t < SPEAR.MaxLife do
        t += SPEAR.Step
        local pos = origin + vel * t + SPEAR.Gravity * (0.5 * t * t)
        local from, dir = prev, pos - prev
        for _ = 1, (pierce and 0 or 32) do -- [v91] 32, как SpearWorld.cast (было 8)
            SpearRay.FilterDescendantsInstances = filter
            local hit = workspace:Raycast(from, dir, SpearRay)
            if not hit then break end
            local inst = hit.Instance
            -- [v91] как ignoreWorld в SpearWorld: всё внутри модели с Humanoid (клоны, фейки, превью, копьё в руке
            -- и т.п.) копьё пролетает. Без этого обычный бросок упирался в такую деталь у самой руки -> была видна
            -- только точка; с абилкой (pierce) лучи не пускаются, поэтому там путь был.
            local inHum = false
            if inst ~= workspace.Terrain then
                local x = inst.Parent
                while x and x ~= workspace do
                    if x:IsA("Model") and x:FindFirstChildOfClass("Humanoid") then inHum = true break end
                    x = x.Parent
                end
            end
            local pass = inHum or inst.Name == "Plant" or (inst.Transparency >= 0.05 and not inst:HasTag("TrueInvis"))
            if not pass then
                pts[#pts + 1] = { Pos = hit.Position, T = t }
                return pts, hit.Position, hit.Normal -- [v24] нормаль - для кольца места падения
            end
            filter[#filter + 1] = inst
        end
        pts[#pts + 1] = { Pos = pos, T = t }
        prev = pos
    end
    return pts, nil
end

-- пересечение отрезка с коробкой (slab test, как bodyIntersection в SpearWorld)
local function SegBox(a, d, cf, size)
    local o, v = cf:PointToObjectSpace(a), cf:VectorToObjectSpace(d)
    local t0, t1 = 0, 1
    for _, ax in ipairs({ "X", "Y", "Z" }) do
        local p, dv, h = o[ax], v[ax], size[ax] * 0.5
        if math.abs(dv) < 1e-8 then
            if p < -h or p > h then return nil end
        else
            local ta, tb = (-h - p) / dv, (h - p) / dv
            if ta > tb then ta, tb = tb, ta end
            t0, t1 = math.max(t0, ta), math.min(t1, tb)
            if t1 < t0 then return nil end
        end
    end
    return t0
end

-- попадёт ли путь в наш персонаж (части тела + запас)
local function SpearHitsMe(pts, char, margin)
    local grow = Vector3.new(margin, margin, margin) * 2
    for i = 1, #pts - 1 do
        local a, b = pts[i].Pos, pts[i + 1].Pos
        for _, name in ipairs(SPEAR_BODY) do
            local part = char:FindFirstChild(name)
            if part and part:IsA("BasePart") and SegBox(a, b - a, part.CFrame, part.Size + grow) then
                return true
            end
        end
    end
    return false
end

DefineFeature({
    Id = "DodgeKnight_",
    Gate = { "DodgeAbyss_Slash", "DodgeAbyss_Corrupt", "DodgeVeil_Spear", "DodgeCure_Flask", "DodgeButcher_Chain" }, -- [v37] + Cure, Butcher
    Crouching = false,

    -- [NEW v13] Уход вбок клавишами WASD через VirtualInputManager (тот же канал, что у Ctrl для приседа,
    -- который работает). Humanoid:Move перебивался управлением игры, поэтому уход не происходил.
    -- dir - в мире; клавиши выбираются относительно камеры (W/S - вперёд/назад, A/D - влево/вправо).
    Keys = {},
    Sides = {},
    -- [v43] мягче: жмём ОДНУ клавишу (ближайшую к направлению ухода), клавишу, которую игрок и так держит,
    -- не жмём и не отпускаем - остальное управление (W/S, мышь) остаётся за игроком.
    SetStrafe = function(self, dir)
        local want = {}
        if dir then
            local cam = workspace.CurrentCamera
            local lv = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
            local f = Vector3.new(lv.X, 0, lv.Z)
            f = f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
            local r = Vector3.new(-f.Z, 0, f.X)
            local df, dr = dir:Dot(f), dir:Dot(r)
            if math.abs(dr) >= math.abs(df) then
                want[dr > 0 and Enum.KeyCode.D or Enum.KeyCode.A] = true
            else
                want[df > 0 and Enum.KeyCode.W or Enum.KeyCode.S] = true
            end
        end
        for key in pairs(self.Keys) do
            if not want[key] then
                self.Keys[key] = nil
                pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
            end
        end
        -- [v56] приоритет игрока: если он сам жмёт ПРОТИВОПОЛОЖНУЮ клавишу (A против D, W против S) -
        -- не перебиваем (раньше обе клавиши гасили друг друга и персонаж вставал / шёл криво)
        local OPP = { [Enum.KeyCode.A] = Enum.KeyCode.D, [Enum.KeyCode.D] = Enum.KeyCode.A,
            [Enum.KeyCode.W] = Enum.KeyCode.S, [Enum.KeyCode.S] = Enum.KeyCode.W }
        for key in pairs(want) do
            local opp = OPP[key]
            if opp and not self.Keys[opp] and UserInputService:IsKeyDown(opp) then want[key] = nil end
        end
        for key in pairs(self.Keys) do
            if not want[key] then
                self.Keys[key] = nil
                pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
            end
        end
        for key in pairs(want) do
            if not self.Keys[key] and not UserInputService:IsKeyDown(key) then
                self.Keys[key] = true
                pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
            end
        end
    end,

    -- [v43] куда игрок сам жмёт WASD (без наших нажатий), в мире
    UserDir = function(self)
        local cam = workspace.CurrentCamera
        local f = FlatUnit(cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)) or Vector3.new(0, 0, -1)
        local r = Vector3.new(-f.Z, 0, f.X)
        local v = Vector3.zero
        local function held(k) return not self.Keys[k] and UserInputService:IsKeyDown(k) end
        if held(Enum.KeyCode.W) then v += f end
        if held(Enum.KeyCode.S) then v -= f end
        if held(Enum.KeyCode.D) then v += r end
        if held(Enum.KeyCode.A) then v -= r end
        return v.Magnitude > 0.1 and v.Unit or nil
    end,

    -- [v43] сторона ухода от линии угрозы lineDir: 1) куда игрок уже идёт; 2) где нет стены;
    -- 3) ближе к краю (offset - вектор от оси угрозы к игроку). Выбор держится, пока угроза жива.
    PickSide = function(self, key, myRoot, lineDir, offset, char, ignore)
        local flat = FlatUnit(lineDir)
        if not flat then return nil end
        local right = Vector3.new(-flat.Z, 0, flat.X)
        local now = os.clock()
        for k, rec in pairs(self.Sides) do if now - rec.T > 0.6 then self.Sides[k] = nil end end
        local rec = key and self.Sides[key]
        if rec then rec.T = now return right * rec.S end
        -- [v58] свободное место с каждой стороны: лучи на уровне ног и груди, до 8 стад
        self.WallRay = self.WallRay or RaycastParams.new()
        self.WallRay.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { Containers.Root }
        if char then filter[#filter + 1] = char end
        if ignore then filter[#filter + 1] = ignore end
        self.WallRay.FilterDescendantsInstances = filter
        local pos = myRoot.Position
        local function free(sign)
            local best = 8
            for _, dy in ipairs({ -1.8, 0.8 }) do
                local hit = workspace:Raycast(pos + Vector3.new(0, dy, 0), right * sign * 8, self.WallRay)
                if hit then best = math.min(best, (hit.Position - (pos + Vector3.new(0, dy, 0))).Magnitude) end
            end
            return best
        end
        local fR, fL = free(1), free(-1)
        local s
        local want = self:UserDir()
        -- 1) куда игрок уже идёт - если там есть место (>= 3.5 ст)
        if want and math.abs(want:Dot(right)) > 0.3 then
            local ws = want:Dot(right) > 0 and 1 or -1
            if (ws == 1 and fR or fL) >= 3.5 then s = ws end
        end
        if not s then
            -- 2) ближний край линии, если там не стена; 3) иначе - где свободнее
            s = (offset and offset:Dot(right) < 0) and -1 or 1
            local fs, fo = (s == 1 and fR or fL), (s == 1 and fL or fR)
            if fs < 3.5 and fo > fs then s = -s end
        end
        if key then self.Sides[key] = { S = s, T = now } end
        return right * s
    end,

    -- [FIX v18] Раньше Ctrl нажимался ОДИН раз. Если игра его не приняла (бег, действие) - присед так и
    -- не происходил, а скрипт считал, что сидим. Теперь:
    --   * клавиши присед/спринт берутся из KeybindsConfig игры (если переназначены), иначе Ctrl / Shift;
    --   * пока нужно сидеть, а атрибут персонажа Crouching ~= true - повторяем нажатие каждые CROUCH_RETRY;
    --   * если персонаж бежит (Sprinting == true) - отпускаем клавишу спринта, чтобы присед прошёл.
    Keybind = function(self, names, fallback)
        local ok, cfg = pcall(function()
            return require(game:GetService("ReplicatedStorage").Modules.Survivors.KeybindsConfig)
        end)
        if ok and type(cfg) == "table" and type(cfg.getRaw) == "function" then
            for _, n in ipairs(names) do
                local okRaw, raw = pcall(cfg.getRaw, n)
                if okRaw and raw ~= nil then
                    if typeof(raw) == "EnumItem" and raw.EnumType == Enum.KeyCode then return raw end
                    if type(raw) == "string" then
                        local okKey, key = pcall(function() return Enum.KeyCode[raw] end)
                        if okKey and key then return key end
                    end
                end
            end
        end
        return fallback
    end,

    SetCrouch = function(self, on)
        local char = LocalPlayer.Character
        local now = os.clock()
        if not self.CrouchKey then
            self.CrouchKey = self:Keybind({ "crouch", "Crouch" }, DODGE_KNIGHT.CrouchKey)
            self.SprintKey = self:Keybind({ "sprint", "Sprint", "run", "Run" }, Enum.KeyCode.LeftShift)
        end
        local key = self.CrouchKey

        if not on then
            if self.Crouching then
                self.Crouching = false
                pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
            end
            return
        end

        local crouched = char and char:GetAttribute("Crouching") == true
        if not self.Crouching then
            self.Crouching = true
            self.CrouchPressAt = now
            if char and char:GetAttribute("Sprinting") == true then
                pcall(function() VirtualInputManager:SendKeyEvent(false, self.SprintKey, false, game) end)
            end
            pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
        elseif not crouched and now - (self.CrouchPressAt or 0) >= CROUCH_RETRY then
            -- не сел -> отпускаем спринт и жмём заново
            self.CrouchPressAt = now
            if char and char:GetAttribute("Sprinting") == true then
                pcall(function() VirtualInputManager:SendKeyEvent(false, self.SprintKey, false, game) end)
            end
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, key, false, game)
                VirtualInputManager:SendKeyEvent(true, key, false, game)
            end)
        end
    end,

    Enable = function(self)
        -- после ControlModule (RenderPriority.Input): наш Humanoid:Move перекрывает ввод клавиатуры
        local name = RandomName()
        RunService:BindToRenderStep(name, Enum.RenderPriority.Input.Value + 1, function()
            SafeRun(self, "Step")
        end)
        self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
        self.Maid:Give(function() self:SetCrouch(false) end)
        self.Maid:Give(function() self:SetStrafe(nil) end) -- [NEW v13] отпустить WASD
    end,

    Step = function(self)
        local team = LocalPlayer.Team
        local char = LocalPlayer.Character
        local myRoot = GetRoot(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not team or not string.find(string.lower(team.Name), "survivor", 1, true)
            or not myRoot or not hum or hum.Health <= 0 then
            self:SetCrouch(false)
            self:SetStrafe(nil)
            return
        end

        local slashOn = Toggles.DodgeAbyss_Slash.Value
        local corruptOn = Toggles.DodgeAbyss_Corrupt.Value
        local strafe, crouch = nil, false

        -- Corrupt: летящая волна (visualize) - уходим из её коридора, пока не пролетит
        if corruptOn then
            AbyssWaves.Bind()
            AbyssWaves.BindModels() -- [NEW v13]
            local esc, escDir, escKey, escSide = AbyssWaves.Escape(myRoot.Position, math.max(myRoot.Size.X, myRoot.Size.Z) / 2)
            if esc then strafe = (escDir and self:PickSide(escKey, myRoot, escDir, escSide, char)) or esc end
        end

        for _, e in ipairs(Targets.Killers) do
            if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == DODGE_KNIGHT.Killer and e.Root then
                local kPos, myPos = e.Root.Position, myRoot.Position
                local dist = (myPos - kPos).Magnitude
                local look = FlatUnit(e.Root.CFrame.LookVector)
                local toMe = FlatUnit(myPos - kPos)

                -- [CHANGED v12] Corrupt windup: уходим, ТОЛЬКО если предсказанная линия волны проходит через нас.
                -- Раньше: линия по HRP (во время каста он стоит, целится камерой) и уход вбок без проверки угрозы.
                self.CorruptCast = self.CorruptCast or {}
                local casting = corruptOn and KillerTracks(e, DODGE_KNIGHT.CorruptAnims)
                if casting and not self.CorruptCast[e.Model] then
                    self.CorruptCast[e.Model] = { T0 = os.clock(), Side = nil }
                elseif not casting then
                    self.CorruptCast[e.Model] = nil
                end
                local cast = self.CorruptCast[e.Model]
                -- волна уже вылетела после старта этого каста -> дальше работает fallback по летящей волне
                -- [v43] + по времени: волна вылетает через CORRUPT_FIRE от старта - дальше линию прицела не держим
                local fired = cast and ((AbyssWaves.LastAt and AbyssWaves.LastAt >= cast.T0)
                    or os.clock() - cast.T0 > CORRUPT_FIRE + 0.15)
                if cast and not strafe and not fired then -- [CHANGED v23] дальность - из LaneThreat (range ниже)
                    -- до выстрела (CORRUPT_FIRE от старта) линия следует за прицелом, после - фиксируется
                    local aim = cast.Aim or CorruptAim(e)
                    if aim and not cast.Aim and os.clock() - cast.T0 >= CORRUPT_FIRE then cast.Aim = aim end
                    if aim then
                        local range = AbyssWaves.LastRange or CORRUPT_RANGE
                        local width = (AbyssWaves.Half or 4) + math.max(myRoot.Size.X, myRoot.Size.Z) / 2 + CORRUPT_MARGIN
                        local threat, side = LaneThreat(kPos, aim, range, myPos, width)
                        -- [NEW v13] направление волны выбирает сервер (в файлах нет) -> проверяем и линию по HRP
                        local rootAim = look
                        if not threat and rootAim and not cast.Aim then
                            threat, side = LaneThreat(kPos, rootAim, range, myPos, width)
                            if threat then aim = rootAim end
                        end
                        if threat then
                            strafe = self:PickSide(cast, myRoot, aim, side, char, e.Model)
                        end
                    end
                end

                -- [CHANGED v11] Slash: садимся не со старта анимации, а к удару (0.8с - упреждение),
                -- держим окно удара (0.2с) + запас и сразу встаём. Решение "это в меня" - в момент приседа:
                -- мы перед ним и он дотянется рывком (35 ст/с * оставшееся время + хитбокс) или ближе Slash range.
                local slashing = slashOn and KillerTracks(e, DODGE_KNIGHT.SlashAnims)
                self.SlashStart = self.SlashStart or {}
                if slashing and not self.SlashStart[e.Model] then
                    self.SlashStart[e.Model] = os.clock()
                elseif not slashing then
                    self.SlashStart[e.Model] = nil
                end
                local t0 = self.SlashStart[e.Model]
                if t0 then
                    local t = os.clock() - t0
                    local from = SLASH_HIT_AT - Options.DodgeAbyss_SlashLead.Value / 1000
                    local to = SLASH_HIT_AT + SLASH_HIT_WIN + SLASH_TAIL
                    if t >= from and t <= to then
                        local inFront = look and toMe
                            and look:Dot(toMe) >= SLASH_FRONT_COS
                        local reach = math.max(SLASH_HIT_AT - t, 0) * SLASH_SPEED + SLASH_REACH
                        if self.Crouching or (inFront and dist <= reach) then
                            crouch = true
                        end
                    end
                end
            end
        end

        -- [NEW v14] копьё Veil. [CHANGED v15] додж ТОЛЬКО после броска (по летящему копью), на заряде не уходим
        if not strafe and Toggles.DodgeVeil_Spear.Value then
            for _, e in ipairs(Targets.Killers) do
                if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == "veil" and e.Root then
                    local st = VeilSpearTrack(e)
                    local origin, vel, pierce
                    if st.Flight then
                        origin, vel, pierce = st.Flight.Origin, st.Flight.Vel, st.Flight.Pierce
                    elseif st.ChargeStart and Toggles.DodgeVeil_Charge.Value then
                        -- [v56] уход ЗАРАНЕЕ, на заряде: копьё летит 180 ст/с - с 20 стадов это 0.1с, после броска
                        -- не успеть. Если прицел (текущая сила и полная) идёт через тебя - уже уходим с линии.
                        local o, d = VeilAim(e)
                        if o then
                            local charge = math.max(os.clock() - st.ChargeStart, SPEAR.MinCharge)
                            local m = Options.DodgeVeil_Margin.Value + 1
                            for _, sp in ipairs({ math.clamp(charge * SPEAR.Speed, 1, SPEAR.Speed), SPEAR.Speed }) do
                                local pp = VeilSpearPath(o, d * sp, st.Empowered)
                                if SpearHitsMe(pp, char, m) then
                                    local dir = FlatUnit(d)
                                    if dir then
                                        local rel = myRoot.Position - o
                                        rel = Vector3.new(rel.X, 0, rel.Z)
                                        strafe = self:PickSide(st, myRoot, dir, rel - dir * rel:Dot(dir), char, e.Model)
                                    end
                                    break
                                end
                            end
                        end
                    end
                    if origin and not strafe then
                        -- [v43] только ОСТАВШИЙСЯ путь: копьё уже пролетело мимо - больше не держим
                        local pts = VeilSpearPath(origin, vel, pierce)
                        local elapsed = os.clock() - (st.Flight.At or os.clock())
                        local left = {}
                        for i, p in ipairs(pts) do
                            if p.T >= elapsed - 0.05 or (pts[i + 1] and pts[i + 1].T >= elapsed) then left[#left + 1] = p end
                        end
                        if #left >= 2 and SpearHitsMe(left, char, Options.DodgeVeil_Margin.Value) then
                            local a, b = left[1].Pos, left[#left].Pos
                            local dir = FlatUnit(b - a) or FlatUnit(vel)
                            if dir then
                                local rel = myRoot.Position - a
                                rel = Vector3.new(rel.X, 0, rel.Z)
                                strafe = self:PickSide(st, myRoot, dir, rel - dir * rel:Dot(dir), char, e.Model) -- [v56] та же сторона, что на заряде
                            end
                        end
                    end
                end
            end
        end

        -- [v37] колба Cure / цепь Butcher: по точным данным сервера, уход перпендикулярно оставшемуся пути
        if not strafe and (Toggles.DodgeCure_Flask.Value or Toggles.DodgeButcher_Chain.Value) then
            Projectiles.Bind()
            local serverNow = workspace:GetServerTimeNow()
            Projectiles.Prune(serverNow)
            local function away(from, dirV, key)
                local flat = FlatUnit(dirV)
                if not flat then return nil end
                local rel = myRoot.Position - from
                rel = Vector3.new(rel.X, 0, rel.Z)
                return self:PickSide(key, myRoot, flat, rel - flat * rel:Dot(flat), char)
            end
            -- [v56] заранее: Cure целится колбой (flaskcharge / flaskidle / flaskthrow) - считаем путь сами
            -- по FlaskTrajectory.trace из камеры (CamPos / CamLook) и уходим, если он идёт через тебя
            if Toggles.DodgeCure_Flask.Value and Toggles.DodgeCure_Aim.Value then
                for _, e in ipairs(Targets.Killers) do
                    if not strafe and e.Root and KillerTracks(e, Projectiles.FLASK_AIM_ANIMS) then
                        local pts = Projectiles.FlaskPredict(e)
                        if pts and #pts >= 2 and SpearHitsMe(pts, char, Options.DodgeCure_Margin.Value + 1) then
                            strafe = away(pts[1].Pos, pts[#pts].Pos - pts[1].Pos, e.Model)
                        end
                    end
                end
            end
            if Toggles.DodgeCure_Flask.Value then
                for _, f in ipairs(Projectiles.Flasks) do
                    local left = not strafe and Projectiles.FlaskLeft(f, serverNow)
                    if left and #left >= 2 and SpearHitsMe(left, char, Options.DodgeCure_Margin.Value) then
                        strafe = away(left[1].Pos, left[#left].Pos - left[1].Pos, f)
                    end
                end
            end
            if not strafe and Toggles.DodgeButcher_Chain.Value then
                for owner, ch in pairs(Projectiles.Chains) do
                    local tip, stop = Projectiles.ChainNow(ch, serverNow)
                    if tip and owner ~= char and SpearHitsMe({ { Pos = tip }, { Pos = stop } }, char,
                        Projectiles.CHAIN_RADIUS + Options.DodgeButcher_Margin.Value) then
                        strafe = away(ch.Origin, ch.Dir, ch)
                        break
                    end
                end
            end
        end

        -- [v58] легит-слой поверх найденного ухода:
        local now = os.clock()
        if strafe then
            -- реакция: начинаем через случайные 0..React мс после появления угрозы
            if not self.ThreatAt then
                self.ThreatAt = now + math.random() * Options.Dodge_React.Value / 1000
            end
            if now < self.ThreatAt then strafe = nil end
            -- игрок и так уходит в ту же сторону -> ничего не жмём
            local mine = self:UserDir()
            if strafe and Toggles.Dodge_TrustMe.Value and mine and mine:Dot(strafe) > 0.5 then strafe = nil end
            -- анти-застревание: жмём уход, а за 0.35с почти не сдвинулись вбок -> меняем сторону
            if strafe then
                local p = myRoot.Position
                local st = self.Stuck
                if not st or (st.Dir - strafe).Magnitude > 0.5 then
                    self.Stuck = { Dir = strafe, P = p, T = now }
                elseif now - st.T > 0.35 then
                    local moved = (p - st.P):Dot(strafe)
                    if moved < 1 then
                        for _, rec in pairs(self.Sides) do rec.S = -rec.S end
                        strafe = -strafe
                    end
                    self.Stuck = { Dir = strafe, P = p, T = now }
                end
            end
        else
            if self.ThreatAt and now - (self.ThreatGone or now) > 0.2 then self.ThreatAt = nil end
            self.ThreatGone = self.ThreatGone or now
            self.Stuck = nil
        end
        if strafe or self.ThreatAt == nil then self.ThreatGone = nil end

        -- [CHANGED v13] клавишами вместо Humanoid:Move
        self:SetStrafe(strafe)
        self:SetCrouch(crouch)
    end,

    Disable = function(self)
        self.Crouching = false
        table.clear(self.Keys)
    end,
})

-- [v43] Визуалайзер копья Veil в 3D. Полёт копья - парабола p(t) = o + v*t + g*t^2/2 (SpearMath),
-- а парабола - это в точности кубическая кривая Безье: контрольные точки o + v*T/3 и p(T) - v(T)*T/3.
-- Поэтому вся дуга - один Beam с изогнутыми концами: гладко, без 2D-проекции (она и дёргалась).
-- Место удара - неоновое кольцо по нормали поверхности; у пробивного копья (абилка) - ещё
-- отдельная белая отметка там, где оно прошивает стену и летит дальше.
Projectiles.SpearViz = { Pool = {} }
do
    local SV = Projectiles.SpearViz
    local function seq(a, b) return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) end
    local function holderPart(folder)
        return New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
            CastShadow = false, Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1), CFrame = CFrame.new(), Parent = folder })
    end
    local function neon(folder, size, shape)
        return New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
            CastShadow = false, Material = Enum.Material.Neon, Transparency = 1, Size = size,
            Shape = shape or Enum.PartType.Block, Parent = folder })
    end
    -- кольцо из N неоновых отрезков
    local function ring(folder, r, n, th)
        local R = { Segs = {}, R = r, N = n }
        for i = 1, n do R.Segs[i] = neon(folder, Vector3.new(th, th, 2 * math.pi * r / n * 0.78)) end
        function R:Set(cf, color, transparency)
            local u, w = cf.RightVector, cf.UpVector
            for i, sp in ipairs(self.Segs) do
                local a = (i - 1) / self.N * 2 * math.pi
                local pos = cf.Position + (u * math.cos(a) + w * math.sin(a)) * self.R
                sp.CFrame = CFrame.lookAt(pos, pos + (w * math.cos(a) - u * math.sin(a)))
                sp.Color = color
                sp.Transparency = transparency
            end
        end
        function R:Hide() for _, sp in ipairs(self.Segs) do sp.Transparency = 1 end end
        return R
    end
    local function frameAlong(pos, dir)
        local x = dir.Magnitude > 1e-4 and dir.Unit or Vector3.new(0, 0, -1)
        local up = Vector3.new(0, 1, 0)
        if math.abs(x:Dot(up)) > 0.98 then up = Vector3.new(1, 0, 0) end
        local y = (up - x * up:Dot(x)).Unit
        return CFrame.fromMatrix(pos, x, y)
    end
    local function surfaceCF(pos, normal)
        local n = (typeof(normal) == "Vector3" and normal.Magnitude > 0.1) and normal.Unit or Vector3.new(0, 1, 0)
        return CFrame.lookAt(pos + n * 0.06, pos + n * 2)
    end

    function SV.Get(folder, key)
        local v = SV.Pool[key]
        if v and v.Holder.Parent then return v end
        local h = holderPart(folder)
        local a0 = New("Attachment", { Parent = h })
        local a1 = New("Attachment", { Parent = h })
        local function beam(w0, w1, t0, t1)
            return New("Beam", { Attachment0 = a0, Attachment1 = a1, Segments = 48, Width0 = w0, Width1 = w1,
                FaceCamera = true, LightEmission = 1, LightInfluence = 0, Transparency = seq(t0, t1), Enabled = false, Parent = h })
        end
        v = {
            Holder = h, A0 = a0, A1 = a1,
            Core = beam(0.22, 0.12, 0.05, 0.55), -- линия
            Glow = beam(0.85, 0.45, 0.8, 0.95),   -- свечение вокруг
            Ball = neon(folder, Vector3.new(0.7, 0.7, 0.7), Enum.PartType.Ball), -- копьё сейчас
            Hit = ring(folder, 1.8, 20, 0.16),     -- место удара
            HitDot = neon(folder, Vector3.new(0.5, 0.5, 0.5), Enum.PartType.Ball),
            Pierce = ring(folder, 1.1, 14, 0.12),  -- пробитие стены
        }
        SV.Pool[key] = v
        return v
    end

    function SV.Hide(v)
        v.Core.Enabled, v.Glow.Enabled = false, false
        v.Ball.Transparency, v.HitDot.Transparency = 1, 1
        v.Hit:Hide()
        v.Pierce:Hide()
    end

    -- t0: сколько копьё уже летит (0 - ещё на заряде); preview: пунктир/бледнее для предсказания
    -- Возвращает точку удара (для 2D-отметки поверх стен).
    function SV.Draw(v, origin, vel, pierce, t0, color, preview)
        local g = SPEAR.Gravity
        local pts, impact, normal = VeilSpearPath(origin, vel, pierce)
        local tEnd = pts[#pts] and pts[#pts].T or SPEAR.MaxLife
        if t0 >= tEnd - 1e-3 then SV.Hide(v) return nil end
        local p0 = origin + vel * t0 + g * (0.5 * t0 * t0)
        local v0 = vel + g * t0
        local T = tEnd - t0
        local p3 = impact or (origin + vel * tEnd + g * (0.5 * tEnd * tEnd))
        local v3 = vel + g * tEnd
        v.A0.WorldCFrame = frameAlong(p0, v0)
        v.A1.WorldCFrame = frameAlong(p3, v3)
        local col = ColorSequence.new(color)
        for _, b in ipairs({ v.Core, v.Glow }) do
            b.CurveSize0 = v0.Magnitude * T / 3
            b.CurveSize1 = v3.Magnitude * T / 3
            b.Color = col
            b.Enabled = true
        end
        v.Core.Transparency = preview and seq(0.35, 0.75) or seq(0.05, 0.55)
        -- копьё в полёте
        if t0 > 0 then
            v.Ball.CFrame = CFrame.new(p0)
            v.Ball.Color = color
            v.Ball.Transparency = 0.1
        else
            v.Ball.Transparency = 1
        end
        -- место удара
        v.HitCF = surfaceCF(p3, normal) -- [v65]
        v.Hit:Set(v.HitCF, color, preview and 0.45 or 0.1)
        v.HitDot.CFrame = CFrame.new(p3)
        v.HitDot.Color = color
        v.HitDot.Transparency = preview and 0.5 or 0.1
        -- пробивное копьё: где бы обычное ударилось о стену - белая отметка, дуга идёт дальше
        if pierce then
            local wpts, wImpact, wNormal = VeilSpearPath(origin, vel, false)
            local wT = wpts[#wpts] and wpts[#wpts].T or 0
            if wImpact and wT > t0 then
                v.Pierce:Set(surfaceCF(wImpact, wNormal), Color3.new(1, 1, 1), 0.15)
            else
                v.Pierce:Hide()
            end
        else
            v.Pierce:Hide()
        end
        return p3, pts -- [v65] + точки пути (для проверки «летит в меня»)
    end

    -- [v65] вариант C: путь в тебя - линия цветом предупреждения и широкий полупрозрачный коридор
    -- (ширина ~ хитбокс тела); иначе обычное свечение
    function SV.SetDanger(v, color)
        if color then
            local col = ColorSequence.new(color)
            v.Core.Color, v.Glow.Color = col, col
            v.Glow.Width0, v.Glow.Width1 = 3.2, 2.4
            v.Glow.Transparency = seq(0.78, 0.86)
            v.Hit:Set(v.HitCF or CFrame.new(), color, 0.1)
        else
            v.Glow.Width0, v.Glow.Width1 = 0.85, 0.45
            v.Glow.Transparency = seq(0.8, 0.95)
        end
    end

    -- [v65] время до удара по тебе: первая точка оставшегося пути (после t0), задевающая тело; nil - мимо
    function SV.HitTime(pts, char, margin, t0)
        if not (pts and char) then return nil end
        local grow = Vector3.new(margin, margin, margin) * 2
        for i = 1, #pts - 1 do
            if pts[i + 1].T >= t0 then
                local a, b = pts[i].Pos, pts[i + 1].Pos
                for _, name in ipairs(SPEAR_BODY) do
                    local part = char:FindFirstChild(name)
                    if part and part:IsA("BasePart") and SegBox(a, b - a, part.CFrame, part.Size + grow) then
                        return math.max(pts[i].T - t0, 0)
                    end
                end
            end
        end
        return nil
    end

    function SV.Clear()
        for k, v in pairs(SV.Pool) do
            pcall(function() v.Holder:Destroy() end)
            pcall(function() v.Ball:Destroy() v.HitDot:Destroy() end)
            for _, sp in ipairs(v.Hit.Segs) do pcall(function() sp:Destroy() end) end
            for _, sp in ipairs(v.Pierce.Segs) do pcall(function() sp:Destroy() end) end
            SV.Pool[k] = nil
        end
    end
end

-- [NEW v13] ESP абилок: волна Corrupt (Highlight + путь до конца дальности) и прицел Corrupt на касте
do
    local waveGroup = HighlightGroup.new(function()
        local c = Options.AbilityESP_WaveColor.Value
        return { FillColor = c, FillTransparency = 0.4, OutlineColor = c, OutlineTransparency = 0,
            DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }
    end, 0) -- приоритет как у киллера: волна важнее объектов

    DefineFeature({
        Id = "AbilityESP_",
        Gate = { "AbilityESP_Wave", "AbilityESP_CorruptAim", "AbilityESP_VeilSpear", "AbilityESP_Flask", "AbilityESP_Chain" }, -- [v14] + Veil, [v37] + Cure, Butcher
        Watch = { "AbilityESP_WaveColor", "AbilityESP_VeilColor", "AbilityESP_FlaskColor", "AbilityESP_ChainColor" },
        Lines = {},
        Dots = {}, -- [NEW v16]

        Enable = function(self)
            self.Gui = self.Maid:Give(NewOverlayGui())
            AbyssWaves.BindModels()
            AbyssWaves.Bind()
            Projectiles.Bind() -- [v37]
            -- [v43] 3D-дуга копья: детали/лучи в папке камеры (видны только тебе, лучи их не видят)
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.SpearFolder = self.Maid:Give(folder)
            self.SpearSmooth = {}
            self.Maid:Give(function() Projectiles.SpearViz.Clear() end)
        end,

        Update = function(self)
            local list = {}
            if Toggles.AbilityESP_Wave.Value then
                for _, w in ipairs(AbyssWaves.Live()) do list[#list + 1] = w.Model end
            end
            waveGroup:Sync(list)
        end,

        Render = function(self)
            local gui, cam = self.Gui, workspace.CurrentCamera
            if not gui or not cam then return end
            local camCF = cam.CFrame
            local color = Options.AbilityESP_WaveColor.Value
            local used = 0

            local lineColor = color
            local function line(a, b, transparency)
                local da, db = -camCF:PointToObjectSpace(a).Z, -camCF:PointToObjectSpace(b).Z
                if da < 0.1 and db < 0.1 then return end
                if da < 0.1 or db < 0.1 then
                    local k = (0.1 - da) / (db - da)
                    if da < 0.1 then a = a + (b - a) * k else b = a + (b - a) * k end
                end
                local sa, sb = cam:WorldToViewportPoint(a), cam:WorldToViewportPoint(b)
                used += 1
                local f = self.Lines[used]
                if not f then
                    f = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = gui })
                    self.Lines[used] = f
                end
                SetLineFrame(f, Vector2.new(sa.X, sa.Y), Vector2.new(sb.X, sb.Y), lineColor, 2)
                SetIf(f, "BackgroundTransparency", transparency)
            end


            -- [NEW v14] путь копья чужого Veil: на заряде (текущая сила) и летящего
            -- [CHANGED v16] визуал: тёмная подложка + линия, затухание к концу, метки каждые 0.1с, кольцо удара
            local usedD = 0
            local function dot(p, size, transparency)
                local sp = cam:WorldToViewportPoint(p)
                if sp.Z <= 0 then return end
                usedD += 1
                local d = self.Dots[usedD]
                if not d then
                    d = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = gui })
                    New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
                    New("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.4, Parent = d })
                    self.Dots[usedD] = d
                end
                SetIf(d, "Position", UDim2.fromOffset(sp.X, sp.Y))
                SetIf(d, "Size", UDim2.fromOffset(size, size))
                SetIf(d, "BackgroundColor3", lineColor)
                SetIf(d, "BackgroundTransparency", transparency)
                SetIf(d, "Visible", true)
            end
            local function thick(a, b, w, c, transparency)
                local saved, before = lineColor, used
                lineColor = c
                line(a, b, transparency)
                lineColor = saved
                if used > before then
                    local f = self.Lines[used]
                    if f.Visible then SetIf(f, "Size", UDim2.fromOffset(f.Size.X.Offset, w)) end
                end
            end

            -- [v56] Corrupt: «опасная полоса» на полу шириной с волну (как Floor Cone: деталь + SurfaceGui
            -- AlwaysOnTop -> видна сквозь стены, ровная, без 2D-линий в воздухе). Заливка + рамка;
            -- у летящей волны - яркая черта там, где волна сейчас (ближний край полосы).
            local usedLane = 0
            self.Lanes = self.Lanes or {}
            self.LaneRay = self.LaneRay or RaycastParams.new()
            self.LaneRay.FilterType = Enum.RaycastFilterType.Exclude
            local laneFilter = { Containers.Root, self.SpearFolder }
            for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then laneFilter[#laneFilter + 1] = plr.Character end end
            for _, w in ipairs(AbyssWaves.Live()) do if w.Model then laneFilter[#laneFilter + 1] = w.Model end end
            self.LaneRay.FilterDescendantsInstances = laneFilter
            local function lane(p, dir, len, half, c, head)
                if len < 0.5 or not self.SpearFolder then return end
                local down = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), self.LaneRay)
                local y = (down and down.Position.Y or (p.Y - 3)) + 0.08
                local a = Vector3.new(p.X, y, p.Z)
                usedLane += 1
                local L = self.Lanes[usedLane]
                if not L then
                    local part = New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false,
                        CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(1, 0.05, 1), Parent = self.SpearFolder })
                    local sg = New("SurfaceGui", { Name = RandomName(), Face = Enum.NormalId.Top, AlwaysOnTop = true, LightInfluence = 0,
                        SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 12, Adornee = part, Parent = Containers.World })
                    local fill = New("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = sg })
                    local stroke = New("UIStroke", { Thickness = 3, Parent = fill })
                    local bar = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
                        Size = UDim2.new(1, 0, 0, 10), BorderSizePixel = 0, Parent = fill })
                    L = { Part = part, Gui = sg, Fill = fill, Stroke = stroke, Bar = bar }
                    self.Lanes[usedLane] = L
                end
                L.Part.Size = Vector3.new(half * 2, 0.05, len)
                L.Part.CFrame = CFrame.lookAt(a + dir * (len / 2), a + dir * (len / 2 + 1))
                SetIf(L.Gui, "Enabled", true)
                SetIf(L.Fill, "BackgroundColor3", c)
                SetIf(L.Fill, "BackgroundTransparency", head and 0.72 or 0.82)
                SetIf(L.Stroke, "Color", c)
                SetIf(L.Stroke, "Transparency", head and 0.1 or 0.35)
                SetIf(L.Bar, "BackgroundColor3", c)
                SetIf(L.Bar, "Visible", head == true)
            end
            if Toggles.AbilityESP_Wave.Value then
                for _, w in ipairs(AbyssWaves.Live()) do
                    local flown = ((w.Pos - w.Origin) * Vector3.new(1, 0, 1)).Magnitude
                    local left = math.max(w.Range - flown, 0)
                    local d = Vector3.new(w.Dir.X, 0, w.Dir.Z)
                    if d.Magnitude > 1e-3 then lane(w.Pos, d.Unit, left, AbyssWaves.Half or 4, color, true) end
                end
            end
            -- прицел на касте (до вылета): та же полоса, бледнее
            if Toggles.AbilityESP_CorruptAim.Value then
                for _, e in ipairs(Targets.Killers) do
                    if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == DODGE_KNIGHT.Killer and e.Root
                        and KillerTracks(e, DODGE_KNIGHT.CorruptAnims) then
                        local aim = CorruptAim(e)
                        if aim then
                            lane(e.Root.Position, aim, AbyssWaves.LastRange or CORRUPT_RANGE, AbyssWaves.Half or 4, color, false)
                        end
                    end
                end
            end
            for k = usedLane + 1, #self.Lanes do SetIf(self.Lanes[k].Gui, "Enabled", false) end

            local spearDrawn = {} -- [v43] какие дуги рисовали в этом кадре (остальные прячем)
            local warn = nil -- [v65] { Left = сек до удара (nil - ещё заряжает), Root = Veil }
            if Toggles.AbilityESP_VeilSpear.Value then
                lineColor = Options.AbilityESP_VeilColor.Value
                for _, e in ipairs(Targets.Killers) do
                    if HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller")) == "veil" and e.Root then
                        spearDrawn[e.Model] = true
                        local st = VeilSpearTrack(e)
                        local origin, vel, alpha, pierce
                        if st.Flight then
                            origin, vel, alpha, pierce = st.Flight.Origin, st.Flight.Vel, 0, st.Flight.Pierce
                        elseif st.ChargeStart then
                            local o, d = VeilAim(e)
                            if o then
                                local charge = math.max(os.clock() - st.ChargeStart, SPEAR.MinCharge)
                                origin, vel, alpha = o, d * math.clamp(charge * SPEAR.Speed, 1, SPEAR.Speed), 0.4
                                pierce = st.Empowered
                            end
                        end
                        local viz = self.SpearFolder and Projectiles.SpearViz.Get(self.SpearFolder, e.Model)
                        if origin and viz then
                            local t0 = 0
                            local sm = self.SpearSmooth[e.Model]
                            if st.Flight then
                                -- точный/летящий: без сглаживания, рисуем только оставшуюся часть дуги
                                t0 = math.max(os.clock() - (st.Flight.At or os.clock()), 0)
                                self.SpearSmooth[e.Model] = nil
                            else
                                -- [v43] предсказание на заряде: сглаживаем, чтобы дуга не дёргалась от шума прицела
                                local now = os.clock()
                                if sm and now - sm.At < 0.5 then
                                    local k = 1 - math.exp(-(now - sm.At) / 0.09)
                                    sm.O = sm.O:Lerp(origin, k)
                                    sm.V = sm.V:Lerp(vel, k)
                                    sm.At = now
                                else
                                    sm = { O = origin, V = vel, At = now }
                                    self.SpearSmooth[e.Model] = sm
                                end
                                origin, vel = sm.O, sm.V
                            end
                            local hitPos, pts = Projectiles.SpearViz.Draw(viz, origin, vel, pierce, t0, lineColor, not st.Flight)
                            -- [v65] вариант C: путь задевает тебя -> красная линия + коридор + предупреждение
                            local danger = nil
                            if Toggles.AbilityESP_VeilWarn.Value and hitPos then
                                danger = Projectiles.SpearViz.HitTime(pts, LocalPlayer.Character, 0.6, t0)
                            end
                            Projectiles.SpearViz.SetDanger(viz, danger and Options.AbilityESP_VeilWarnColor.Value or nil)
                            -- [v68] из NL-ветки: дуга ещё и 2D поверх стен (3D-луч стенами закрывается);
                            -- [v69] как в NL v56: 2D только там, где дугу закрывает стена (луч от камеры до точки),
                            -- на открытом месте - одна чистая 3D-дуга. Летит в тебя - цветом предупреждения.
                            if hitPos and pts and pts[#pts] then
                                local tEnd = pts[#pts].T
                                local g, n = SPEAR.Gravity, 20
                                local c2 = danger and Options.AbilityESP_VeilWarnColor.Value or lineColor
                                self.OccRay = self.OccRay or RaycastParams.new()
                                self.OccRay.FilterType = Enum.RaycastFilterType.Exclude
                                local occ = { Containers.Root, self.SpearFolder, cam }
                                for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then occ[#occ + 1] = plr.Character end end
                                self.OccRay.FilterDescendantsInstances = occ
                                local camPos = camCF.Position
                                local function hidden(pt)
                                    local hit = workspace:Raycast(camPos, pt - camPos, self.OccRay)
                                    return hit ~= nil and hit.Position ~= nil and (hit.Position - pt).Magnitude > 1
                                end
                                local prev = origin + vel * t0 + g * (0.5 * t0 * t0)
                                local prevHidden = hidden(prev)
                                for k = 1, n do
                                    local t = t0 + (tEnd - t0) * k / n
                                    local pt = k == n and hitPos or (origin + vel * t + g * (0.5 * t * t))
                                    local h = hidden(pt)
                                    if h or prevHidden then
                                        thick(prev, pt, 5, Color3.new(0, 0, 0), 0.7)
                                        thick(prev, pt, 2, c2, st.Flight and 0.15 or 0.35)
                                    end
                                    prev, prevHidden = pt, h
                                end
                            end
                            if danger then
                                local left = st.Flight and danger or nil
                                if not warn or (left and (not warn.Left or left < warn.Left)) then
                                    warn = { Left = left, Root = e.Root }
                                end
                            end
                            -- точка удара поверх стен (2D), чтобы место было видно и за препятствием
                            if hitPos then dot(hitPos, 6, alpha) end
                        elseif viz then
                            Projectiles.SpearViz.Hide(viz)
                        end
                    end
                end
                lineColor = color
            end
            for key, v in pairs(Projectiles.SpearViz.Pool) do
                if not spearDrawn[key] and key ~= "__self" then Projectiles.SpearViz.Hide(v) end -- [v65] своё копьё рисует SpearAim_
            end
            -- [v65] вариант C: «SPEAR · 0.4s» по центру и стрелка к Veil у края экрана, если его не видно
            do
                local wl, wa = self.WarnLabel, self.WarnArrow
                if not wl then
                    wl = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(240, 22),
                        BackgroundTransparency = 1, TextSize = 18, TextStrokeTransparency = 0.2, Text = "", Visible = false, Parent = gui })
                    Library:ApplyESPFont(wl)
                    wa = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1,
                        TextSize = 22, Text = "▲", TextStrokeTransparency = 0.2, Visible = false, Parent = gui })
                    self.WarnLabel, self.WarnArrow = wl, wa
                end
                local wc = Options.AbilityESP_VeilWarnColor.Value
                if warn then
                    SetIf(wl, "Text", warn.Left and string.format("SPEAR · %.1fs", warn.Left) or "SPEAR · AIMED AT YOU")
                    SetIf(wl, "TextColor3", wc)
                    SetIf(wl, "Visible", true)
                    local vp = cam.ViewportSize
                    local sp, onScreen = cam:WorldToViewportPoint(warn.Root.Position)
                    if onScreen and sp.Z > 0 then
                        SetIf(wa, "Visible", false)
                    else
                        local c = vp / 2
                        local d = Vector2.new(sp.X, sp.Y) - c
                        if sp.Z < 0 then d = -d end
                        if d.Magnitude < 1e-3 then d = Vector2.new(0, -1) end
                        d = d.Unit
                        local r = math.min(vp.X, vp.Y) / 2 - 36
                        SetIf(wa, "Position", UDim2.fromOffset(c.X + d.X * r, c.Y + d.Y * r))
                        SetIf(wa, "Rotation", math.deg(math.atan2(d.Y, d.X)) + 90)
                        SetIf(wa, "TextColor3", wc)
                        SetIf(wa, "Visible", true)
                    end
                else
                    SetIf(wl, "Visible", false)
                    SetIf(wa, "Visible", false)
                end
            end

            -- [v37] колба Cure (точный путь с сервера) и цепь Butcher (точная линия полёта)
            Projectiles.Bind()
            local serverNow = workspace:GetServerTimeNow()
            Projectiles.Prune(serverNow)
            if Toggles.AbilityESP_Flask.Value then
                local c = Options.AbilityESP_FlaskColor.Value
                for _, f in ipairs(Projectiles.Flasks) do
                    local left = Projectiles.FlaskLeft(f, serverNow)
                    if left then
                        for i = 1, #left - 1 do
                            local fade = 0.6 * (i / #left)
                            thick(left[i].Pos, left[i + 1].Pos, 6, Color3.new(0, 0, 0), math.min(0.55 + fade * 0.4, 1))
                            thick(left[i].Pos, left[i + 1].Pos, 3, c, fade)
                        end
                        lineColor = c
                        dot(left[1].Pos, 8, 0)                -- колба сейчас
                        dot(f.Points[#f.Points], 16, 0.6)     -- куда упадёт
                        dot(f.Points[#f.Points], 6, 0)
                        lineColor = color
                    end
                end
            end
            if Toggles.AbilityESP_Chain.Value then
                local c = Options.AbilityESP_ChainColor.Value
                for _, ch in pairs(Projectiles.Chains) do
                    local tip, stop = Projectiles.ChainNow(ch, serverNow)
                    if tip then
                        thick(tip, stop, 6, Color3.new(0, 0, 0), 0.55)
                        thick(tip, stop, 3, c, 0)
                        lineColor = c
                        dot(tip, 8, 0)
                        dot(stop, 14, 0.6)
                        lineColor = color
                    end
                end
            end

            for i = used + 1, #self.Lines do SetIf(self.Lines[i], "Visible", false) end
            for i = usedD + 1, #self.Dots do SetIf(self.Dots[i], "Visible", false) end
        end,

        Disable = function(self)
            waveGroup:Clear()
            table.clear(self.Dots)
            table.clear(self.Lines)
            for _, L in ipairs(self.Lanes or {}) do pcall(L.Gui.Destroy, L.Gui) end
            self.Lanes = nil
            self.Gui = nil
        end,
    })
end

-- [NEW v7] логгер анимаций киллера: печатает каждый новый ID (для заполнения DODGE_KNIGHT и HUD)
DefineFeature({
    Id = "DodgeLogger_",
    Toggle = "Dodge_Logger",
    Seen = {},

    Update = function(self)
        local myRoot = GetRoot(LocalPlayer.Character)
        for _, e in ipairs(Targets.Killers) do
            local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local id = track.Animation and tostring(track.Animation.AnimationId):match("%d+")
                    if id and not self.Seen[id] then
                        self.Seen[id] = true
                        local dist = (myRoot and e.Root) and (myRoot.Position - e.Root.Position).Magnitude or -1
                        print(string.format("[%s][Dodge log] %s (%s) anim=%s name=%s length=%.2fs dist=%.0f",
                            CONFIG.ScriptName, e.Name, tostring(ReadAttr(e.Model, e.Player, "MorphedKiller")),
                            id, tostring(track.Name), track.Length, dist))
                    end
                end
            end
        end
    end,

    Disable = function(self)
        table.clear(self.Seen)
    end,
})

------------------------------------------------------------
-- ChasePreview ("In chase")
------------------------------------------------------------
local CHASE_KEYS = { "IsChasing", "Chasing", "InChase", "IsInChase", "BeingChased", "IsBeingChased" }

local function MatchesMe(v)
    if v == nil then return false end
    if v == LocalPlayer or v == LocalPlayer.Character then return true end
    local t = type(v)
    if t == "string" then
        return v == LocalPlayer.Name or v == LocalPlayer.DisplayName or v == tostring(LocalPlayer.UserId)
    elseif t == "number" then
        return v == LocalPlayer.UserId
    end
    return false
end

local function KeyIsChaseish(name)
    local l = string.lower(name)
    return string.find(l, "chase", 1, true) ~= nil
        or string.find(l, "stalk", 1, true) ~= nil
        or string.find(l, "target", 1, true) ~= nil
end

-- возвращает (inChase: bool, killerEntry|nil)
local function DetectChase()
    local team = LocalPlayer.Team and LocalPlayer.Team.Name
    if team == CONFIG.Teams.Spectator then return false, nil end
    local char = LocalPlayer.Character

    for _, key in ipairs(CHASE_KEYS) do
        if (char and Truthy(char:GetAttribute(key))) or Truthy(LocalPlayer:GetAttribute(key)) then
            return true, (team ~= CONFIG.Teams.Killer) and Targets.Killers[1] or nil
        end
    end

    if team ~= CONFIG.Teams.Killer then
        for _, e in ipairs(Targets.Killers) do
            for _, holder in ipairs({ e.Model, e.Player }) do
                if holder then
                    for name, value in pairs(holder:GetAttributes()) do
                        if KeyIsChaseish(name) and MatchesMe(value) then return true, e end
                    end
                end
            end
            for _, c in ipairs(e.Model:GetChildren()) do
                if c:IsA("ObjectValue") and KeyIsChaseish(c.Name) and MatchesMe(c.Value) then return true, e end
            end
        end
    end
    return false, nil
end

DefineFeature({
    Id = "ChasePreview_",
    Toggle = "ChasePreview_Enabled",

    Enable = function(self)
        local scheme = Library.Scheme
        self.Gui = self.Maid:Give(NewOverlayGui())
        local panel = New("Frame", {
            Name = "ChasePanel",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, CONFIG.ChaseScreenY),
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundColor3 = scheme.MainColor,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            Visible = false,
            Parent = self.Gui,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = panel })
        self.Stroke = New("UIStroke", { Color = scheme.OutlineColor, Thickness = 1.5, Parent = panel })
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 20),
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            Parent = panel,
        })
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = panel,
        })
        self.Dot = New("Frame", {
            LayoutOrder = 1,
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = scheme.AccentColor,
            BorderSizePixel = 0,
            Parent = panel,
        })
        New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Dot })
        self.Label = New("TextLabel", {
            LayoutOrder = 2,
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            FontFace = scheme.Font,
            TextSize = 18,
            TextColor3 = scheme.FontColor,
            Text = "In chase",
            Parent = panel,
        })
        self.Sub = New("TextLabel", {
            LayoutOrder = 3,
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            FontFace = scheme.Font,
            TextSize = 14,
            TextTransparency = 0.4,
            TextColor3 = scheme.FontColor,
            Text = "",
            Visible = false,
            Parent = panel,
        })
        self.Panel = panel
    end,

    Update = function(self)
        if not self.Panel then return end
        local scheme = Library.Scheme
        local on, killer = DetectChase()

        SetIf(self.Panel, "Visible", on)
        SetIf(self.Panel, "BackgroundColor3", scheme.MainColor)
        SetIf(self.Stroke, "Color", scheme.OutlineColor)
        SetIf(self.Dot, "BackgroundColor3", scheme.AccentColor)
        SetIf(self.Label, "TextColor3", scheme.FontColor)
        SetIf(self.Sub, "TextColor3", scheme.FontColor)

        local sub = ""
        local myRoot = GetRoot(LocalPlayer.Character)
        if on and killer and myRoot and killer.Root then
            sub = FormatDist((myRoot.Position - killer.Root.Position).Magnitude)
        end
        SetIf(self.Sub, "Text", sub)
        SetIf(self.Sub, "Visible", sub ~= "")
    end,

    -- мягкая пульсация точки
    Render = function(self)
        if self.Dot and self.Panel and self.Panel.Visible then
            self.Dot.BackgroundTransparency = 0.1 + 0.55 * (0.5 + 0.5 * math.sin(os.clock() * 5))
        end
    end,

    Disable = function(self)
        self.Gui, self.Panel, self.Stroke, self.Dot, self.Label, self.Sub = nil, nil, nil, nil, nil, nil
    end,
})


------------------------------------------------------------
-- [NEW v24] Auto Parry / Moonwalk / Veil Spear Auto-Aim + место падения
------------------------------------------------------------
do
    local function GameKey(names, fallback)
        local ok, cfg = pcall(function()
            return require(game:GetService("ReplicatedStorage").Modules.Survivors.KeybindsConfig)
        end)
        if ok and type(cfg) == "table" and type(cfg.getRaw) == "function" then
            for _, n in ipairs(names) do
                local okRaw, raw = pcall(cfg.getRaw, n)
                if okRaw and raw ~= nil then
                    if typeof(raw) == "EnumItem" and (raw.EnumType == Enum.KeyCode or raw.EnumType == Enum.UserInputType) then return raw end
                    if type(raw) == "string" then
                        local okKey, key = pcall(function() return Enum.KeyCode[raw] end)
                        if okKey and key then return key end
                    end
                end
            end
        end
        return fallback
    end
    ESPUI.GameKey = GameKey -- [v80] для Auto Crouch / Auto Pallet (блок v80 в конце)

    local function IsSurvivorTeam()
        local team = LocalPlayer.Team
        return team ~= nil and string.find(string.lower(team.Name), "survivor", 1, true) ~= nil
    end

    --------------------------------------------------------
    -- Auto Parry (Modules.Items.ParryingDagger.ParryClient):
    --   парри = Remotes.Items["Parrying Dagger"].parry:FireServer(character) + анимация useanim кинжала,
    --   нельзя: кинжал не в персонаже, тег Silenced, HP < 50%, Trapped/IsCarried/IsHooked/IsDead,
    --   тег "doing action" на HRP, CheckInterractable is*-атрибуты, кулдаун (parryResult: success,
    --   cooldown, permanent, clear, character).
    --   Жмём клавишу предмета игры (KeybindsConfig "item") - игра сама делает всё как при ручном парри.
    --   Нет клавиши в конфиге -> делаем то же, что ParryClient:Parry(), напрямую.
    -- Когда: киллер ближе Parry distance, смотрит на нас и начинает атаку: рывок (lungeWalkSpeed 27,
    --   скорость к нам >= 24) или новая анимация приоритета Action (замах). ID анимаций атак в файлах
    --   нет (они в конфигах киллеров), поэтому так.
    --------------------------------------------------------
    local BUSY_ATTRS = { "isVaulting", "isSliding", "isDroppingPallet", "isRepairing", "isHealing", "isUnhooking", "isExiting" }
    local LUNGE_SPEED = 24 -- рывок 27 ст/с; обычный бег киллера ниже
    local SWING_FRESH = 0.25 -- сек: анимация считается «только что начатой»

    -- [v25] Обучение: ID анимаций атак в файлах игры нет (в ReplicatedStorage только Moves = абилки,
    -- конфиги ударов лежат в скриптах киллеров). Поэтому скрипт запоминает их сам: когда тебя бьют,
    -- анимации ближнего киллера, начавшиеся за 1.5с до урона, - это удар; сохраняем ID и время
    -- от начала анимации до удара в <ScriptName>/parry_anims.json. Дальше парри идёт по этим ID
    -- точно ко времени удара (минус «Parry early»). Пока ID не выучены - запасной способ: рывок
    -- (скорость к тебе >= 24, у них lungeWalkSpeed 27) или новая анимация приоритета Action.
    local PARRY_FILE = CONFIG.ScriptName .. "/parry_anims.json"
    local LEARN_WINDOW, LEARN_RANGE, TRACK_RANGE = 1.5, 16, 40
    local Learned = {}
    pcall(function()
        if isfile and isfile(PARRY_FILE) then
            local d = HttpService:JSONDecode(readfile(PARRY_FILE))
            if type(d) == "table" then
                for id, v in pairs(d) do
                    if type(v) == "table" and tonumber(v.delay) then
                        Learned[tostring(id)] = { delay = tonumber(v.delay), hits = tonumber(v.hits) or 1, killer = v.killer }
                    end
                end
            end
        end
    end)
    local function SaveLearned()
        pcall(function()
            if not (writefile and makefolder and isfolder) then return end
            if not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
            writefile(PARRY_FILE, HttpService:JSONEncode(Learned))
        end)
    end
    ESPUI.ParryLearned = Learned -- для тестов

    local function TrackId(track)
        return track.Animation and tostring(track.Animation.AnimationId):match("%d+")
    end

    -- [v34] Из AutoDagger: ID анимаций атаки берутся из скрипта «Animations» в персонаже киллера -
    -- переменные с attack / lunge в имени (без spear): name = "rbxassetid://123". Исходник - через
    -- .Source или decompile() экзекутора. Кэш на экземпляр скрипта.
    local AttackIdsCache = setmetatable({}, { __mode = "k" })
    local function ParseAttackIds(script)
        if AttackIdsCache[script] then return AttackIdsCache[script] end
        local src = ""
        pcall(function() src = script.Source end)
        if (type(src) ~= "string" or #src == 0) and typeof(decompile) == "function" then
            local ok, d = pcall(decompile, script)
            if ok and type(d) == "string" then src = d end
        end
        local ids = {}
        if type(src) == "string" then
            for name, id in string.gmatch(src, "([%w_]+)%s*=%s*[\"']rbxassetid://(%d+)[\"']") do
                local l = string.lower(name)
                if (string.find(l, "attack", 1, true) or string.find(l, "lunge", 1, true)) and not string.find(l, "spear", 1, true) then
                    ids[id] = name
                end
            end
        end
        AttackIdsCache[script] = ids
        return ids
    end
    ESPUI.ParseAttackIds = ParseAttackIds -- для тестов

    -- [v38] ID ударов, снятые AnimLogger'ом (у своего персонажа видно имя анимации: lungehold -> attack на клик).
    -- У чужих киллеров имя не приходит (в логе name=Animation), поэтому только по ID. Парри - на старт "attack":
    -- у Slasher удар через ~0.37с после старта (обучение), окна хватает. lungehold не берём - при зажатии
    -- (рывок) удар может прийти намного позже.
    ESPUI.KnownAttacks = {
        ["81963230963908"]  = { Killer = "veil", Name = "attack" },
        ["121216847022485"] = { Killer = "cure", Name = "attack" },
        ["113691709436161"] = { Killer = "slasher", Name = "attack" }, -- Modules.Killers.Slasher.Visuals (SwingBurst)
        -- [v47] зажатие удара (holdTrack). KillerActionController: BasicAttack уходит на сервер В ТОТ ЖЕ миг,
        -- что стартует "attack" - к нам анимация приходит уже после удара. Поэтому парри - во время lungehold.
        ["135002183282873"] = { Killer = "cure", Name = "lungehold" }, -- Cure Animations.lua: lungehold
        ["84926129581106"]  = { Killer = "veil", Name = "lungehold" },
    }
    ESPUI.KnownKillers = {}
    for _, k in pairs(ESPUI.KnownAttacks) do ESPUI.KnownKillers[k.Killer] = true end
    -- [v47] окно парри 0.8с (ParryClient lockDuration), зажатие до maxHold 0.6с x lungeboost (Cure: 0.6).
    -- Жмём через (maxHold*boost - 0.45)с после начала зажатия: окно накрывает и мгновенный, и полный рывок.
    ESPUI.ParryHold = { Window = 0.8, MaxHold = 0.6, LungeWS = 27 } -- (без новых local: главный чанк на пределе)
    function ESPUI.IsHoldName(name) return string.find(string.lower(tostring(name)), "hold", 1, true) ~= nil end

    -- киллер «смотрит» на нас в пределах угла (полный угол; 360 = не проверять).
    -- В AutoDagger угол сравнивался с полным Angle, а конус рисовался с Angle/2 - здесь везде половина.
    local function InParryAngle(kRoot, myPos)
        local full = Options.AutoParry_Angle.Value
        if full >= 360 then return true end
        local look = FlatUnit(kRoot.CFrame.LookVector)
        local toMe = FlatUnit(myPos - kRoot.Position)
        if not look or not toMe then return true end
        return math.deg(math.acos(math.clamp(look:Dot(toMe), -1, 1))) <= full / 2
    end

    DefineFeature({
        Id = "AutoParry_",
        Toggle = "AutoParry_Enabled",
        Seen = setmetatable({}, { __mode = "k" }), -- [track] = { T = когда впервые увидели, Killer = модель }
        Fired = setmetatable({}, { __mode = "k" }), -- [track] = true: по этой анимации уже парировали
        Holds = setmetatable({}, { __mode = "k" }), -- [v47] [track lungehold] = { T, E, Name }
        KHist = setmetatable({}, { __mode = "k" }), -- [v58] [модель киллера] = { T, D, C } для скорости сближения
        Hooks = {}, -- [модель киллера] = { Conn, Ids, Animator }

        -- [v34] событие AnimationPlayed у аниматора киллера + ID атак из его скрипта Animations
        HookKiller = function(self, e)
            local h = self.Hooks[e.Model]
            local animator = e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
            if h and h.Animator == animator and (h.Ids or h.Parsing) then return end
            if h and h.Conn then h.Conn:Disconnect() end
            h = { Animator = animator }
            self.Hooks[e.Model] = h
            local anims = e.Model:FindFirstChild("Animations")
            if anims then
                h.Parsing = true
                task.spawn(function()
                    local ids = ParseAttackIds(anims)
                    h.Ids, h.Parsing = ids, false
                    if Toggles.AutoParry_Log.Value then
                        local n = 0 for _ in pairs(ids) do n += 1 end
                        print(string.format("[%s] auto parry: %d attack anims read from %s.Animations", CONFIG.ScriptName, n, e.Name))
                    end
                end)
            end
            if animator then
                h.Conn = animator.AnimationPlayed:Connect(function(track)
                    local ids = h.Ids
                    local id = TrackId(track)
                    local known = id and ESPUI.KnownAttacks[id] -- [v38]
                    local name = (ids and id and ids[id]) or (known and known.Killer .. " " .. known.Name)
                    if not name then return end
                    -- [v47] lungehold (и "...hold" из скрипта Animations) - не удар: раньше парри уходило в
                    -- начале зажатия, а удар приходил после окна 0.8с. vm-анимации на персонаже не играют.
                    if ESPUI.IsHoldName(name) then
                        self.Holds[track] = { T = os.clock(), E = e, Name = name }
                    elseif not string.find(string.lower(name), "vm", 1, true) then
                        SafeRun(self, "OnAttack", e, name, track)
                    end
                end)
            end
        end,

        OnAttack = function(self, e, name, track)
            if not IsSurvivorTeam() then return end
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 or not e.Root or not e.Root.Parent then return end
            local dist = (root.Position - e.Root.Position).Magnitude
            if dist > Options.AutoParry_Distance.Value or not InParryAngle(e.Root, root.Position) then return end
            local ok, dagger = self:CanParry(char, root, hum)
            if not ok then return end
            self.Fired[track] = true
            self:Fire(char, root, hum, dagger, e, "attack " .. tostring(name), dist)
        end,

        Update = function(self)
            local seen = {}
            for _, e in ipairs(Targets.Killers) do
                seen[e.Model] = true
                self:HookKiller(e)
            end
            for model, h in pairs(self.Hooks) do
                if not seen[model] then
                    if h.Conn then h.Conn:Disconnect() end
                    self.Hooks[model] = nil
                end
            end
        end,

        Enable = function(self)
            self.CooldownUntil, self.Permanent, self.LastFire = 0, false, -math.huge
            local folder
            pcall(function() folder = game:GetService("ReplicatedStorage").Remotes.Items["Parrying Dagger"] end)
            self.Folder = folder
            local result = folder and folder:FindFirstChild("parryResult")
            if result then
                self.Maid:Give(result.OnClientEvent:Connect(function(success, cooldown, permanent, clear, character)
                    if character ~= LocalPlayer.Character then return end
                    if clear == true then self.Permanent, self.CooldownUntil = false, 0 return end
                    if permanent == true then self.Permanent = true end
                    local cd = tonumber(cooldown)
                    if cd and cd > 0 then self.CooldownUntil = os.clock() + cd end
                    if Toggles.AutoParry_Log.Value then
                        print(string.format("[%s] parryResult success=%s cooldown=%s permanent=%s", CONFIG.ScriptName,
                            tostring(success), tostring(cooldown), tostring(permanent)))
                    end
                end))
            end
            local function bindHum(char)
                local hum = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))
                if not hum then return end
                self.LastHealth = hum.Health
                self.Maid:Give(hum.HealthChanged:Connect(function(h) SafeRun(self, "OnHealth", h) end))
            end
            self.Maid:Give(LocalPlayer.CharacterAdded:Connect(function(c)
                self.CooldownUntil, self.Permanent = 0, false
                task.spawn(bindHum, c)
            end))
            task.spawn(bindHum, LocalPlayer.Character)
            local name = RandomName()
            RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 2, function()
                SafeRun(self, "Step")
            end)
            self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
        end,

        -- урон по нам: учим анимации ближнего киллера, начатые незадолго до удара
        OnHealth = function(self, h)
            local before = self.LastHealth or h
            self.LastHealth = h
            if h >= before - 0.01 or not IsSurvivorTeam() then return end
            local root = GetRoot(LocalPlayer.Character)
            if not root then return end
            local now, changed = os.clock(), false
            -- [v38] от одного удара учим ОДНУ анимацию - начавшуюся ближе всего к урону (раньше брались все
            -- за 1.5с: от удара Slasher запомнились 3, из них 2 лишние). Известные по ID не учим.
            local best, bestDt, bestKiller
            for track, info in pairs(self.Seen) do
                local k = info.Killer
                local kRoot = k and GetRoot(k)
                local dt = now - info.T
                local id = TrackId(track)
                if kRoot and id and not info.Ambient and dt <= LEARN_WINDOW
                    and (kRoot.Position - root.Position).Magnitude <= LEARN_RANGE and (not bestDt or dt < bestDt) then
                    best, bestDt, bestKiller = id, dt, k
                end
            end
            if best and not ESPUI.KnownAttacks[best] then -- ударила известная анимация - учить нечего
                local id, dt, k = best, bestDt, bestKiller
                do
                    do
                        local L = Learned[id]
                        if L then
                            L.delay = (L.delay * L.hits + dt) / (L.hits + 1)
                            L.hits = math.min(L.hits + 1, 20)
                        else
                            Learned[id] = { delay = dt, hits = 1, killer = HudKey(ReadAttr(k, Players:GetPlayerFromCharacter(k), "MorphedKiller")) }
                        end
                        changed = true
                        if Toggles.AutoParry_Log.Value then
                            print(string.format("[%s] learned attack anim %s: hit %.2fs after start", CONFIG.ScriptName, id, Learned[id].delay))
                        end
                    end
                end
            end
            if changed then SaveLearned() end
        end,

        CanParry = function(self, char, root, hum)
            local dagger = char:FindFirstChild("Parrying Dagger")
            -- [v34] как в AutoDagger: в руках = атрибут игрока EquippedItem == "Parrying Dagger"
            if tostring(LocalPlayer:GetAttribute("EquippedItem")) ~= "Parrying Dagger" and not dagger then return false end
            if CollectionService:HasTag(char, "Silenced") then return false end
            if hum.Health < hum.MaxHealth * 0.5 then return false end
            if self.Permanent or os.clock() < self.CooldownUntil then return false end
            if os.clock() - self.LastFire < 1 then return false end -- ждём ответа сервера
            if char:GetAttribute("Trapped") or LocalPlayer:GetAttribute("IsDead")
                or char:GetAttribute("IsCarried") or char:GetAttribute("IsHooked") then return false end
            if CollectionService:HasTag(root, "doing action") then return false end
            local ci = char:FindFirstChild("CheckInterractable")
            if ci then
                for _, a in ipairs(BUSY_ATTRS) do if ci:GetAttribute(a) then return false end end
            end
            return true, dagger
        end,

        -- атакует ли киллер нас прямо сейчас (и запоминаем, когда начались его анимации)
        Threat = function(self, e, myPos)
            local kPos = e.Root.Position
            local dist = (myPos - kPos).Magnitude
            local now = os.clock()
            local animator = dist <= TRACK_RANGE and e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
            local fresh = {}
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local info = self.Seen[track]
                    if not info then
                        -- уже игравшие при первом взгляде (idle, бег) не считаем началом атаки
                        info = { T = now, Killer = e.Model, Ambient = track.TimePosition > SWING_FRESH }
                        self.Seen[track] = info
                    end
                    if not info.Ambient then table.insert(fresh, { Track = track, Age = now - info.T }) end
                end
            end
            if dist > Options.AutoParry_Distance.Value then return nil end
            if not Toggles.AutoParry_Guess.Value then return nil end
            local hook = self.Hooks[e.Model]
            if hook and hook.Ids and next(hook.Ids) then return nil end -- ID атак известны: работает событие
            -- [v38] удар этого киллера известен по ID (событие) -> догадку по любой Action-анимации не используем
            local knownKiller = ESPUI.KnownKillers[HudKey(ReadAttr(e.Model, e.Player, "MorphedKiller"))]
            local toMe = FlatUnit(myPos - kPos)
            local look = FlatUnit(e.Root.CFrame.LookVector)
            if not toMe or not look then return nil end
            if Options.AutoParry_Angle.Value >= 360 and look:Dot(toMe) < 0.35 then return nil end -- догадкам нужен взгляд на нас
            if not InParryAngle(e.Root, myPos) then return nil end
            -- 1) выученная анимация удара: парри ко времени удара
            local early = Options.AutoParry_Early.Value / 1000
            if Toggles.AutoParry_PingComp.Value then early += self:Ping() end -- [v39]
            for _, f in ipairs(fresh) do
                local L = not knownKiller and Learned[TrackId(f.Track) or ""] -- [v38] у известных киллеров - только их ID
                if L and not self.Fired[f.Track] and f.Age <= L.delay + 0.3 and f.Age >= L.delay - early then
                    self.Fired[f.Track] = true
                    return "learned", dist
                end
            end
            -- 2) запасной: рывок или свежая анимация Action (Core - ходьба/idle)
            local v = e.Root.AssemblyLinearVelocity
            if Vector3.new(v.X, 0, v.Z):Dot(toMe) >= LUNGE_SPEED then return "lunge", dist end
            for _, f in ipairs(fresh) do
                local pr = f.Track.Priority
                if not knownKiller and not self.Fired[f.Track] and f.Age <= SWING_FRESH and f.Track.TimePosition <= SWING_FRESH
                    and pr ~= Enum.AnimationPriority.Core and pr.Value >= Enum.AnimationPriority.Action.Value
                    and not Learned[TrackId(f.Track) or ""] then
                    self.Fired[f.Track] = true
                    return "swing", dist
                end
            end
            return nil
        end,

        -- [v39] пинг в секундах (Player:GetNetworkPing), 0 если недоступен
        Ping = function(self)
            local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)
            return (ok and tonumber(p)) or 0
        end,

        -- [v39] Delay (+ ±10мс хуманизации, - пинг) перед нажатием
        Fire = function(self, char, root, hum, dagger, killer, why, dist)
            self.LastFire = os.clock()
            -- [v58] легит: шанс парри и «только если киллер на экране» (не парируем то, чего не видим)
            if math.random() * 100 > Options.AutoParry_Chance.Value then
                if Toggles.AutoParry_Log.Value then print(string.format("[%s] auto parry skipped (chance)", CONFIG.ScriptName)) end
                return
            end
            if Toggles.AutoParry_OnScreen.Value then
                local cam = workspace.CurrentCamera
                -- [v78] фикс: «cam and cam:WorldToViewportPoint()» отдаёт одно значение, on всегда был nil ->
                -- с включённым OnScreen (пресет Legit) автопарри не нажимало никогда
                local sp, on
                if cam then sp, on = cam:WorldToViewportPoint(killer.Root.Position) end
                if not on or not sp or sp.Z <= 0 then
                    self.LastFire = -math.huge -- не считаем это нажатием: вдруг повернёшься
                    return
                end
            end
            local d = Options.AutoParry_Delay.Value / 1000
            -- [v58] реакция: случайно 0..React мс сверху (как у живого человека, каждый раз по-разному)
            d += math.random() * Options.AutoParry_React.Value / 1000
            if Toggles.AutoParry_Humanize.Value then d += (math.random() * 2 - 1) * 0.01 end
            if Toggles.AutoParry_PingComp.Value then d -= self:Ping() end
            if d > 0.001 then
                task.delay(d, function()
                    local c = LocalPlayer.Character
                    local h = c and c:FindFirstChildOfClass("Humanoid")
                    if c ~= char or not h or h.Health <= 0 or not killer.Root or not killer.Root.Parent then return end
                    SafeRun(self, "Press", char, killer, why, dist, d)
                end)
                return
            end
            self:Press(char, killer, why, dist, 0)
        end,

        Press = function(self, char, killer, why, dist, d)
            if Toggles.AutoParry_Log.Value then
                print(string.format("[%s] auto parry: %s, killer %.1f studs, delay %d ms", CONFIG.ScriptName, why, dist, math.floor(d * 1000 + 0.5)))
            end
            local cam = workspace.CurrentCamera
            if Toggles.AutoParry_Face.Value and cam then
                -- игра поворачивает персонажа туда, куда смотрит камера
                local p = cam.CFrame.Position
                local target = Vector3.new(killer.Root.Position.X, p.Y, killer.Root.Position.Z)
                if (target - p).Magnitude > 0.1 then cam.CFrame = CFrame.lookAt(p, target) end
            end
            -- [v34] жмём кнопку предмета игры: клавиша из KeybindsConfig, а если там мышь или ничего -
            -- кнопка мыши как в AutoDagger (SendMouseButtonEvent(..., 1, ...) = правая кнопка)
            local key = GameKey({ "item", "Item", "UseItem" }, nil)
            if key and key.EnumType == Enum.KeyCode then
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, key, false, game)
                    VirtualInputManager:SendKeyEvent(false, key, false, game)
                end)
                return
            end
            local button = 1
            if key == Enum.UserInputType.MouseButton1 then button = 0 elseif key == Enum.UserInputType.MouseButton3 then button = 2 end
            task.spawn(function()
                pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, button, true, game, 0) end)
                task.wait(0.05)
                pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, button, false, game, 0) end)
            end)
        end,

        Step = function(self)
            if not IsSurvivorTeam() then return end
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 then return end
            local ok, dagger = self:CanParry(char, root, hum)
            -- [v47] киллер зажал удар (lungehold): парри, когда он в радиусе и прошло (maxHold*boost - 0.45)с
            local now = os.clock()
            for track, h in pairs(self.Holds) do
                local e = h.E
                if not track.IsPlaying or now - h.T > 3 or not e.Root or not e.Root.Parent then
                    self.Holds[track] = nil
                elseif ok and not self.Fired[track] then
                    local PH = ESPUI.ParryHold
                    -- [v48] без ожидания: короткий тап (0.1с зажатия) иначе не успевали. Длинный рывок начинается
                    -- издалека - парри всё равно сработает только когда киллер уже в радиусе.
                    local wait = Options.AutoParry_HoldWait and Options.AutoParry_HoldWait.Value / 1000 or 0
                    local dist = (root.Position - e.Root.Position).Magnitude
                    local reach = Options.AutoParry_Distance.Value
                    -- [v58] предикт: реальная скорость сближения (по смещению за ~0.15с), а не константа 27.
                    -- Жмём, когда к моменту, как парри дойдёт до сервера (пинг + задержки), киллер будет в радиусе.
                    local kh = self.KHist[e.Model]
                    if not kh or now - kh.T > 0.3 then kh = { T = now, D = dist, C = 0 } self.KHist[e.Model] = kh end
                    if now - kh.T >= 0.15 then
                        kh.C = math.max((kh.D - dist) / (now - kh.T), 0)
                        kh.T, kh.D = now, dist
                    end
                    if Toggles.AutoParry_Predict.Value then
                        local lead = Options.AutoParry_Delay.Value / 1000 + Options.AutoParry_React.Value / 2000
                        if Toggles.AutoParry_PingComp.Value then lead += self:Ping() end
                        reach += math.min(kh.C, PH.LungeWS + 5) * lead
                    elseif Toggles.AutoParry_PingComp.Value then
                        reach += self:Ping() * PH.LungeWS
                    end
                    if now - h.T >= wait and dist <= reach and InParryAngle(e.Root, root.Position) then
                        self.Fired[track] = true
                        self:Fire(char, root, hum, dagger, e, "hold " .. tostring(h.Name), dist)
                        return
                    end
                end
            end
            for _, e in ipairs(Targets.Killers) do
                if e.Root and e.Root.Parent then
                    local why, dist = self:Threat(e, root.Position) -- считаем всегда: и для обучения
                    if why and ok then
                        self:Fire(char, root, hum, dagger, e, why, dist)
                        return
                    end
                end
            end
        end,

        Disable = function(self)
            for _, h in pairs(self.Hooks) do if h.Conn then h.Conn:Disconnect() end end
            table.clear(self.Hooks)
            table.clear(self.Seen)
            table.clear(self.Fired)
            table.clear(self.Holds)
            self.Folder = nil
        end,
    })

    -- [v36] из AutoDagger 1:1 по виду: пунктирный неоновый круг радиуса парри у ног (48 отрезков, 60% длины)
    -- и конус угла перед ближайшим киллером (6 + 6 отрезков краёв, 24 дуги), плавное появление 0.25с.
    -- Раньше были HandleAdornment в CoreGui - в игре их не было видно. Теперь, как в оригинале, детали,
    -- но в папке внутри камеры (только у тебя, не в workspace, лучи их не видят: CanQuery = false).
    -- Показ: включён Auto Parry + Show range / Show angle (как Config.Enabled + ShowParryRange в оригинале).
    local VIZ_ON, VIZ_OFF, VIZ_FADE = 0.15, 1, 0.25
    local function VizPart(folder)
        return New("Part", {
            Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
            Material = Enum.Material.Neon, Transparency = VIZ_OFF, Size = Vector3.new(0.2, 0.2, 1), Parent = folder,
        })
    end
    local function VizFade(set, on)
        if set.Shown == on then return end
        set.Shown = on
        local tw = game:GetService("TweenService")
        for _, part in ipairs(set.Parts) do
            if set.Tweens[part] then set.Tweens[part]:Cancel() end
            local t = tw:Create(part, TweenInfo.new(VIZ_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Transparency = on and VIZ_ON or VIZ_OFF })
            set.Tweens[part] = t
            t:Play()
        end
    end
    local function FeetY(root, hum)
        return root.Position.Y - root.Size.Y / 2 - ((hum and (tonumber(hum.HipHeight) or 0) > 0) and hum.HipHeight or 2) -- [v75] tonumber (мок)
    end

    DefineFeature({
        Id = "AutoParryViz_",
        Toggle = "AutoParry_Enabled",
        Watch = { "AutoParry_Color" },
        Enable = function(self)
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.Maid:Give(folder)
            self.Ring = { Parts = {}, Tweens = {}, Shown = false }
            for i = 1, 48 do self.Ring.Parts[i] = VizPart(folder) end
            self.Cone = { Parts = {}, Tweens = {}, Shown = false, Left = {}, Right = {}, Arc = {} }
            for i = 1, 6 do local p = VizPart(folder) self.Cone.Left[i] = p table.insert(self.Cone.Parts, p) end
            for i = 1, 6 do local p = VizPart(folder) self.Cone.Right[i] = p table.insert(self.Cone.Parts, p) end
            for i = 1, 24 do local p = VizPart(folder) self.Cone.Arc[i] = p table.insert(self.Cone.Parts, p) end
            -- [v75] Threat: внутреннее кольцо «момента» и вспышка при парри (ParryLands растёт - как у Hitsounds)
            self.Inner = {}
            for i = 1, 32 do self.Inner[i] = VizPart(folder) end
            self.Vis, self.InVis, self.FlashAt, self.Prev = 0, 0, -math.huge, {}
            local landsConn
            local function bind(c)
                if landsConn then landsConn:Disconnect() landsConn = nil end
                if not c then return end
                local last = tonumber(c:GetAttribute("ParryLands")) or 0
                landsConn = c:GetAttributeChangedSignal("ParryLands"):Connect(function()
                    local v = tonumber(c:GetAttribute("ParryLands")) or 0
                    if v > last then self.FlashAt = os.clock() end
                    last = v
                end)
            end
            bind(LocalPlayer.Character)
            self.Maid:Give(LocalPlayer.CharacterAdded:Connect(bind))
            self.Maid:Give(function() if landsConn then landsConn:Disconnect() landsConn = nil end end)
            self.LastDraw = os.clock()
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Draw") end))
        end,
        -- [v75] стиль Threat: светлая дуга смотрит на ближайшего киллера и растёт с угрозой (цвет -> красный),
        -- внутреннее кольцо дорастает до края к моменту, когда он войдёт в радиус парри (по скорости сближения),
        -- вспышка + расширение при успешном парри. Прозрачность ведём сами (без твинов VizFade).
        Threat = function(self, root, hum, radius, color, want, dt)
            local now = os.clock()
            for _, tw in pairs(self.Ring.Tweens) do tw:Cancel() end
            table.clear(self.Ring.Tweens)
            self.Ring.Shown = nil
            self.Vis = self.Vis + ((want and 1 or 0) - self.Vis) * math.min(dt * 8, 1)
            local kd, kdir, closing = nil, nil, 0
            if root then
                for _, e in ipairs(Targets.Killers) do
                    if e.Root and e.Root.Parent then
                        local off = Vector3.new(e.Root.Position.X - root.Position.X, 0, e.Root.Position.Z - root.Position.Z)
                        local d = off.Magnitude
                        local pr = self.Prev[e.Model]
                        local cl = (pr and now - pr.T > 0) and (pr.D - d) / (now - pr.T) or 0
                        self.Prev[e.Model] = { D = d, T = now, C = pr and (pr.C or 0) + (cl - (pr.C or 0)) * 0.25 or 0 }
                        if not kd or d < kd then kd, kdir, closing = d, d > 0.05 and off.Unit or nil, self.Prev[e.Model].C end
                    end
                end
            end
            local far = radius * 3
            local f = kd and math.clamp((far - kd) / (far - radius), 0, 1) or 0
            local fl = math.clamp((now - self.FlashAt) / 0.45, 0, 1)
            local flash = fl < 1
            local col = color:Lerp(Color3.fromRGB(255, 60, 60), f)
            if flash then col = Color3.new(1, 1, 1):Lerp(col, fl) end
            local r = radius * (flash and (1 + 0.3 * math.sin(math.pi * fl)) or (1 + (f > 0.85 and 0.03 * math.sin(now * 14) or 0)))
            local n = #self.Ring.Parts
            local step = 2 * math.pi / n
            local c = root and Vector3.new(root.Position.X, FeetY(root, hum) + 0.1, root.Position.Z)
            local ka = kdir and math.atan2(kdir.Z, kdir.X)
            local litHalf = math.pi * math.max(f, kd and 0.12 or 0)
            for i, part in ipairs(self.Ring.Parts) do
                local a = (i - 1) * step
                if c then
                    local pos = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
                    part.Size = Vector3.new(0.18, 0.18, 2 * math.pi * r / n * 0.72)
                    part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
                end
                local lit = ka and math.abs((a - ka + math.pi) % (2 * math.pi) - math.pi) <= litHalf
                part.Color = col
                local base = (lit or flash) and 0.08 or 0.72
                part.Transparency = 1 - (1 - base) * self.Vis
            end
            -- внутреннее кольцо: время до входа в радиус (до 1.5 с) -> радиус от 0 до края
            local ttc = (kd and closing > 3 and kd > radius) and (kd - radius) / closing or nil
            local wantIn = want and ttc ~= nil and ttc < 1.5
            self.InVis = self.InVis + ((wantIn and 1 or 0) - self.InVis) * math.min(dt * 10, 1)
            local ri = radius * (ttc and math.clamp(1 - ttc / 1.5, 0.05, 1) or 1)
            local m = #self.Inner
            for i, part in ipairs(self.Inner) do
                local a = (i - 1) / m * 2 * math.pi
                if c then
                    local pos = c + Vector3.new(math.cos(a) * ri, 0, math.sin(a) * ri)
                    part.Size = Vector3.new(0.12, 0.12, 2 * math.pi * ri / m * 0.5)
                    part.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
                end
                part.Color = Color3.new(1, 1, 1):Lerp(col, 0.5)
                part.Transparency = 1 - 0.75 * self.InVis
            end
        end,
        Draw = function(self)
            local color = Options.AutoParry_Color.Value
            local radius = Options.AutoParry_Distance.Value
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local nowT = os.clock()
            local dt = math.clamp(nowT - (self.LastDraw or nowT), 0, 0.2)
            self.LastDraw = nowT

            -- круг вокруг себя: точки по окружности, отрезок по касательной длиной 60% шага -> пунктир
            local wantRing = Toggles.AutoParry_ShowRange.Value and root ~= nil
            local threat = Options.AutoParry_CircleStyle.Value == "Threat" -- [v75]
            if threat then
                self:Threat(root, hum, radius, color, wantRing, dt)
            else
                if self.Inner then for _, p in ipairs(self.Inner) do p.Transparency = VIZ_OFF end end
            end
            if wantRing and not threat then
                local c = Vector3.new(root.Position.X, FeetY(root, hum) + 0.1, root.Position.Z)
                local n = #self.Ring.Parts
                local step = 2 * math.pi / n
                local len = 2 * math.pi * radius / n * (Options.AutoParry_CircleStyle.Value == "Solid" and 1.05 or 0.6) -- [v39]
                for i, part in ipairs(self.Ring.Parts) do
                    local a = (i - 1) * step
                    local pos = c + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
                    local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
                    part.Size = Vector3.new(0.2, 0.2, len)
                    part.CFrame = CFrame.lookAt(pos, pos + tangent)
                    part.Color = color
                end
            end
            if not threat then VizFade(self.Ring, wantRing) end

            -- конус перед ближайшим киллером: края + дуга (полный угол = Parry angle)
            local full = Options.AutoParry_Angle.Value
            local k, best
            if Toggles.AutoParry_ShowAngle.Value and full < 360 and root then
                for _, e in ipairs(Targets.Killers) do
                    if e.Root and e.Root.Parent then
                        local d = (e.Root.Position - root.Position).Magnitude
                        if not best or d < best then k, best = e, d end
                    end
                end
            end
            local fwd = k and FlatUnit(k.Root.CFrame.LookVector)
            if fwd then
                local half = math.rad(full / 2)
                local c = Vector3.new(k.Root.Position.X, FeetY(k.Root, k.Humanoid) + 0.1, k.Root.Position.Z)
                local function dirAt(a) return CFrame.Angles(0, a, 0):VectorToWorldSpace(fwd) end
                local function lay(parts, from, to)
                    local d = to - from
                    local L = d.Magnitude
                    if L < 0.01 then return end
                    local u = d.Unit
                    for i, part in ipairs(parts) do
                        local pos = from + u * (L * (i - 0.5) / #parts)
                        part.Size = Vector3.new(0.2, 0.2, L / #parts * 0.6)
                        part.CFrame = CFrame.lookAt(pos, pos + u)
                    end
                end
                lay(self.Cone.Left, c, c + dirAt(half) * radius)
                lay(self.Cone.Right, c, c + dirAt(-half) * radius)
                local n = #self.Cone.Arc
                for i, part in ipairs(self.Cone.Arc) do
                    local t = (i - 1) / math.max(n - 1, 1)
                    local dir = dirAt(half - 2 * half * t)
                    local pos = c + dir * radius
                    part.Size = Vector3.new(0.2, 0.2, radius * 2 * half / n * 0.6)
                    part.CFrame = CFrame.lookAt(pos, pos + dirAt(half - 2 * half * t + math.pi / 2))
                end
                for _, part in ipairs(self.Cone.Parts) do part.Color = color end
            end
            VizFade(self.Cone, fwd ~= nil)
        end,
        Disable = function(self)
            self.Ring, self.Cone, self.Inner = nil, nil, nil
        end,
    })

    --------------------------------------------------------
    -- Moonwalk: персонаж смотрит вперёд (по камере), держим S и быстро чередуем A / D -> идёт задом
    --------------------------------------------------------
    DefineFeature({
        Id = "Moonwalk_",
        Toggle = "Moonwalk_Enabled",
        Keys = {},

        SetKeys = function(self, want)
            for key in pairs(self.Keys) do
                if not want[key] then
                    self.Keys[key] = nil
                    pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
                end
            end
            for key in pairs(want) do
                -- [v27] если ты сам нажал и отпустил эту клавишу (например S), игра считает её отпущенной -
                -- жмём заново, иначе мунвок переставал идти назад и только качался влево-вправо
                if not self.Keys[key] or not UserInputService:IsKeyDown(key) then
                    self.Keys[key] = true
                    pcall(function() VirtualInputManager:SendKeyEvent(true, key, false, game) end)
                end
            end
        end,

        Enable = function(self)
            self.Side, self.SwapAt = false, 0
            local name = RandomName()
            RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
                SafeRun(self, "Step")
            end)
            self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
            self.Maid:Give(function()
                self:SetKeys({})
                local hum = self.Hum
                if hum and hum.Parent and self.AutoRotate ~= nil then pcall(function() hum.AutoRotate = self.AutoRotate end) end
                self.Hum, self.AutoRotate = nil, nil
            end)
        end,

        Step = function(self)
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local cam = workspace.CurrentCamera
            if not root or not hum or hum.Health <= 0 or not cam or UserInputService:GetFocusedTextBox() then
                self:SetKeys({})
                return
            end
            if self.Hum ~= hum then
                if self.Hum and self.Hum.Parent and self.AutoRotate ~= nil then pcall(function() self.Hum.AutoRotate = self.AutoRotate end) end
                self.Hum, self.AutoRotate = hum, hum.AutoRotate
            end
            hum.AutoRotate = false
            -- [v27] как при ручном мунвоке (твоё видео): корпус смотрит вперёд (по камере), но покачивается
            -- в сторону шага - с D поворачивается вправо, с A влево, плавно (как AutoRotate игры не успевает
            -- развернуть персонажа при быстром A/D). Раньше он стоял ровно вперёд, как статуя.
            local now = os.clock()
            if now >= self.SwapAt then
                -- [v39] Stutters: иногда на шаге короткая пауза (все клавиши отпущены)
                if Toggles.Moonwalk_Stutter.Value and math.random() < 0.12 then
                    self.StutterUntil = now + 0.05 + math.random() * 0.1
                end
                self.Side = not self.Side
                -- [v35] хуманизация: каждый шаг свой угол (сила ± разброс) и чуть разный темп
                local jitter = Options.Moonwalk_Random.Value
                self.StepAmp = Options.Moonwalk_Sway.Value + (math.random() * 2 - 1) * jitter
                local rate = Options.Moonwalk_Rate.Value / 1000
                self.SwapAt = now + rate * (1 + (math.random() * 2 - 1) * math.min(jitter / 40, 0.3))
            end
            local fwd = FlatUnit(cam.CFrame.LookVector)
            if fwd then
                local amp = math.rad(math.max(self.StepAmp or Options.Moonwalk_Sway.Value, 0))
                local target = self.Side and -amp or amp -- D (Side) -> вправо (по часовой = минус)
                local dt = math.clamp(now - (self.LastStep or now), 0, 0.1)
                self.LastStep = now
                self.Sway = (self.Sway or 0) + (target - (self.Sway or 0)) * math.clamp(dt * 14, 0, 1)
                local look = CFrame.Angles(0, self.Sway, 0):VectorToWorldSpace(fwd)
                root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
            end
            if self.StutterUntil and now < self.StutterUntil then self:SetKeys({}) return end -- [v39]
            self:SetKeys({
                [Enum.KeyCode.S] = true,
                [self.Side and Enum.KeyCode.D or Enum.KeyCode.A] = true,
            })
        end,

        Disable = function(self) end,
    })

    --------------------------------------------------------
    -- Veil: Spear Auto-Aim + место падения своего копья.
    -- Бросок берёт позицию и LookVector КАМЕРЫ в момент отпускания (SpearMath: скорость = clamp(заряд*Speed, 1, Speed), [v82] Speed 165,
    -- старт = камера + dir*3, g = 98.1). Пока заряжаешь, каждый кадр после камеры ставим её взгляд так,
    -- чтобы копьё при текущем заряде попало в цель с упреждением по её скорости.
    --------------------------------------------------------
    local function MyVeil()
        local char = LocalPlayer.Character
        local root = GetRoot(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return nil end
        if not (LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer) then return nil end
        if HudKey(ReadAttr(char, LocalPlayer, "MorphedKiller")) ~= "veil" then return nil end
        return { Model = char, Player = LocalPlayer, Root = root, Humanoid = hum }
    end

    -- направление броска из o со скоростью s в точку, которая движется: p + vel*t
    local function SolveSpear(o, p, vel, s)
        local g = -SPEAR.Gravity.Y
        local dir = (p - o).Magnitude > 1e-3 and (p - o).Unit or nil
        if not dir then return nil end
        -- [v45] в упор: копьё появляется в SpawnOffset (3 ст) перед камерой, но игра проверяет попадание и
        -- на отрезке камера -> точка появления. Цель ближе - просто прямо в неё. Раньше решатель целил из
        -- точки уже ЗА целью: горизонталь ~0 -> угол ~90°, камеру кидало вверх и копьё летело в потолок.
        local direct = dir
        local flatDirect = Vector3.new(p.X - o.X, 0, p.Z - o.Z)
        if (p - o).Magnitude <= SPEAR.SpawnOffset + 2 or flatDirect.Magnitude <= SPEAR.SpawnOffset + 1 then
            return direct, 0
        end
        local t = (p - o).Magnitude / s
        for _ = 1, 5 do
            local start = o + dir * SPEAR.SpawnOffset
            local d = (p + vel * t) - start
            local h = Vector3.new(d.X, 0, d.Z)
            local dx, dy = h.Magnitude, d.Y
            if dx < 0.05 or h:Dot(flatDirect) <= 0 then return direct, 0 end -- точка появления уже за целью
            local s2 = s * s
            local disc = s2 * s2 - g * (g * dx * dx + 2 * dy * s2)
            if disc < 0 then return nil end -- не долетит при таком заряде
            local ang = math.atan((s2 - math.sqrt(disc)) / (g * dx)) -- нижняя (прямая) траектория
            dir = h.Unit * math.cos(ang) + Vector3.new(0, math.sin(ang), 0)
            t = dx / (s * math.cos(ang))
        end
        -- страховка: решение не должно задирать прицел больше чем на 60° над прямой линией на цель
        if math.asin(math.clamp(dir.Y, -1, 1)) - math.asin(math.clamp(direct.Y, -1, 1)) > math.rad(60) then
            return direct, 0
        end
        return dir, t
    end

    local function ChargeSpeed(st)
        local charge = math.max(os.clock() - st.ChargeStart, SPEAR.MinCharge)
        return math.clamp(charge * SPEAR.Speed, 1, SPEAR.Speed)
    end

    DefineFeature({
        Id = "SpearAim_",
        Gate = { "SpearAim_Enabled", "SpearLand_Enabled" },
        Solve = SolveSpear, -- для тестов
        Watch = { "SpearLand_Color" },

        Enable = function(self)
            -- [v36] кольцо места падения: неоновые детали в папке камеры (HandleAdornment в CoreGui в игре не видно).
            -- ring / dot - «прокси» с полями CFrame / Visible / Color3, как были у адорнментов.
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.Maid:Give(folder)
            local function part(size, shape)
                return New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                    CastShadow = false, Material = Enum.Material.Neon, Transparency = 1, Size = size, Shape = shape or Enum.PartType.Block,
                    Parent = folder })
            end
            local R, N = 2.2, 20
            local segs = {}
            for i = 1, N do segs[i] = part(Vector3.new(0.18, 0.18, 2 * math.pi * R / N * 0.75)) end
            local ball = part(Vector3.new(0.6, 0.6, 0.6), Enum.PartType.Ball)
            local ring = setmetatable({}, { __newindex = function(_, k, v)
                if k == "CFrame" then
                    -- плоскость кольца ⟂ LookVector (нормаль поверхности)
                    local u, w = v.RightVector, v.UpVector
                    for i, sp in ipairs(segs) do
                        local a = (i - 1) / N * 2 * math.pi
                        local pos = v.Position + (u * math.cos(a) + w * math.sin(a)) * R
                        sp.CFrame = CFrame.lookAt(pos, pos + (w * math.cos(a) - u * math.sin(a)))
                    end
                elseif k == "Visible" then
                    for _, sp in ipairs(segs) do sp.Transparency = v and 0.1 or 1 end
                elseif k == "Color3" then
                    for _, sp in ipairs(segs) do sp.Color = v end
                end
            end })
            local dot = setmetatable({}, { __newindex = function(_, k, v)
                if k == "CFrame" then ball.CFrame = v
                elseif k == "Visible" then ball.Transparency = v and 0.05 or 1
                elseif k == "Color3" then ball.Color = v end
            end })
            ring.Color3, dot.Color3 = Options.SpearLand_Color.Value, Options.SpearLand_Color.Value
            self.Ring, self.Dot = ring, dot
            self.Folder = folder -- [v65] дуга своего копья (вариант A)
            self.Maid:Give(function() Projectiles.SpearViz.Pool["__self"] = nil end)
            self.PxPerRad, self.NoResp, self.LastCmd = self.PxPerRad or 600, 0, nil
            local name = RandomName()
            RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
                SafeRun(self, "Step")
            end)
            self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
        end,

        Update = function(self)
            if self.Ring then
                local c = Options.SpearLand_Color.Value
                self.Ring.Color3, self.Dot.Color3 = c, c
            end
        end,

        -- [v26] Почему раньше экран дёргало вверх и обратно: скрипт каждый кадр ПЕРЕЗАПИСЫВАЛ камеру, а камера
        -- игры помнит свой поворот и после броска возвращала его -> рывок вверх (подъём под дальность) и назад.
        -- Теперь поворачиваем «мышью» (mousemoverel): двигается сама камера игры, поэтому после броска
        -- взгляд остаётся там, куда навели, и это плавно. Сколько пикселей = радиан, меряем на ходу.
        -- Если мышь камеру не крутит (курсор не захвачен) или функции нет - старый способ, но плавно.
        Aim = function(self, cam, dir)
            local look = cam.CFrame.LookVector
            local function yawOf(v) return math.atan2(-v.X, -v.Z) end
            local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
            local yaw, pitch = yawOf(look), math.asin(math.clamp(look.Y, -1, 1))
            local dYaw = wrap(yawOf(dir) - yaw)
            local dPitch = math.asin(math.clamp(dir.Y, -1, 1)) - pitch
            local f = 1 - Options.SpearAim_Smooth.Value / 100
            local mmr = mousemoverel or (Input and Input.MouseMove)
            if mmr and (self.NoResp or 0) < 10 then
                local last = self.LastCmd
                if last then
                    local movedYaw, movedPitch = wrap(yaw - last.Yaw), pitch - last.Pitch
                    if math.abs(last.X) >= 3 and math.abs(movedYaw) > 1e-4 then
                        local k = -last.X / movedYaw -- мышь вправо -> yaw уменьшается
                        if k > 30 and k < 30000 then self.PxPerRad = self.PxPerRad * 0.7 + k * 0.3 end
                        self.NoResp = 0
                    elseif math.abs(last.Y) >= 3 and math.abs(movedPitch) > 1e-4 then
                        local k = -last.Y / movedPitch
                        if k > 30 and k < 30000 then self.PxPerRad = self.PxPerRad * 0.7 + k * 0.3 end
                        self.NoResp = 0
                    elseif math.abs(last.X) + math.abs(last.Y) >= 3 then
                        self.NoResp = (self.NoResp or 0) + 1
                    end
                end
                local dx = math.clamp(-dYaw * self.PxPerRad * f, -500, 500)
                local dy = math.clamp(-dPitch * self.PxPerRad * f, -500, 500)
                dx, dy = math.floor(dx + 0.5), math.floor(dy + 0.5)
                self.LastCmd = { X = dx, Y = dy, Yaw = yaw, Pitch = pitch }
                if dx ~= 0 or dy ~= 0 then pcall(mmr, dx, dy) end
                return
            end
            -- запасной: поворот камеры напрямую, но плавно
            local p = cam.CFrame.Position
            local want = look:Lerp(dir, math.max(f, 0.05))
            if want.Magnitude > 1e-3 then cam.CFrame = CFrame.lookAt(p, p + want.Unit) end
        end,

        PickTarget = function(self, cam, me)
            local best, bestAng
            local look = cam.CFrame.LookVector
            local fov = math.rad(Options.SpearAim_FOV.Value)
            for _, e in ipairs(Targets.AllSurvivors) do
                if e.Root and e.Root.Parent and e.Model ~= me.Model
                    and not ReadAttr(e.Model, e.Player, "Knocked") and not ReadAttr(e.Model, e.Player, "IsHooked") then
                    local to = e.Root.Position - cam.CFrame.Position
                    if to.Magnitude > 1 then
                        local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
                        if ang <= fov / 2 and (not bestAng or ang < bestAng) then best, bestAng = e, ang end
                    end
                end
            end
            return best
        end,

        Step = function(self)
            local ring, dot = self.Ring, self.Dot
            local cam = workspace.CurrentCamera
            local me = MyVeil()
            local st = me and VeilSpearTrack(me)
            if not cam or not st or not st.ChargeStart then
                if ring then ring.Visible, dot.Visible = false, false end
                local own = Projectiles.SpearViz.Pool["__self"] -- [v65]
                if own then Projectiles.SpearViz.Hide(own) end
                if self.MarkRing then self.MarkRing.Visible = false end -- [v37]
                self.Target, self.LastCmd, self.NoResp, self.TgtVel = nil, nil, 0, nil
                return
            end
            local s = ChargeSpeed(st)
            local camPos = cam.CFrame.Position

            if Toggles.SpearAim_Enabled.Value then
                -- цель держим, пока она в поле зрения (без прыжков между выжившими)
                local tgt = self.Target
                if not (tgt and tgt.Root and tgt.Root.Parent) then tgt = self:PickTarget(cam, me) end
                self.Target = tgt
                -- [v80] для Aim FOV circle / Aim target dots
                ESPUI.AimState = { At = os.clock(), FOV = Options.SpearAim_FOV.Value, List = Targets.AllSurvivors,
                    Target = tgt and tgt.Model, Skip = me.Model }
                if tgt then
                    -- [v29] упреждение: скорость (сглаженная) и направление цели * время полёта копья
                    local vel = Vector3.zero
                    if Toggles.SpearAim_Predict.Value then
                        self.TgtVel = Projectiles.MoveVel(self, tgt.Root) -- [v45] по смещению
                        vel = self.TgtVel * (Options.SpearAim_PredictScale.Value / 100)
                    end
                    -- [v81] Aim at: Body (корень) / Head / Legs
                    local aimAt = tgt.Root.Position
                    local part = Options.SpearAim_Part.Value
                    if part == "Head" then
                        local head = tgt.Model and tgt.Model:FindFirstChild("Head")
                        aimAt = head and head:IsA("BasePart") and head.Position or (aimAt + Vector3.new(0, 1.5, 0))
                    elseif part == "Legs" then
                        aimAt = aimAt - Vector3.new(0, 1.8, 0)
                    end
                    local dir = SolveSpear(camPos, aimAt, vel, s)
                    -- [v37] Legit: камера не трогается, только кружок, куда навести прицел
                    if Options.SpearAim_Mode.Value == "Legit" then
                        Projectiles.Marker(self, cam, dir, Options.SpearLand_Color.Value)
                    else
                        Projectiles.Marker(self, cam, nil)
                        if dir then self:Aim(cam, dir) end
                    end
                elseif self.MarkRing then
                    Projectiles.Marker(self, cam, nil)
                end
            elseif self.MarkRing then
                Projectiles.Marker(self, cam, nil)
            end

            -- [v65] вариант A для своего копья: дуга полёта + кольцо места падения (как у вражеского Veil).
            -- Дуга начинается в 0.08 с полёта, чтобы линия не висела прямо перед камерой.
            local own = self.Folder and Projectiles.SpearViz.Get(self.Folder, "__self")
            if Toggles.SpearLand_Enabled.Value and own then
                local look = cam.CFrame.LookVector
                local hitPos, pts = Projectiles.SpearViz.Draw(own, camPos + look * SPEAR.SpawnOffset, look * s, st.Empowered, 0.08, Options.SpearLand_Color.Value, false)
                -- [v80] Distance + flight time: точка падения и время полёта (последняя точка дуги)
                if hitPos and pts and pts[#pts] then
                    ESPUI.SpearInfo = { At = os.clock(), Pos = hitPos, T = pts[#pts].T, From = me.Root.Position }
                end
                Projectiles.SpearViz.SetDanger(own, nil)
                own.Ball.Transparency = 1
                if ring then ring.Visible, dot.Visible = false, false end
            elseif own then
                Projectiles.SpearViz.Hide(own)
                if ring then ring.Visible, dot.Visible = false, false end
            end
        end,

        Disable = function(self)
            Projectiles.ClearMarker(self) -- [v37]
            self.Ring, self.Dot, self.Target = nil, nil, nil
        end,
    })
end

-- [v37] Butcher Chain Auto-Aim, Flashlight Aim, Parry timers
do
    function Projectiles.HeldRaw(raw)
        if type(raw) == "string" then
            local okK, k = pcall(function() return Enum.KeyCode[raw] end)
            if okK and k then raw = k else
                local okU, u = pcall(function() return Enum.UserInputType[raw] end)
                raw = okU and u or nil
            end
        end
        if typeof(raw) ~= "EnumItem" then return false end
        if raw.EnumType == Enum.KeyCode then return UserInputService:IsKeyDown(raw) end
        if raw.EnumType == Enum.UserInputType then return UserInputService:IsMouseButtonPressed(raw) end
        return false
    end

    function Projectiles.BindStep(self)
        local name = RandomName()
        RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function() SafeRun(self, "Step") end)
        self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
        self.Maid:Give(function() Projectiles.ClearMarker(self) end)
    end

    -- упреждение: сглаженная горизонтальная скорость цели
    -- [v39] видно ли точку: луч без своих/цели, прозрачное (>= 0.5) пропускаем
    function Projectiles.CanSee(from, to, ignore)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { Containers.Root }
        for _, x in ipairs(ignore) do if x then table.insert(filter, x) end end
        local cam = workspace.CurrentCamera
        if cam then table.insert(filter, cam) end
        for _ = 1, 8 do
            rp.FilterDescendantsInstances = filter
            local hit = workspace:Raycast(from, to - from, rp)
            if not hit then return true end
            if hit.Instance.Transparency < 0.5 and hit.Instance.CanCollide then return false end
            table.insert(filter, hit.Instance)
        end
        return true
    end

    -- [v45] скорость цели по РЕАЛЬНОМУ смещению, а не AssemblyLinearVelocity: игра во время починки
    -- генератора держит у выжившего скорость ~16, хотя он стоит - упреждение уводило копьё вбок
    function Projectiles.MoveVel(self, root)
        local now = os.clock()
        local pos = root.Position
        local tr = self.PosTrack
        if not tr or tr.Root ~= root or now - tr.T > 0.5 then
            self.PosTrack = { Root = root, Pos = pos, T = now, V = Vector3.zero }
            return Vector3.zero
        end
        local dt = now - tr.T
        if dt < 1 / 120 then return tr.V end
        local d = pos - tr.Pos
        local raw = Vector3.new(d.X, 0, d.Z) / dt
        if raw.Magnitude > 60 then raw = tr.V end -- рывок/телепорт - не верим
        tr.V = tr.V:Lerp(raw, math.clamp(dt / 0.12, 0, 1))
        tr.Pos, tr.T = pos, now
        return tr.V
    end

    function Projectiles.LeadVel(self, root, on)
        if not on then self.TgtVel, self.PosTrack = nil, nil return Vector3.zero end
        self.TgtVel = Projectiles.MoveVel(self, root)
        return self.TgtVel
    end

    --------------------------------------------------------
    -- Butcher: цепь летит ПРЯМО из головы (ChainProjectile.throwOrigin = Head) со скоростью 140 до 50 стад,
    -- направление броска - взгляд камеры. Наводим взгляд из головы в цель с упреждением dist/140.
    -- Цепь готова: ChainMove1CD = 0 и не ChainInUse (как в HUD Butcher).
    --------------------------------------------------------
    DefineFeature({
        Id = "ChainAim_",
        Toggle = "ChainAim_Enabled",
        Enable = function(self) self.Target = nil Projectiles.BindStep(self) end,
        Step = function(self)
            local cam = workspace.CurrentCamera
            if not cam then return end
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local head = char and char:FindFirstChild("Head")
            local ready = head and hum and hum.Health > 0
                and LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer
                and HudKey(ReadAttr(char, LocalPlayer, "MorphedKiller")) == "butcher"
                and (tonumber(ReadAttr(char, LocalPlayer, "ChainMove1CD")) or 0) <= 0
                and ReadAttr(char, LocalPlayer, "ChainInUse") ~= true
                and not UserInputService:GetFocusedTextBox()
            local range = Projectiles.CHAIN_RANGE + 2
            local tgt = ready and self.Target or nil
            if tgt and not (tgt.Root and tgt.Root.Parent and (tgt.Root.Position - head.Position).Magnitude <= range) then tgt = nil end
            if ready and not tgt then tgt = Projectiles.PickTarget(cam, Options.ChainAim_FOV.Value, range, head.Position) end
            self.Target = tgt
            if not tgt then
                self.LastCmd, self.NoResp, self.TgtVel = nil, 0, nil
                Projectiles.Marker(self, cam, nil)
                return
            end
            local o = head.Position
            local vel = Projectiles.LeadVel(self, tgt.Root, Toggles.ChainAim_Predict.Value)
            local p = tgt.Root.Position
            for _ = 1, 3 do p = tgt.Root.Position + vel * ((p - o).Magnitude / Projectiles.CHAIN_SPEED) end
            local dir = (p - o).Magnitude > 1e-3 and (p - o).Unit or nil
            if not dir then return end
            if Options.ChainAim_Mode.Value == "Legit" then
                Projectiles.Marker(self, cam, dir, Options.AbilityESP_ChainColor.Value)
            else
                Projectiles.Marker(self, cam, nil)
                Projectiles.MouseAim(self, cam, dir, Options.ChainAim_Smooth.Value / 100)
            end
        end,
        Disable = function(self) self.Target, self.LastCmd, self.TgtVel = nil, nil, nil end,
    })

    --------------------------------------------------------
    -- Фонарик (FlashlightClient): светит, пока зажата клавиша предмета (KeybindsConfig "item", по умолчанию ПКМ),
    -- заряд - атрибут "remaining" у детали фонаря. Персонаж поворачивается по взгляду камеры
    -- (SurvivorFacing.request(LookVector)) - поэтому наводим взгляд камеры в голову киллера.
    --------------------------------------------------------
    DefineFeature({
        Id = "FlashAim_",
        Toggle = "FlashAim_Enabled",
        Enable = function(self)
            self.Target = nil
            Projectiles.BindStep(self)
        end,
        FindLight = function(self, char)
            if self.LightChar == char and self.Light and self.Light:IsDescendantOf(char) then return self.Light end
            self.LightChar, self.Light = char, nil
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BasePart") and d:GetAttribute("remaining") ~= nil then self.Light = d break end
            end
            return self.Light
        end,
        Step = function(self)
            local cam = workspace.CurrentCamera
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not cam or not hum or hum.Health <= 0 or UserInputService:GetFocusedTextBox() then self.Target = nil return end
            local team = LocalPlayer.Team
            if not team or not string.find(string.lower(team.Name), "survivor", 1, true) then self.Target = nil return end
            local light = self:FindLight(char)
            local equipped = light ~= nil or tostring(LocalPlayer:GetAttribute("EquippedItem")) == "Flashlight"
            if not equipped or (light and (light:GetAttribute("remaining") or 0) <= 0) then self.Target = nil return end
            if not self.ItemRaw then
                local ok, cfg = pcall(function() return require(game:GetService("ReplicatedStorage").Modules.Survivors.KeybindsConfig) end)
                local raw
                if ok and type(cfg) == "table" and type(cfg.getRaw) == "function" then
                    local okRaw, r = pcall(cfg.getRaw, "item")
                    if okRaw then raw = r end
                end
                self.ItemRaw = raw or "MouseButton2"
            end
            -- [v90] только пока ты сам держишь клавишу предмета (Auto stun убран)
            if not Projectiles.HeldRaw(self.ItemRaw) then
                self.Target, self.LastCmd, self.NoResp = nil, nil, 0
                return
            end
            -- киллер с головой ближе всего к прицелу в пределах FOV (+ [v39] видна ли голова)
            local tgt, bestAng = nil, nil
            local look = cam.CFrame.LookVector
            for _, e in ipairs(Targets.Killers) do
                local head = e.Model and e.Model:FindFirstChild("Head")
                if head and Toggles.FlashAim_WallCheck.Value and not Projectiles.CanSee(cam.CFrame.Position, head.Position, { char, e.Model }) then
                    head = nil
                end
                if head then
                    local to = head.Position - cam.CFrame.Position
                    if to.Magnitude > 1 then
                        local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
                        if ang <= math.rad(Options.FlashAim_FOV.Value) / 2 and (not bestAng or ang < bestAng) then tgt, bestAng = head, ang end
                    end
                end
            end
            self.Target = tgt
            ESPUI.AimState = { At = os.clock(), FOV = Options.FlashAim_FOV.Value, List = Targets.Killers, -- [v80]
                Target = tgt and tgt.Parent }
            if not tgt then return end
            local dir = (tgt.Position - cam.CFrame.Position).Unit
            Projectiles.MouseAim(self, cam, dir, Options.FlashAim_Smooth.Value / 100)
        end,
        Disable = function(self) self.Target, self.LastCmd, self.Light, self.LightChar = nil, nil, nil, nil end,
    })

    --------------------------------------------------------
    -- Кинжалы выживших (ParryClient): парри = анимация useanim кинжала (атрибут модели "Parrying Dagger"),
    -- окно 0.8с (lockDuration). Кулдаун - из parryResult(success, cooldown, permanent, clear, character),
    -- если сервер шлёт его и нам; иначе пишем, сколько секунд назад кинжал использовали.
    --------------------------------------------------------
    DefineFeature({
        Id = "ParryESP_",
        Toggle = "ParryESP_Enabled",
        Watch = { "ParryESP_Color", "ParryESP_TextSize" },
        State = setmetatable({}, { __mode = "k" }), -- [персонаж] = { CdUntil, Permanent, UsedAt, ParryUntil }
        Enable = function(self)
            local folder
            pcall(function() folder = game:GetService("ReplicatedStorage").Remotes.Items["Parrying Dagger"] end)
            local result = folder and folder:FindFirstChild("parryResult")
            if result then
                self.Maid:Give(result.OnClientEvent:Connect(function(success, cooldown, permanent, clear, character)
                    if typeof(character) ~= "Instance" then return end
                    local s = self.State[character] or {}
                    self.State[character] = s
                    if clear == true then s.CdUntil, s.Permanent = nil, false return end
                    if permanent == true then s.Permanent = true end
                    local cd = tonumber(cooldown)
                    if cd and cd > 0 then s.CdUntil = os.clock() + cd end
                end))
            end
            self.Maid:Give(function() Tags.RemoveSlotAll("Parry") end)
        end,
        Update = function(self)
            local keep = {}
            local now = os.clock()
            local color = Options.ParryESP_Color.Value
            local size = Options.ParryESP_TextSize.Value
            for _, e in ipairs(Targets.AllSurvivors) do
                local model = e.Model
                local dagger = model and model:FindFirstChild("Parrying Dagger")
                local s = model and self.State[model]
                local has = dagger or (e.Player and tostring(e.Player:GetAttribute("EquippedItem")) == "Parrying Dagger") or s
                if model and model ~= LocalPlayer.Character and has then
                    s = s or {}
                    self.State[model] = s
                    -- идёт ли анимация парри (useanim кинжала)
                    local useId = dagger and tostring(dagger:GetAttribute("useanim") or ""):match("%d+")
                    local parrying = false
                    local animator = useId and e.Humanoid and e.Humanoid:FindFirstChildOfClass("Animator")
                    if animator then
                        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                            local id = tr.Animation and tostring(tr.Animation.AnimationId):match("%d+")
                            if id == useId then parrying = true break end
                        end
                    end
                    if parrying and not s.WasParry then s.UsedAt = now end
                    s.WasParry = parrying
                    local text, c = nil, color
                    if parrying then
                        text = "PARRY!"
                    elseif s.Permanent then
                        text, c = "Dagger: no parry", Color3.fromRGB(170, 170, 170)
                    elseif s.CdUntil and s.CdUntil > now then
                        text, c = string.format("Dagger %.1fs", s.CdUntil - now), Color3.fromRGB(170, 170, 170)
                    elseif s.UsedAt and not s.CdUntil then
                        text, c = string.format("Dagger used %ds ago", math.floor(now - s.UsedAt)), Color3.fromRGB(200, 200, 200)
                    else
                        text = "Dagger ready"
                    end
                    if text then
                        keep[model] = true
                        Tags.Set(model, "Parry", text, size, c)
                    end
                end
            end
            Tags.PruneSlot("Parry", keep)
        end,
        Disable = function(self) Tags.RemoveSlotAll("Parry") end,
    })

    --------------------------------------------------------
    -- [v39] Fake Dagger: анимация парри кинжала (атрибут useanim / parriedanim у модели "Parrying Dagger"),
    -- но parry:FireServer не шлём. Анимации своего персонажа видят все. Как настоящее парри (ParryClient):
    -- поворот к камере (0.2с), AutoRotate выкл, стоим на месте; поза держится Freeze duration.
    --------------------------------------------------------
    DefineFeature({
        Id = "FakeDagger_",
        Toggle = "FakeDagger_Enabled",
        Tracks = setmetatable({}, { __mode = "k" }), -- [animator] = { [id] = track }
        Enable = function(self)
            self.Busy, self.NextAt = false, 0
            self.Maid:Give(UserInputService.InputBegan:Connect(function(input, gp)
                if gp or UserInputService:GetFocusedTextBox() or Library._Binding then return end
                local want = tostring(Options.FakeDagger_Key.Value)
                local name = input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name
                    or (input.UserInputType == Enum.UserInputType.MouseButton2 and "MB2") or nil
                if name and name == want then task.spawn(SafeRun, self, "Fake") end
            end))
            self.Maid:Give(function() self.Token = (self.Token or 0) + 1 end)
        end,
        -- ID анимации: кинжал в руках / в рюкзаке / у любого выжившего на карте; запоминаем последний
        AnimId = function(self, char)
            local attr = Options.FakeDagger_Preset.Value == "Parry hit" and "parriedanim" or "useanim"
            local places = { char, LocalPlayer:FindFirstChildOfClass("Backpack") }
            for _, e in ipairs(Targets.AllSurvivors) do table.insert(places, e.Model) end
            for _, where in ipairs(places) do
                local d = where and where:FindFirstChild("Parrying Dagger")
                local id = d and tostring(d:GetAttribute(attr) or ""):match("%d+")
                if id then
                    Projectiles.DaggerAnims = Projectiles.DaggerAnims or {}
                    Projectiles.DaggerAnims[attr] = id
                    return id
                end
            end
            return Projectiles.DaggerAnims and Projectiles.DaggerAnims[attr]
        end,
        Fake = function(self)
            local now = os.clock()
            if self.Busy or now < (self.NextAt or 0) then return end
            local team = LocalPlayer.Team
            if not team or not string.find(string.lower(team.Name), "survivor", 1, true) then return end
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if not root or not animator or hum.Health <= 0 then return end
            local id = self:AnimId(char)
            if not id then
                if not self.Warned then
                    self.Warned = true
                    warn("[" .. CONFIG.ScriptName .. "] Fake Dagger: no Parrying Dagger found yet (its animation id comes from the dagger)")
                end
                return
            end
            local cache = self.Tracks[animator] or {}
            self.Tracks[animator] = cache
            local track = cache[id]
            if not track then
                local anim = Instance.new("Animation")
                anim.AnimationId = "rbxassetid://" .. id
                track = animator:LoadAnimation(anim)
                track.Priority = Enum.AnimationPriority.Action
                track.Looped = false
                cache[id] = track
            end
            self.Busy = true
            self.Token = (self.Token or 0) + 1
            local token = self.Token
            local cam = workspace.CurrentCamera
            local face = Toggles.FakeDagger_Face.Value and cam and FlatUnit(cam.CFrame.LookVector)
            local autoRotate, walk = hum.AutoRotate, hum.WalkSpeed
            local speed = Options.FakeDagger_Speed.Value
            local freeze = Options.FakeDagger_Freeze.Value
            hum.AutoRotate = false
            track:Play(0.1, 1, speed)
            local t0 = os.clock()
            local startCF = root.CFrame
            while self.Token == token and os.clock() - t0 < freeze and root.Parent and hum.Health > 0 do
                local t = os.clock() - t0
                hum.WalkSpeed = 0
                if face then
                    local want = CFrame.lookAt(root.Position, root.Position + face)
                    root.CFrame = t < 0.2 and startCF.Rotation:Lerp(want.Rotation, t / 0.2) + root.Position or want
                end
                -- держим позу до конца Freeze: на последнем кадре анимации ставим скорость 0
                if track.Length > 0 and track.TimePosition >= track.Length - 0.06 and track.Speed ~= 0 then track:AdjustSpeed(0) end
                RunService.RenderStepped:Wait()
            end
            pcall(function() track:Stop(0.15) end)
            if hum.Parent then
                hum.WalkSpeed = (hum.WalkSpeed == 0) and walk or hum.WalkSpeed
                hum.AutoRotate = autoRotate
            end
            self.Busy = false
            self.NextAt = os.clock() + Options.FakeDagger_Cooldown.Value
        end,
        Disable = function(self) self.Busy = false end,
    })

    --------------------------------------------------------
    -- [v67] Self Chams: всё твоё тело, только у тебя ([v91] Hand Chams убран)
    --------------------------------------------------------
    DefineFeature({
        Id = "SelfChams_",
        Toggle = "SelfChams_Enabled",
        Watch = { "SelfChams_Color", "SelfChams_Material", "SelfChams_Transparency", "SelfChams_NoTextures", "SelfChams_Accessories",
            "SelfChams_Outline", "SelfChams_OutlineColor", "SelfChams_Aura", "SelfChams_AuraColor", "SelfChams_Trail", "SelfChams_TrailColor",
            "SelfChams_TrailLength", "SelfChams_Rainbow" },
        Saved = {},   -- [part] = { Color, Material, Transparency, TextureID, SA = { {obj, parent} } }
        Props = {},   -- [inst] = { prop = исходное }  (лицо, SpecialMesh.TextureId)
        Moved = {},   -- { {obj, parent} } одежда / скрытые аксессуары
        IsArm = function(self, part)
            local n = string.lower(part.Name)
            if n ~= "handle" and (string.find(n, "arm", 1, true) or string.find(n, "hand", 1, true)) then return true end
            local loc = part:GetAttribute("loc")
            return type(loc) == "string" and string.find(string.lower(loc), "arm", 1, true) ~= nil
        end,
        Hold = function(self, inst, prop, value)
            local p = self.Props[inst]
            if not p then p = {} self.Props[inst] = p end
            if p[prop] == nil then
                local ok, cur = pcall(function() return inst[prop] end)
                if not ok then return end
                p[prop] = cur
            end
            SetIf(inst, prop, value)
        end,
        Move = function(self, obj)
            if obj.Parent then
                table.insert(self.Moved, { obj, obj.Parent })
                obj.Parent = nil
            end
        end,
        RestorePart = function(self, part)
            local s = self.Saved[part]
            if not s then return end
            self.Saved[part] = nil
            pcall(function()
                part.Color, part.Material, part.Transparency = s.Color, s.Material, s.Transparency
                if s.TextureID ~= nil then part.TextureID = s.TextureID end
                for _, sa in ipairs(s.SA) do sa[1].Parent = sa[2] end
            end)
        end,
        RestoreAll = function(self)
            for part in pairs(self.Saved) do self:RestorePart(part) end
            for inst, props in pairs(self.Props) do
                for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
            end
            table.clear(self.Props)
            for i = #self.Moved, 1, -1 do
                local m = self.Moved[i]
                pcall(function() if m[2].Parent then m[1].Parent = m[2] end end)
            end
            table.clear(self.Moved)
        end,
        Color = function(self)
            if Toggles.SelfChams_Rainbow.Value then
                return Color3.fromHSV((os.clock() * Options.SelfChams_RainbowSpeed.Value / 100) % 1, 0.8, 1)
            end
            return Options.SelfChams_Color.Value
        end,
        Enable = function(self)
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.Folder = self.Maid:Give(folder)
            local part = New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                CastShadow = false, Transparency = 1, Size = Vector3.new(2, 4.5, 1.2), Parent = folder })
            local a0 = New("Attachment", { CFrame = CFrame.new(0, 1.6, 0), Parent = part })
            local a1 = New("Attachment", { CFrame = CFrame.new(0, -1.6, 0), Parent = part })
            self.Leash = part
            self.Trail = New("Trail", { Attachment0 = a0, Attachment1 = a1, LightEmission = 1, LightInfluence = 0,
                Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
                MinLength = 0.05, Enabled = false, Parent = part })
            self.Aura = New("ParticleEmitter", { Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1,
                LightInfluence = 0, Rate = 18, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(0.3, 1),
                SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.3, 0), Acceleration = Vector3.new(0, 2, 0),
                Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Enabled = false, Parent = part })
        end,
        Update = function(self)
            local char = LocalPlayer.Character
            local keep = {}
            local color = self:Color()
            local mat = Enum.Material[Options.SelfChams_Material.Value] or Enum.Material.ForceField
            local tr = Options.SelfChams_Transparency.Value / 100
            local noTex = Toggles.SelfChams_NoTextures.Value
            local acc = Options.SelfChams_Accessories.Value
            local handOn = false -- [v91] Hand Chams убран
            -- сменили «что снимать» (одежда / аксессуары / руки) - сначала всё вернуть, потом заново
            local sig = acc .. tostring(noTex) .. tostring(handOn)
            if self.Sig ~= sig then self:RestoreAll() self.Sig = sig end
            if char then
                for _, d in ipairs(char:GetDescendants()) do
                    local inAcc = d:FindFirstAncestorOfClass("Accessory") ~= nil
                    if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not (handOn and self:IsArm(d))
                        and not (inAcc and acc ~= "Chams") then
                        keep[d] = true
                        local s = self.Saved[d]
                        if not s then
                            s = { Color = d.Color, Material = d.Material, Transparency = d.Transparency, SA = {} }
                            if d:IsA("MeshPart") then s.TextureID = d.TextureID end
                            self.Saved[d] = s
                        end
                        if noTex then
                            for _, c in ipairs(d:GetChildren()) do
                                if c:IsA("SurfaceAppearance") then table.insert(s.SA, { c, d }) c.Parent = nil end
                            end
                            if s.TextureID ~= nil then SetIf(d, "TextureID", "") end
                        end
                        SetIf(d, "Color", color)
                        SetIf(d, "Material", mat)
                        local t0 = tonumber(s.Transparency) or 0
                        if t0 < 1 then SetIf(d, "Transparency", math.max(t0, tr)) end
                    elseif noTex and d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
                        self:Hold(d, "Transparency", 1) -- лицо
                    elseif noTex and d:IsA("SpecialMesh") and not d:FindFirstAncestorOfClass("Accessory") then
                        self:Hold(d, "TextureId", "")
                    elseif noTex and (d:IsA("Clothing") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic")) then
                        self:Move(d)
                    elseif acc == "Hide" and d:IsA("Accessory") then
                        self:Move(d)
                    end
                end
            end
            for part in pairs(self.Saved) do
                if not keep[part] then self:RestorePart(part) end
            end
            -- обводка: свой Highlight, занимает 1 место в бюджете подсветки
            local want = Toggles.SelfChams_Outline.Value and char ~= nil
            if want and not (self.HL and self.HL.Parent) then
                self.HL = New("Highlight", { Name = RandomName(), FillTransparency = 1, DepthMode = Enum.HighlightDepthMode.Occluded,
                    Parent = Containers.Highlights })
                HighlightGroup.Reserved += 1
            elseif not want and self.HL then
                pcall(self.HL.Destroy, self.HL)
                self.HL = nil
                HighlightGroup.Reserved = math.max(HighlightGroup.Reserved - 1, 0)
            end
            if self.HL then
                SetIf(self.HL, "Adornee", char)
                SetIf(self.HL, "OutlineColor", Options.SelfChams_OutlineColor.Value)
            end
        end,
        Render = function(self)
            local char = LocalPlayer.Character
            local root = char and GetRoot(char)
            if Toggles.SelfChams_Rainbow.Value then
                local c = self:Color()
                for part in pairs(self.Saved) do SetIf(part, "Color", c) end
            end
            if self.Leash and root then
                self.Leash.CFrame = root.CFrame
                local tOn, aOn = Toggles.SelfChams_Trail.Value, Toggles.SelfChams_Aura.Value
                SetIf(self.Trail, "Enabled", tOn)
                SetIf(self.Aura, "Enabled", aOn)
                if tOn then
                    self.Trail.Color = ColorSequence.new(Toggles.SelfChams_Rainbow.Value and self:Color() or Options.SelfChams_TrailColor.Value)
                    SetIf(self.Trail, "Lifetime", Options.SelfChams_TrailLength.Value)
                end
                if aOn then
                    self.Aura.Color = ColorSequence.new(Toggles.SelfChams_Rainbow.Value and self:Color() or Options.SelfChams_AuraColor.Value)
                end
            end
        end,
        Disable = function(self)
            self:RestoreAll()
            self.Sig = nil
            if self.HL then
                pcall(self.HL.Destroy, self.HL)
                self.HL = nil
                HighlightGroup.Reserved = math.max(HighlightGroup.Reserved - 1, 0)
            end
            self.Leash, self.Trail, self.Aura = nil, nil, nil
        end,
    })

    --------------------------------------------------------
    -- [v40] Hitsounds: 24 звука вшиты как ogg (base64 в HITSOUNDS_DATA). На первом использовании
    -- декодируем base64 -> writefile в папку -> getcustomasset -> SoundId. Звук только у тебя (SoundService).
    --  * Hit   - выживший потерял HP, пока ты рядом киллер (в игре урон по выжившим - твой).
    --  * Down  - выживший перешёл в Knocked.
    --  * Parry - твоё успешное парри (parryResult success / рост ParryLands).
    --------------------------------------------------------
    local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local B64I = {}
    for i = 1, #B64 do B64I[string.byte(B64, i)] = i - 1 end
    local function b64decode(data)
        -- bit32-аккумулятор: держим не больше 8 бит, иначе float теряет точность на длинных строках
        local out, acc, nbits, n = {}, 0, 0, 0
        for i = 1, #data do
            local v = B64I[string.byte(data, i)]
            if v then
                acc = acc * 64 + v
                nbits = nbits + 6
                if nbits >= 8 then
                    nbits = nbits - 8
                    local div = 2 ^ nbits
                    n = n + 1
                    out[n] = string.char(math.floor(acc / div))
                    acc = acc % div -- оставляем только младшие nbits
                end
            end
        end
        return table.concat(out)
    end

    local HS = { Assets = {}, SoundFolder = CONFIG.ScriptName .. "/hitsounds" }
    function HS.Asset(name)
        if HS.Assets[name] ~= nil then return HS.Assets[name] or nil end
        local data = HITSOUNDS_DATA and HITSOUNDS_DATA[name]
        if not data or not (writefile and getcustomasset) then HS.Assets[name] = false return nil end
        local id
        pcall(function()
            if makefolder and isfolder and not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
            if makefolder and isfolder and not isfolder(HS.SoundFolder) then makefolder(HS.SoundFolder) end
            local path = HS.SoundFolder .. "/" .. name:gsub("[^%w _%-]", "_") .. ".ogg"
            if not (isfile and isfile(path)) then writefile(path, b64decode(data)) end
            id = getcustomasset(path)
        end)
        HS.Assets[name] = id or false
        return id
    end
    function HS.Play(name, dmg)
        local id = HS.Asset(name)
        if not id then return end
        local parent = workspace
        pcall(function() parent = game:GetService("SoundService") end)
        local snd = New("Sound", {
            Name = RandomName(), SoundId = id,
            Volume = Options.Hitsound_Volume.Value / 100 * 3,
            PlaybackSpeed = Options.Hitsound_Pitch.Value / 100, Parent = parent,
        })
        if Toggles.Hitsound_PitchByDamage.Value and dmg then
            snd.PlaybackSpeed = snd.PlaybackSpeed * (0.8 + math.clamp(dmg / 60, 0, 1) * 0.7)
        end
        pcall(function() snd:Play() end)
        task.delay(5, function() pcall(function() snd:Destroy() end) end)
    end
    ESPUI.TestHitsound = function() HS.Play(Options.Hitsound_HitSound.Value, 30) end
    ESPUI.HS = HS -- для тестов

    local function AmKiller()
        return LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer
    end

    DefineFeature({
        Id = "Hitsound_",
        Gate = { "Hitsound_Hit", "Hitsound_Down", "Hitsound_Parry" },
        HP = setmetatable({}, { __mode = "k" }),   -- [model] = последнее HP
        Downed = setmetatable({}, { __mode = "k" }), -- [model] = был ли Knocked
        Enable = function(self)
            local folder
            pcall(function() folder = game:GetService("ReplicatedStorage").Remotes.Items["Parrying Dagger"] end)
            local result = folder and folder:FindFirstChild("parryResult")
            -- [v47] звук парри - по росту атрибута ParryLands у своего персонажа (ParryClient: растёт сразу
            -- при успехе). parryResult приходит ~1.5с спустя - он теперь только запасной.
            self.LastParrySound = -math.huge
            local function parried()
                if not Toggles.Hitsound_Parry.Value or os.clock() - self.LastParrySound < 2 then return end
                self.LastParrySound = os.clock()
                HS.Play(Options.Hitsound_ParrySound.Value)
            end
            local landsConn
            local function bind(char)
                if landsConn then landsConn:Disconnect() landsConn = nil end
                if not char then return end
                local last = tonumber(char:GetAttribute("ParryLands")) or 0
                landsConn = char:GetAttributeChangedSignal("ParryLands"):Connect(function()
                    local v = tonumber(char:GetAttribute("ParryLands")) or 0
                    if v > last then parried() end
                    last = v
                end)
            end
            bind(LocalPlayer.Character)
            self.Maid:Give(LocalPlayer.CharacterAdded:Connect(bind))
            self.Maid:Give(function() if landsConn then landsConn:Disconnect() landsConn = nil end end)
            if result then
                self.Maid:Give(result.OnClientEvent:Connect(function(success, cooldown, permanent, clear, character)
                    if success == true and character == LocalPlayer.Character then parried() end
                end))
            end
        end,
        Update = function(self)
            local nearKiller = AmKiller()
            local myRoot = nearKiller and GetRoot(LocalPlayer.Character)
            for _, e in ipairs(Targets.AllSurvivors) do
                local model, hum = e.Model, e.Humanoid
                if model and hum then
                    -- Hit: HP упало
                    local last = self.HP[model]
                    local h = hum.Health
                    if Toggles.Hitsound_Hit.Value and nearKiller and myRoot and last and h < last - 0.5 and h > 0 then
                        HS.Play(Options.Hitsound_HitSound.Value, last - h)
                    end
                    self.HP[model] = h
                    -- Down: переход в Knocked
                    local knocked = ReadAttr(model, e.Player, "Knocked") == true
                    if Toggles.Hitsound_Down.Value and nearKiller and knocked and self.Downed[model] == false then
                        HS.Play(Options.Hitsound_DownSound.Value)
                    end
                    self.Downed[model] = knocked
                end
            end
        end,
        Disable = function(self)
            table.clear(self.HP)
            table.clear(self.Downed)
        end,
    })
end

------------------------------------------------------------
-- [v72] Хит-логи (как у gamesense). Данные те же, что у Hitsounds:
--  * Hit / Down - выживший теряет HP / становится Knocked, пока ты киллер;
--  * Got hit    - падает HP твоего персонажа (или ты Knocked), пока ты выживший;
--  * Hook       - у выжившего (или у тебя) IsHooked false -> true;
--  * Parry      - растёт ParryLands у твоего персонажа;
--  * Stun       - у киллера (или у тебя-киллера) IsStunned false -> true.
-- Своя функция: в главном чанке занято 199 из 200 локалов.
------------------------------------------------------------
;(function()
    local function amKiller() return LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer end
    -- [v75] события нужны и HUD (хитмаркер, урон, статистика): ловим всегда, фильтр Log events - только для строки лога
    local function on() return true end
    local function logOn(ev)
        local v = Options.HitLog_Events.Value
        return type(v) == "table" and v[ev] == true
    end
    local KIND_EV = { hit = "Hit", down = "Down", hurt = "Got hit", downed = "Got hit", hook = "Hook", hooked = "Hook", parry = "Parry", stun = "Stun" }
    ESPUI.HitSubs = ESPUI.HitSubs or {} -- [v75] подписчики: fn(kind, info, model)
    local function nm(e, killer)
        if Library.StreamerMode then return killer and "Killer" or "Player" end
        return e and e.Name or (killer and "Killer" or "?")
    end
    local function n(x) return tostring(math.floor((tonumber(x) or 0) + 0.5)) end
    local function nearestKiller()
        local root = GetRoot(LocalPlayer.Character)
        local best, bd = nil, math.huge
        for _, e in ipairs(Targets.Killers) do
            local d = (root and e.Root) and (e.Root.Position - root.Position).Magnitude or 0
            if d < bd then best, bd = e, d end
        end
        return best
    end
    local function push(kind, parts, info, model)
        local hl = Library.HitLogObj
        if hl and Toggles.HitLog_Enabled.Value and logOn(KIND_EV[kind]) then -- [v75]
            hl.Time = Options.HitLog_Time.Value
            hl:Push(parts)
        end
        for _, fn in ipairs(ESPUI.HitSubs) do pcall(fn, kind, info or {}, model) end -- [v75]
        if ESPUI.LuaEmit then ESPUI.LuaEmit("hit", kind, info or {}) end -- Lua-скрипты: hub.on("hit", fn)
    end
    ESPUI.HitLogPush = push -- для тестов

    DefineFeature({
        Id = "HitLog_",
        Gate = { "HitLog_Enabled", "Hud_Hitmarker", "Hud_DamageNum", "Hud_Stats" }, -- [v75] события нужны и HUD
        HP = setmetatable({}, { __mode = "k" }),
        Down = setmetatable({}, { __mode = "k" }),
        Hook = setmetatable({}, { __mode = "k" }),
        Stun = setmetatable({}, { __mode = "k" }),
        Enable = function(self)
            local function bind(char)
                if self.LandsConn then self.LandsConn:Disconnect() self.LandsConn = nil end
                if not char then return end
                local last = tonumber(char:GetAttribute("ParryLands")) or 0
                self.LandsConn = char:GetAttributeChangedSignal("ParryLands"):Connect(function()
                    local v = tonumber(char:GetAttribute("ParryLands")) or 0
                    if v > last and on("Parry") then
                        local k = nearestKiller()
                        push("parry", { "Parried ", { nm(k, true) } }, { target = k and k.Name })
                    end
                    last = v
                end)
            end
            bind(LocalPlayer.Character)
            self.Maid:Give(LocalPlayer.CharacterAdded:Connect(bind))
            self.Maid:Give(function() if self.LandsConn then self.LandsConn:Disconnect() self.LandsConn = nil end end)
        end,
        -- было / стало по ключу (модель): срабатывает только на переходе, первый кадр - без лога
        Edge = function(self, map, key, now)
            local was = map[key]
            map[key] = now
            return was == false and now == true
        end,
        Update = function(self)
            local killer = amKiller()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            for _, e in ipairs(Targets.AllSurvivors) do
                local model, h = e.Model, e.Humanoid
                if model and h then
                    local last, hp = self.HP[model], h.Health
                    if killer and on("Hit") and last and hp < last - 0.5 and hp > 0 then
                        push("hit", { "Hit ", { nm(e) }, " for ", { n(last - hp) }, " damage (", { n(hp) }, " health remaining)" },
                            { target = e.Name, damage = last - hp, health = hp }, model)
                    end
                    self.HP[model] = hp
                    if self:Edge(self.Down, model, ReadAttr(model, e.Player, "Knocked") == true) and killer and on("Down") then
                        push("down", { "Downed ", { nm(e) } }, { target = e.Name }, model)
                    end
                    if self:Edge(self.Hook, model, ReadAttr(model, e.Player, "IsHooked") == true) and on("Hook") then
                        push("hook", killer and { "Hooked ", { nm(e) } } or { { nm(e) }, " was hooked" }, { target = e.Name })
                    end
                end
            end
            for _, e in ipairs(Targets.Killers) do
                if e.Model and self:Edge(self.Stun, e.Model, ReadAttr(e.Model, e.Player, "IsStunned") == true) and on("Stun") then
                    push("stun", { { nm(e, true) }, " stunned" }, { target = e.Name })
                end
            end
            if char and hum then
                if killer then
                    if self:Edge(self.Stun, char, char:GetAttribute("IsStunned") == true) and on("Stun") then
                        push("stun", { "You were ", { "stunned" } }, {})
                    end
                else
                    local last, hp = self.HP[char], hum.Health
                    if on("Got hit") and last and hp < last - 0.5 then
                        local k = nearestKiller()
                        push("hurt", { "Got hit by ", { nm(k, true) }, " for ", { n(last - hp) }, " damage (", { n(math.max(hp, 0)) }, " health remaining)" },
                            { target = k and k.Name, damage = last - hp, health = hp }, char)
                    end
                    self.HP[char] = hp
                    if self:Edge(self.Down, char, char:GetAttribute("Knocked") == true) and on("Got hit") then
                        local k = nearestKiller()
                        push("downed", { "Downed by ", { nm(k, true) } }, { target = k and k.Name })
                    end
                    if self:Edge(self.Hook, char, char:GetAttribute("IsHooked") == true) and on("Hook") then
                        push("hooked", { "You were ", { "hooked" } }, {})
                    end
                end
            end
        end,
        Disable = function(self)
            table.clear(self.HP) table.clear(self.Down) table.clear(self.Hook) table.clear(self.Stun)
        end,
    })
end)()

------------------------------------------------------------
-- [v75] HUD (Misc > HUD): хитмаркер, цифры урона, компас угрозы, радар, статистика сессии, таймер погони.
-- Данные: события хит-логов (ESPUI.HitSubs), Targets, MapIndex / Collect (генераторы, паллеты, рычаги ворот),
-- KillerHUD.LOS (видит ли киллер). Всё только у тебя на экране. Своя функция: в главном чанке 199 локалов.
------------------------------------------------------------
;(function()
    local HUD = { Stats = { Hits = 0, Downs = 0, Hurt = 0, Parries = 0, Stuns = 0, Chases = 0, ChaseTime = 0, Longest = 0 }, Born = os.clock() }
    ESPUI.Hud = HUD
    function ESPUI.ResetStats()
        for k in pairs(HUD.Stats) do HUD.Stats[k] = 0 end
        HUD.Born = os.clock()
    end
    local function amKiller() return LocalPlayer.Team and LocalPlayer.Team.Name == CONFIG.Teams.Killer end
    local RED = Color3.fromRGB(255, 60, 60)
    local function center()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        return Vector2.new(vp.X / 2, vp.Y / 2)
    end
    local function subscribe(fn)
        table.insert(ESPUI.HitSubs, fn)
        return function()
            local i = table.find(ESPUI.HitSubs, fn)
            if i then table.remove(ESPUI.HitSubs, i) end
        end
    end
    ESPUI.HitSubs = ESPUI.HitSubs or {}
    local function fmtTime(sec)
        sec = math.max(0, math.floor(sec))
        return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
    end
    local function worldPos(inst)
        if not inst or not inst.Parent then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        local ok, cf = pcall(function() return inst:GetPivot() end)
        return ok and cf and cf.Position or nil
    end

    -- статистика: события
    local function countEvent(kind)
        local S = HUD.Stats
        if kind == "hit" then S.Hits += 1
        elseif kind == "down" then S.Downs += 1
        elseif kind == "hurt" then S.Hurt += 1
        elseif kind == "parry" then S.Parries += 1
        elseif kind == "stun" then S.Stuns += 1 end
    end

    --------------------------------------------------------
    -- хитмаркер: крест из 4 чёрточек у прицела, «подпрыгивает» и гаснет за 0.35 с
    --------------------------------------------------------
    DefineFeature({
        Id = "HudHit_",
        Toggle = "Hud_Hitmarker",
        Enable = function(self)
            self.Gui = self.Maid:Give(NewOverlayGui())
            self.Lines = {}
            for i = 1, 4 do
                self.Lines[i] = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, BackgroundTransparency = 1,
                    Rotation = 45 + 90 * i, Parent = self.Gui })
                New("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 1, Thickness = 1, Parent = self.Lines[i] })
            end
            self.At, self.Color, self.Big = -math.huge, Color3.new(1, 1, 1), false
            self.Maid:Give(subscribe(function(kind)
                local col
                if kind == "hit" then col = Options.Hud_HitmarkerColor.Value
                elseif kind == "down" then col = RED
                elseif kind == "parry" then col = Library.Scheme.AccentColor end
                if col then self.At, self.Color, self.Big = os.clock(), col, kind ~= "hit" end
            end))
            self.Maid:Give(RunService.RenderStepped:Connect(function() SafeRun(self, "Draw") end))
        end,
        Draw = function(self)
            local t = (os.clock() - self.At) / 0.35
            local a = t >= 1 and 1 or t
            local size = Options.Hud_HitmarkerSize.Value * (self.Big and 1.4 or 1)
            local pop = 1 + 0.35 * math.max(0, 1 - t * 4)
            local c = center()
            for i, f in ipairs(self.Lines) do
                local ang = math.rad(45 + 90 * i)
                local dist = size * 0.5 + size * 0.45 * pop
                f.Position = UDim2.fromOffset(c.X + math.cos(ang) * dist, c.Y + math.sin(ang) * dist)
                f.Size = UDim2.fromOffset(math.floor(size * 0.7 * pop + 0.5), 2)
                f.Rotation = 45 + 90 * i
                f.BackgroundColor3 = self.Color
                f.BackgroundTransparency = a
                local st = f:FindFirstChildOfClass("UIStroke")
                if st then st.Transparency = math.min(1, a + 0.3) end
            end
        end,
    })

    --------------------------------------------------------
    -- цифры урона: «-25» над головой выжившего, всплывает и гаснет за 0.9 с
    --------------------------------------------------------
    DefineFeature({
        Id = "HudDmg_",
        Toggle = "Hud_DamageNum",
        Enable = function(self)
            self.Gui = self.Maid:Give(NewOverlayGui())
            self.Items = {}
            self.Maid:Give(subscribe(function(kind, info, model)
                if kind ~= "hit" or not model or not info.damage then return end
                if #self.Items >= 12 then pcall(function() table.remove(self.Items, 1).Label:Destroy() end) end
                local l = New("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(60, 20),
                    Text = "-" .. tostring(math.floor(info.damage + 0.5)), TextSize = 16, Font = Enum.Font.SourceSansBold,
                    TextColor3 = Options.Hud_DamageNumColor.Value, TextStrokeTransparency = 0.3, Visible = false, Parent = self.Gui })
                pcall(Library.ApplyESPFont, Library, l)
                local head = model:FindFirstChild("Head")
                local from = (head and head:IsA("BasePart") and head.Position) or worldPos(model) or Vector3.zero
                table.insert(self.Items, { Label = l, Born = os.clock(), From = from + Vector3.new((math.random() - 0.5) * 1.2, 1.2, 0) })
            end))
            self.Maid:Give(function() for _, it in ipairs(self.Items or {}) do pcall(function() it.Label:Destroy() end) end end)
            self.Maid:Give(RunService.RenderStepped:Connect(function() SafeRun(self, "Draw") end))
        end,
        Draw = function(self)
            local cam = workspace.CurrentCamera
            local now = os.clock()
            for i = #self.Items, 1, -1 do
                local it = self.Items[i]
                local t = (now - it.Born) / 0.9
                if t >= 1 or not cam then
                    pcall(function() it.Label:Destroy() end)
                    table.remove(self.Items, i)
                else
                    local p, on = cam:WorldToViewportPoint(it.From + Vector3.new(0, t * 2.2, 0))
                    it.Label.Visible = on and p.Z > 0
                    it.Label.Position = UDim2.fromOffset(p.X, p.Y)
                    it.Label.TextTransparency = t < 0.6 and 0 or (t - 0.6) / 0.4
                    it.Label.TextStrokeTransparency = 0.3 + 0.7 * (t < 0.6 and 0 or (t - 0.6) / 0.4)
                end
            end
        end,
    })

    --------------------------------------------------------
    -- компас угрозы: дуги вокруг прицела в сторону киллеров (и за спиной); ближе - толще и краснее
    --------------------------------------------------------
    DefineFeature({
        Id = "HudCompass_",
        Toggle = "Hud_Compass",
        Enable = function(self)
            self.Gui = self.Maid:Give(NewOverlayGui())
            self.Pool, self.Used = {}, 0
            self.Maid:Give(RunService.RenderStepped:Connect(function() SafeRun(self, "Draw") end))
        end,
        Seg = function(self)
            self.Used += 1
            local f = self.Pool[self.Used]
            if not f then
                f = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = self.Gui })
                self.Pool[self.Used] = f
            end
            f.Visible = true
            return f
        end,
        Draw = function(self)
            self.Used = 0
            local cam = workspace.CurrentCamera
            local root = GetRoot(LocalPlayer.Character)
            if cam and root then
                local list = {}
                for _, e in ipairs(Targets.Killers) do list[#list + 1] = { E = e, Killer = true } end
                if amKiller() and Toggles.Hud_CompassSurv.Value then
                    for _, e in ipairs(Targets.AllSurvivors) do list[#list + 1] = { E = e } end
                end
                local R = Options.Hud_CompassRadius.Value
                local range = Options.Hud_CompassRange.Value
                local far = Options.Hud_CompassColor.Value
                local c = center()
                for _, it in ipairs(list) do
                    local e = it.E
                    if e.Root and e.Root.Parent then
                        local off = e.Root.Position - root.Position
                        local d = Vector3.new(off.X, 0, off.Z).Magnitude
                        if d <= range then
                            local rel = cam.CFrame:VectorToObjectSpace(e.Root.Position - cam.CFrame.Position)
                            local a = math.atan2(rel.X, -rel.Z)
                            local k = 1 - d / range
                            local col = it.Killer and far:Lerp(RED, k) or Color3.fromRGB(90, 225, 130)
                            local span = math.rad(14 + 22 * k)
                            local n = 7
                            for j = 1, n do
                                local aj = a - span / 2 + span * (j - 0.5) / n
                                local f = self:Seg()
                                f.Position = UDim2.fromOffset(c.X + math.sin(aj) * R, c.Y - math.cos(aj) * R)
                                f.Size = UDim2.fromOffset(math.ceil(R * span / n * 0.8), math.floor(2 + 3 * k + 0.5))
                                f.Rotation = math.deg(aj)
                                f.BackgroundColor3 = col
                                f.BackgroundTransparency = 0.55 - 0.45 * k
                            end
                        end
                    end
                end
            end
            for i = self.Used + 1, #self.Pool do self.Pool[i].Visible = false end
        end,
    })

    --------------------------------------------------------
    -- радар: вид сверху, ты в центре (вверх - куда смотрит камера); киллер за краем - прижат к краю
    --------------------------------------------------------
    DefineFeature({
        Id = "HudRadar_",
        Toggle = "Hud_Radar",
        Watch = { "Hud_RadarSize" },
        Enable = function(self)
            local size = Options.Hud_RadarSize.Value
            self.Panel = Library:CreateHudPanel("radar", "radar", size, size + 19, UDim2.new(0, 20, 0.25, 0))
            local body = self.Panel.Body
            if not self.Grid then
                self.Grid = {
                    New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 1, 1, 0),
                        BackgroundColor3 = Color3.fromRGB(45, 45, 45), BorderSizePixel = 0, ZIndex = 31, Parent = body }),
                    New("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1),
                        BackgroundColor3 = Color3.fromRGB(45, 45, 45), BorderSizePixel = 0, ZIndex = 31, Parent = body }),
                }
                self.Me = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(5, 5),
                    BorderSizePixel = 0, ZIndex = 34, Parent = body })
                self.Dots = {}
            end
            self.Panel:SetVisible(true)
            self.ObjAt, self.Objs = 0, {}
            self.Maid:Give(function() if self.Panel then self.Panel:SetVisible(false) end end)
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Draw") end))
        end,
        Update = function(self)
            if self.Panel then
                local size = Options.Hud_RadarSize.Value
                self.Panel:SetSize(size, size + 19)
            end
        end,
        Dot = function(self, i)
            local f = self.Dots[i]
            if not f then
                f = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, ZIndex = 33, Parent = self.Panel.Body })
                New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = f })
                self.Dots[i] = f
            end
            f.Visible = true
            return f
        end,
        Draw = function(self)
            local now = os.clock()
            if now - (self.DrawAt or 0) < 1 / 20 then return end
            self.DrawAt = now
            self.Me.BackgroundColor3 = Library.Scheme.AccentColor
            local root = GetRoot(LocalPlayer.Character)
            local cam = workspace.CurrentCamera
            local n = 0
            if root and cam then
                local show = Options.Hud_RadarShow.Value
                show = type(show) == "table" and show or {}
                -- объекты карты: раз в секунду
                if now - self.ObjAt > 1 then
                    self.ObjAt = now
                    local objs = {}
                    if show.Generators then
                        for _, g in ipairs(Collect.Generators()) do objs[#objs + 1] = { Inst = g, Kind = "Gen" } end
                    end
                    if show.Pallets then
                        for _, p in ipairs(Collect.Pallets()) do objs[#objs + 1] = { Inst = p, Kind = "Pallet" } end
                    end
                    if show["Exit gates"] then
                        for l in pairs(MapIndex.Sets.Levers) do objs[#objs + 1] = { Inst = l, Kind = "Gate" } end
                    end
                    if show.Hooks then -- [v76] точка крюка - HookPoint, иначе центр модели
                        for h in pairs(MapIndex.Sets.Hooks) do
                            if h.Parent then objs[#objs + 1] = { Inst = h:FindFirstChild("HookPoint") or h, Kind = "Hook" } end
                        end
                    end
                    for _, o in ipairs(objs) do o.Pos = worldPos(o.Inst) end
                    self.Objs = objs
                end
                local body = self.Panel.Body.AbsoluteSize
                local half = math.max(math.min(body.X, body.Y) / 2 - 5, 10)
                local range = Options.Hud_RadarRange.Value
                local scale = half / range
                local fwd, right
                if Toggles.Hud_RadarRotate.Value then
                    local lv = cam.CFrame.LookVector
                    fwd = Vector3.new(lv.X, 0, lv.Z)
                    fwd = fwd.Magnitude > 1e-3 and fwd.Unit or Vector3.new(0, 0, -1)
                else
                    fwd = Vector3.new(0, 0, -1)
                end
                right = Vector3.new(-fwd.Z, 0, fwd.X)
                local function place(pos, color, sz, clamp)
                    local off = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
                    local x, y = off:Dot(right) * scale, -off:Dot(fwd) * scale
                    local m = math.max(math.abs(x), math.abs(y))
                    if m > half then
                        if not clamp then return end
                        x, y = x / m * half, y / m * half
                    end
                    n += 1
                    local f = self:Dot(n)
                    f.Position = UDim2.new(0.5, math.floor(x + 0.5), 0.5, math.floor(y + 0.5))
                    f.Size = UDim2.fromOffset(sz, sz)
                    f.BackgroundColor3 = color
                end
                for _, o in ipairs(self.Objs) do
                    if o.Pos then
                        if o.Kind == "Gen" then
                            local v = math.clamp((tonumber(o.Inst:GetAttribute("RepairProgress")) or 0) / 100, 0, 1)
                            place(o.Pos, v >= 1 and Color3.fromRGB(110, 110, 110) or Color3.fromRGB(255, 70, 50):Lerp(Color3.fromRGB(90, 225, 130), v), 5, false)
                        elseif o.Kind == "Pallet" then
                            place(o.Pos, Color3.fromRGB(190, 140, 80), 3, false)
                        elseif o.Kind == "Hook" then
                            -- [v76] занят: рядом (8 ст.) висит выживший (IsHooked)
                            local busy = false
                            for _, e in ipairs(Targets.AllSurvivors) do
                                if e.Root and (e.Root.Position - o.Pos).Magnitude < 8 and ReadAttr(e.Model, e.Player, "IsHooked") == true then busy = true break end
                            end
                            place(o.Pos, busy and Color3.fromRGB(255, 90, 200) or Color3.fromRGB(200, 200, 220), 4, false)
                        else
                            place(o.Pos, Color3.fromRGB(255, 215, 80), 5, false)
                        end
                    end
                end
                if show.Survivors then
                    for _, e in ipairs(Targets.AllSurvivors) do
                        if e.Root and e.Root.Parent then place(e.Root.Position, Color3.fromRGB(90, 160, 255), 4, false) end
                    end
                end
                if show.Killer then
                    for _, e in ipairs(Targets.Killers) do
                        if e.Root and e.Root.Parent then place(e.Root.Position, RED, 7, true) end
                    end
                end
            end
            for i = n + 1, #self.Dots do self.Dots[i].Visible = false end
        end,
    })

    --------------------------------------------------------
    -- погоня (для статистики и индикатора): ближайший киллер видит тебя и сближается (или вплотную);
    -- начало - через 0.75 с, конец - 3 с без условия
    --------------------------------------------------------
    DefineFeature({
        Id = "HudChase_",
        Gate = { "Hud_Chase", "Hud_Stats" },
        Enable = function(self)
            self.On, self.Start, self.Cond, self.Lost, self.Hist, self.ShownText = false, 0, 0, 0, {}, nil
            self.Maid:Give(function()
                if Library.KeybindList then Library.KeybindList:SetStatus("Chase", nil) end
            end)
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Tick") end))
        end,
        Tick = function(self)
            local now = os.clock()
            if now - (self.TickAt or 0) < 0.1 then return end
            local dt = math.min(now - (self.TickAt or now), 0.5)
            self.TickAt = now
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local cond = false
            if root and not amKiller() then
                local best, bd
                for _, e in ipairs(Targets.Killers) do
                    if e.Root and e.Root.Parent then
                        local d = (e.Root.Position - root.Position).Magnitude
                        if not bd or d < bd then best, bd = e, d end
                    end
                end
                if best then
                    local h = self.Hist[best.Model] or {}
                    self.Hist[best.Model] = h
                    table.insert(h, { T = now, D = bd })
                    while #h > 2 and now - h[1].T > 0.5 do table.remove(h, 1) end
                    local closing = (#h > 1 and now - h[1].T > 0) and (h[1].D - bd) / (now - h[1].T) or 0
                    if bd < 45 and (closing > 2 or bd < 14) then
                        local head, myHead = best.Model:FindFirstChild("Head"), char:FindFirstChild("Head")
                        local from = (head and head:IsA("BasePart")) and head.Position or best.Root.Position
                        local to = (myHead and myHead:IsA("BasePart")) and myHead.Position or root.Position
                        local ok, sees = pcall(KillerHUD.LOS, from, to, { best.Model, char })
                        cond = ok and sees == true
                    end
                end
            end
            local S = HUD.Stats
            if cond then
                self.Cond += dt
                self.Lost = 0
                if not self.On and self.Cond >= 0.75 then
                    self.On, self.Start = true, now - self.Cond
                    S.Chases += 1
                end
            else
                self.Cond = 0
                if self.On then
                    self.Lost += dt
                    if self.Lost >= 3 then
                        local len = math.max(0, now - self.Lost - self.Start)
                        S.ChaseTime += len
                        S.Longest = math.max(S.Longest, len)
                        self.On = false
                    end
                end
            end
            HUD.ChaseNow = self.On and (now - self.Start) or nil
            local KL = Library.KeybindList
            local txt = (self.On and Toggles.Hud_Chase.Value) and ("CHASE " .. fmtTime(now - self.Start)) or nil
            if KL and txt ~= self.ShownText then
                self.ShownText = txt
                KL:SetStatus("Chase", txt and { Text = txt, Icon = "ind_timer", Color = Color3.fromRGB(255, 110, 70) } or nil)
            end
        end,
    })

    --------------------------------------------------------
    -- статистика сессии: панель как окно skeet; подписи серым, числа акцентом
    --------------------------------------------------------
    local ROWS = {
        { "Hits", function(S) return S.Hits end }, { "Downs", function(S) return S.Downs end },
        { "Got hit", function(S) return S.Hurt end }, { "Parries", function(S) return S.Parries end },
        { "Stuns", function(S) return S.Stuns end }, { "Chases", function(S) return S.Chases end },
        { "Chase time", function(S) return fmtTime(S.ChaseTime + (HUD.ChaseNow or 0)) end },
        { "Longest chase", function(S) return fmtTime(math.max(S.Longest, HUD.ChaseNow or 0)) end },
        { "Session", function() return fmtTime(os.clock() - HUD.Born) end },
    }
    DefineFeature({
        Id = "HudStats_",
        Toggle = "Hud_Stats",
        Enable = function(self)
            self.Panel = Library:CreateHudPanel("stats", "session", 150, 19 + #ROWS * 15 + 6, UDim2.new(0, 20, 0.55, 0))
            if not self.Labels then
                self.Labels = {}
                for i, r in ipairs(ROWS) do
                    local y = 2 + (i - 1) * 15
                    local name = New("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 15),
                        Text = r[1], TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 150, 150),
                        ZIndex = 33, Parent = self.Panel.Body })
                    local val = New("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 15),
                        Text = "0", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 33, Parent = self.Panel.Body })
                    pcall(function() name.FontFace = self.Panel.Title.FontFace val.FontFace = self.Panel.Title.FontFace end)
                    self.Labels[i] = val
                end
            end
            self.Panel:SetVisible(true)
            self.Maid:Give(subscribe(countEvent))
            self.Maid:Give(function() if self.Panel then self.Panel:SetVisible(false) end end)
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Draw") end))
        end,
        Draw = function(self)
            local now = os.clock()
            if now - (self.DrawAt or 0) < 0.25 then return end
            self.DrawAt = now
            for i, r in ipairs(ROWS) do
                local l = self.Labels[i]
                l.Text = tostring(r[2](HUD.Stats))
                l.TextColor3 = Library.Scheme.AccentColor
            end
        end,
    })
end)()

------------------------------------------------------------
-- [v66] ESP FX: анимированные чамсы (радуга / пульс / цвет по HP), бегущие текстуры, неон-скелет,
-- след за целью, аура, кольцо под ногами, эхо движения (киллер), бектрек (где цель была N мс назад).
-- Всё только визуально и только у тебя на экране. Своя функция: в главном чанке занято 199 из 200 локалов.
------------------------------------------------------------
;(function()
    local FX = HighlightGroup.FX
    -- [v73] вкладки Effects нет: эффекты - в правом групбоксе «... models» каждой подвкладки, у каждой команды свои.
    -- ids: FX<Surv|Killer|Spec|Bot>_<ключ> (старые общие FX_* больше не читаются)
    local SHORT = { Survivors = "Surv", Killer = "Killer", Spectators = "Spec", Bots = "Bot" }
    local function O(team, key)
        local id = "FX" .. (SHORT[team] or "?") .. "_" .. key
        local el = Toggles[id] or Options[id]
        if el then return el.Value end
        return nil
    end
    local GATE, WATCH = {}, {}
    for _, team in ipairs({ "Survivors", "Killer", "Spectators", "Bots" }) do
        local box = ESPUI.ModelBox and ESPUI.ModelBox[team]
        if box then
            local k = "FX" .. SHORT[team] .. "_"
            local killer = team == "Killer"
            box:AddCheckbox(k .. "Enabled", { Text = "Effects", Default = false,
                Tooltip = "Effects below for this team (animated effects cost a bit of FPS)." })
            box:AddDropdown(k .. "ColorMode", { Text = "Color mode", Values = { "Static", "Rainbow", "Health" }, Default = "Static",
                Tooltip = "Static: colors above. Rainbow: hue cycles. Health: green -> red by HP. Used by chams, skeleton and effects." })
                :AddSettings({ Title = "Rainbow", Build = function(g)
                    g:AddSlider(k .. "RainbowSpeed", { Text = "Rainbow speed", Default = 25, Min = 5, Max = 100, Rounding = 0, Suffix = "%" })
                    g:AddSlider(k .. "Saturation", { Text = "Rainbow saturation", Default = 75, Min = 20, Max = 100, Rounding = 0, Suffix = "%" })
                end })
            box:AddCheckbox(k .. "Pulse", { Text = "Pulse", Default = false, Tooltip = "Glow and fill breathe in and out." })
                :AddSettings({ Title = "Pulse", Build = function(g)
                    g:AddSlider(k .. "PulseSpeed", { Text = "Pulse speed", Default = 3, Min = 1, Max = 10, Rounding = 0 })
                    if killer then g:AddCheckbox(k .. "PulseNear", { Text = "Faster when close", Default = true }) end
                end })
            box:AddDropdown(k .. "Texture", { Text = "Moving texture", Values = { "None", "Galaxy", "Grid", "Stripes", "Matrix" }, Default = "None" })
                :AddColorPicker(k .. "TextureColor", { Default = Color3.fromRGB(150, 120, 255), Title = "Texture Color" })
                :AddSettings({ Title = "Moving texture", Build = function(g)
                    g:AddSlider(k .. "TextureSpeed", { Text = "Texture speed", Default = 4, Min = 0, Max = 20, Rounding = 0, Suffix = " st/s" })
                    g:AddSlider(k .. "TextureAlpha", { Text = "Texture transparency", Default = 25, Min = 0, Max = 90, Rounding = 0, Suffix = "%" })
                end })
            box:AddCheckbox(k .. "SkelGlow", { Text = "Neon skeleton", Default = false })
            box:AddCheckbox(k .. "Trail", { Text = "Trail", Default = false })
                :AddColorPicker(k .. "TrailColor", { Default = Color3.fromRGB(255, 70, 70), Title = "Trail Color" })
                :AddSettings({ Title = "Trail", Build = function(g)
                    g:AddSlider(k .. "TrailLength", { Text = "Trail length", Default = 1.5, Min = 0.3, Max = 4, Rounding = 1, Suffix = "s" })
                end })
            box:AddCheckbox(k .. "Aura", { Text = "Aura", Default = false })
                :AddColorPicker(k .. "AuraColor", { Default = Color3.fromRGB(190, 150, 255), Title = "Aura Color" })
                :AddSettings({ Title = "Aura", Build = function(g)
                    g:AddSlider(k .. "AuraRate", { Text = "Aura density", Default = 20, Min = 5, Max = 60, Rounding = 0 })
                end })
            box:AddCheckbox(k .. "Ring", { Text = "Ground ring", Default = false })
                :AddColorPicker(k .. "RingColor", { Default = Color3.fromRGB(147, 197, 57), Title = "Ring Color" })
                :AddSettings({ Title = "Ground ring", Build = function(g)
                    g:AddDropdown(k .. "RingMode", { Text = "Ring color", Values = { "Color", "Distance" }, Default = "Distance" })
                end })
            if killer then
                box:AddCheckbox(k .. "Echo", { Text = "Motion echo", Default = false })
                    :AddColorPicker(k .. "EchoColor", { Default = Color3.fromRGB(255, 60, 60), Title = "Echo Color" })
            end
            box:AddCheckbox(k .. "Backtrack", { Text = "Backtrack", Default = false,
                Tooltip = "Shows where the target was a moment ago (visual only: the game does not let you hit there)." })
                :AddColorPicker(k .. "BacktrackColor", { Default = Color3.fromRGB(80, 200, 255), Title = "Backtrack Color" })
                :AddSettings({ Title = "Backtrack", Build = function(g)
                    g:AddSlider(k .. "BacktrackMs", { Text = "Backtrack time", Default = 200, Min = 50, Max = 500, Rounding = 0, Suffix = "ms" })
                    g:AddDropdown(k .. "BacktrackStyle", { Text = "Backtrack style", Values = { "Ghost", "Ghost trail" }, Default = "Ghost" })
                end })
            GATE[#GATE + 1] = k .. "Enabled"
            for _, w in ipairs({ "Texture", "Trail", "Aura", "Ring", "Echo", "Backtrack" }) do
                if Toggles[k .. w] or Options[k .. w] then WATCH[#WATCH + 1] = k .. w end
            end
        end
    end

    local TEAM_OF = { Killer = "Killer", Surv = "Survivors", Bot = "Bots", Spec = "Spectators" }
    local function teamKey(prefix) return TEAM_OF[string.match(prefix, "^(%a-)[CE]") or ""] end
    local function teamOn(team)
        return team ~= nil and O(team, "Enabled") == true
    end
    FX.TeamOn = function(prefix) return teamOn(teamKey(prefix)) end

    -- цвет эффекта для модели: nil = Static (свой цвет элемента)
    local function colorFor(model, team) -- [v73] настройки своей команды
        local mode = O(team, "ColorMode")
        if mode == "Rainbow" then
            local sp = (O(team, "RainbowSpeed") or 25) / 100
            return Color3.fromHSV((os.clock() * sp) % 1, (O(team, "Saturation") or 75) / 100, 1)
        elseif mode == "Health" then
            local hum = model and model:FindFirstChildOfClass("Humanoid")
            if hum and hum.MaxHealth > 0 then
                return Color3.fromHSV(math.clamp(hum.Health / hum.MaxHealth, 0, 1) * 0.33, 0.85, 1)
            end
        end
        return nil
    end
    FX.ColorFor = colorFor

    local function myPos()
        local c = LocalPlayer.Character
        local r = c and GetRoot(c)
        return r and r.Position
    end

    FX.Style = function(prefix, model, style)
        local team = teamKey(prefix)
        if not teamOn(team) then return style end
        local c = colorFor(model, team)
        local pulse = O(team, "Pulse") == true
        if not c and not pulse then return style end
        local st = table.clone(style)
        if c then st.FillColor, st.OutlineColor = c, c end
        if pulse then
            local k = 1
            if O(team, "PulseNear") and string.find(prefix, "^Killer") then
                local me, root = myPos(), GetRoot(model)
                if me and root then k = 1 + 2 * math.clamp(1 - (root.Position - me).Magnitude / 60, 0, 1) end
            end
            local w = 0.5 + 0.5 * math.sin(os.clock() * (O(team, "PulseSpeed") or 3) * k * 2)
            st.OutlineTransparency = math.clamp(style.OutlineTransparency + (1 - style.OutlineTransparency) * 0.75 * w, 0, 1)
            if style.FillTransparency < 1 then
                st.FillTransparency = math.clamp(style.FillTransparency + (1 - style.FillTransparency) * 0.5 * w, 0, 1)
            end
        end
        return st
    end
    FX.SkelColor = function(prefix, model, base)
        local team = teamKey(prefix)
        return teamOn(team) and colorFor(model, team) or nil
    end
    FX.SkelGlow = function(prefix)
        local team = teamKey(prefix)
        return teamOn(team) and O(team, "SkelGlow") == true
    end

    local LISTS = {
        { Team = "Killer", Get = function() return Targets.Killers end, Killer = true },
        { Team = "Survivors", Get = function() return Targets.Survivors end },
        { Team = "Bots", Get = function() return Targets.Bots end },
        { Team = "Spectators", Get = function() return Targets.Spectators end },
    }
    local TEX = { Galaxy = "fx_galaxy", Grid = "fx_grid", Stripes = "fx_stripes", Matrix = "fx_matrix" }
    local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom }
    local function seq(a, b) return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) }) end
    local function bodyParts(model)
        local out = {}
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and (tonumber(d.Transparency) or 0) < 1 then out[#out + 1] = d end
        end
        return out
    end

    DefineFeature({
        Id = "FX_",
        Gate = GATE, -- [v73] по Effects каждой команды
        Watch = WATCH,

        Enable = function(self)
            local folder = New("Model", { Name = RandomName() })
            pcall(function() folder.Parent = workspace.CurrentCamera end)
            if not folder.Parent then folder.Parent = workspace end
            self.Folder = self.Maid:Give(folder)
            self.Targets, self.Tex, self.Follow, self.Echoes, self.Hist, self.Ghosts = {}, {}, {}, {}, {}, {}
            self.NextEcho, self.TexAt = {}, 0
            self.Ray = RaycastParams.new()
            self.Ray.FilterType = Enum.RaycastFilterType.Exclude
        end,

        Part = function(self, size, shape)
            return New("Part", { Name = RandomName(), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                CastShadow = false, Material = Enum.Material.Neon, Transparency = 1, Size = size,
                Shape = shape or Enum.PartType.Block, Parent = self.Folder })
        end,

        -- кто сейчас под эффектами (раз в UpdateRate)
        Update = function(self)
            local want = {}
            local me = myPos()
            for _, l in ipairs(LISTS) do
                if teamOn(l.Team) then
                    for _, e in ipairs(l.Get()) do
                        if e.Root and (not me or (e.Root.Position - me).Magnitude < 350) then
                            want[e.Model] = { Root = e.Root, Killer = l.Killer == true, Team = l.Team }
                        end
                    end
                end
            end
            self.Targets = want
            -- текстуры: ставим / снимаем
            local function texAsset(team) -- [v73] у каждой команды своя текстура
                local texName = TEX[O(team, "Texture")]
                return texName and Library:GetIcon(texName)
            end
            for model, rec in pairs(self.Tex) do
                local asset = want[model] and texAsset(want[model].Team)
                if not want[model] or not asset or rec.Asset ~= asset then
                    for _, t in ipairs(rec.List) do pcall(t.Destroy, t) end
                    self.Tex[model] = nil
                end
            end
            for model, info in pairs(want) do
                local asset = texAsset(info.Team)
                if asset then
                    if not self.Tex[model] then
                        local rec = { Asset = asset, List = {}, Team = info.Team }
                        for _, p in ipairs(bodyParts(model)) do
                            for _, face in ipairs(FACES) do
                                rec.List[#rec.List + 1] = New("Texture", { Name = RandomName(), Texture = asset, Face = face,
                                    StudsPerTileU = 2.5, StudsPerTileV = 2.5, Parent = p })
                            end
                        end
                        self.Tex[model] = rec
                    end
                end
            end
            -- след / аура / кольцо: «поводок» на каждую цель
            for model, f in pairs(self.Follow) do
                if not want[model] then
                    pcall(f.Part.Destroy, f.Part)
                    for _, sp in ipairs(f.Ring) do pcall(sp.Destroy, sp) end
                    self.Follow[model] = nil
                end
            end
            for model, info in pairs(want) do
                if not self.Follow[model] then
                    local part = self:Part(Vector3.new(2, 4.5, 1.2))
                    local a0 = New("Attachment", { CFrame = CFrame.new(0, 1.6, 0), Parent = part })
                    local a1 = New("Attachment", { CFrame = CFrame.new(0, -1.6, 0), Parent = part })
                    local trail = New("Trail", { Attachment0 = a0, Attachment1 = a1, LightEmission = 1, LightInfluence = 0,
                        Transparency = seq(0.35, 1), MinLength = 0.05, Enabled = false, Parent = part })
                    local em = New("ParticleEmitter", { Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1,
                        LightInfluence = 0, Lifetime = NumberRange.new(0.6, 1.3), Speed = NumberRange.new(0.3, 1.2),
                        SpreadAngle = Vector2.new(180, 180), Size = seq(0.35, 0), Transparency = seq(0.15, 1),
                        Acceleration = Vector3.new(0, 2, 0), Shape = Enum.ParticleEmitterShape.Box,
                        ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Enabled = false, Parent = part })
                    local ring = {}
                    for i = 1, 24 do ring[i] = self:Part(Vector3.new(0.14, 0.14, 0.5)) end
                    self.Follow[model] = { Part = part, Trail = trail, Emitter = em, Ring = ring, Root = info.Root, GroundY = nil, RayAt = 0 }
                end
                self.Follow[model].Root, self.Follow[model].Team = info.Root, info.Team
            end
            -- бектрек / эхо: убрать ушедших
            for model, g in pairs(self.Ghosts) do
                if not want[model] or not O(want[model].Team, "Backtrack") then
                    for _, set in ipairs(g) do for _, p in pairs(set) do pcall(p.Destroy, p) end end
                    self.Ghosts[model] = nil
                end
            end
            for model in pairs(self.Hist) do if not want[model] then self.Hist[model] = nil end end
        end,

        Render = function(self)
            local now = os.clock()
            -- 1. анимированный стиль подсветки и материала - каждый кадр
            for _, g in ipairs(HighlightGroup.All) do
                if g.Prefix and next(g.Map) then
                    local style = g.GetStyle()
                    for adornee, h in pairs(g.Map) do ApplyStyle(h, FX.Style(g.Prefix, adornee, style)) end
                end
            end
            for prefix, fn in pairs(FX.Recolor) do
                local team = teamKey(prefix)
                if teamOn(team) and O(team, "ColorMode") ~= "Static" then fn(function(m) return colorFor(m, team) end) end
            end
            -- 2. бегущие текстуры (30 Гц)
            if now - self.TexAt >= 1 / 30 then
                self.TexAt = now
                for model, rec in pairs(self.Tex) do
                    local sp = O(rec.Team, "TextureSpeed") or 4
                    local tr = (O(rec.Team, "TextureAlpha") or 25) / 100
                    local c = colorFor(model, rec.Team) or O(rec.Team, "TextureColor")
                    local u, v = (now * sp) % 2.5, (now * sp * 0.5) % 2.5
                    for _, t in ipairs(rec.List) do
                        t.OffsetStudsU, t.OffsetStudsV = u, v
                        SetIf(t, "Color3", c)
                        SetIf(t, "Transparency", tr)
                    end
                end
            end
            -- 3. след / аура / кольцо
            local me = myPos()
            for model, f in pairs(self.Follow) do
                local root = f.Root
                if root and root.Parent then
                    f.Part.CFrame = root.CFrame
                    local team = f.Team
                    local base = colorFor(model, team)
                    -- след
                    local trailOn = O(team, "Trail") == true
                    if trailOn then
                        f.Trail.Color = ColorSequence.new(base or O(team, "TrailColor"))
                        SetIf(f.Trail, "Lifetime", O(team, "TrailLength") or 1.5)
                    end
                    SetIf(f.Trail, "Enabled", trailOn)
                    -- аура
                    local auraOn = O(team, "Aura") == true
                    if auraOn then
                        f.Emitter.Color = ColorSequence.new(base or O(team, "AuraColor"))
                        SetIf(f.Emitter, "Rate", O(team, "AuraRate") or 20)
                    end
                    SetIf(f.Emitter, "Enabled", auraOn)
                    -- кольцо под ногами: земля - луч вниз (10 Гц), радиус «дышит»
                    if O(team, "Ring") then
                        if now - f.RayAt > 0.1 then
                            f.RayAt = now
                            local filter = { self.Folder }
                            for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then filter[#filter + 1] = plr.Character end end
                            filter[#filter + 1] = model
                            self.Ray.FilterDescendantsInstances = filter
                            local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), self.Ray)
                            f.GroundY = (hit and hit.Position) and hit.Position.Y or (root.Position.Y - 3)
                        end
                        local c = base or O(team, "RingColor")
                        if not base and O(team, "RingMode") == "Distance" and me then
                            c = Color3.fromHSV(math.clamp(((root.Position - me).Magnitude - 10) / 70, 0, 1) * 0.33, 0.9, 1)
                        end
                        local r = 2.3 + 0.25 * math.sin(now * 3)
                        local center = Vector3.new(root.Position.X, (f.GroundY or root.Position.Y - 3) + 0.08, root.Position.Z)
                        for i, sp in ipairs(f.Ring) do
                            local a = (i - 1) / #f.Ring * 2 * math.pi
                            local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * r
                            sp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
                            sp.Size = Vector3.new(0.14, 0.14, 2 * math.pi * r / #f.Ring * 0.8)
                            sp.Color = c
                            sp.Transparency = 0.15
                        end
                    else
                        for _, sp in ipairs(f.Ring) do sp.Transparency = 1 end
                    end
                end
            end
            -- 4. эхо движения (только киллер): снимок тела раз в 0.15 с, гаснет за 0.6 с
            if O("Killer", "Echo") then
                for model, info in pairs(self.Targets) do
                    if info.Killer and info.Root.Parent and now >= (self.NextEcho[model] or 0) then
                        self.NextEcho[model] = now + 0.15
                        local set = {}
                        local c = colorFor(model, info.Team) or O("Killer", "EchoColor")
                        for _, p in ipairs(bodyParts(model)) do
                            local q = self:Part(p.Size)
                            q.CFrame, q.Color, q.Transparency, q.Material = p.CFrame, c, 0.6, Enum.Material.ForceField
                            set[#set + 1] = q
                        end
                        table.insert(self.Echoes, { Born = now, Parts = set })
                    end
                end
            end
            for i = #self.Echoes, 1, -1 do
                local e = self.Echoes[i]
                local k = (now - e.Born) / 0.6
                if k >= 1 or #self.Echoes - i >= 8 then
                    for _, q in ipairs(e.Parts) do pcall(q.Destroy, q) end
                    table.remove(self.Echoes, i)
                else
                    for _, q in ipairs(e.Parts) do q.Transparency = 0.6 + 0.4 * k end
                end
            end
            -- 5. бектрек: история поз (0.6 с) и «призрак» в прошлом
            do
                for model, info in pairs(self.Targets) do
                  if O(info.Team, "Backtrack") then -- [v73] своя настройка у каждой команды
                    local delay = (O(info.Team, "BacktrackMs") or 200) / 1000
                    local trailMode = O(info.Team, "BacktrackStyle") == "Ghost trail"
                    local h = self.Hist[model]
                    if not h then h = {} self.Hist[model] = h end
                    local snap = { T = now, P = {} }
                    for _, p in ipairs(bodyParts(model)) do snap.P[p] = p.CFrame end
                    h[#h + 1] = snap
                    while #h > 2 and now - h[1].T > 0.6 do table.remove(h, 1) end
                    local c = colorFor(model, info.Team) or O(info.Team, "BacktrackColor")
                    local ghosts = self.Ghosts[model]
                    if not ghosts then ghosts = {} self.Ghosts[model] = ghosts end
                    local count = trailMode and 4 or 1
                    for gi = 1, 4 do
                        local set = ghosts[gi]
                        if gi > count then
                            if set then for _, q in pairs(set) do pcall(q.Destroy, q) end ghosts[gi] = nil end
                        else
                            set = set or {}
                            ghosts[gi] = set
                            local tWant = now - delay * gi / count
                            local rec = h[1]
                            for k = #h, 1, -1 do if h[k].T <= tWant then rec = h[k] break end end
                            local seen = {}
                            for p, cf in pairs(rec.P) do
                                seen[p] = true
                                local q = set[p]
                                if not q then q = self:Part(p.Size) q.Material = Enum.Material.ForceField set[p] = q end
                                q.CFrame, q.Size, q.Color = cf, p.Size, c
                                q.Transparency = 0.45 + 0.4 * (gi - 1) / 4
                            end
                            for p, q in pairs(set) do if not seen[p] then pcall(q.Destroy, q) set[p] = nil end end
                        end
                    end
                  end
                end
            end
        end,

        Disable = function(self)
            for _, rec in pairs(self.Tex or {}) do for _, t in ipairs(rec.List) do pcall(t.Destroy, t) end end
            self.Tex, self.Follow, self.Echoes, self.Ghosts, self.Hist = {}, {}, {}, {}, {}
            -- стили подсветки вернутся сами на следующем ApplyHighlights; материал - на Update своей фичи
        end,
    })
end)()

------------------------------------------------------------
-- [v78] Killer info + косметика (из скрипта конкурента; только визуально / только у тебя)
------------------------------------------------------------
do
    -- Killer info: новый киллер в Targets.Killers -> надпись сверху по центру (ник, персонаж, платформа).
    -- Персонаж: MorphedKiller (KillerTypeText, по дампам), иначе SelectedKiller игрока (дамп: KillerActions).
    -- platform - атрибут игрока (дамп: PromptFactory / CurrencyPopup: "Console", "Mobile", ...).
    DefineFeature({
        Id = "KillerInfo_",
        Toggle = "Hud_KillerInfo",
        Enable = function(self)
            self.Shown = setmetatable({}, { __mode = "k" })
            self.At = -math.huge
            self.Gui = self.Maid:Give(NewOverlayGui())
            self.Label = New("TextLabel", {
                AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(420, 66),
                BackgroundTransparency = 1, RichText = true, Font = Enum.Font.GothamBold, TextSize = 18,
                TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 1, TextTransparency = 1,
                TextYAlignment = Enum.TextYAlignment.Top, Text = "", Parent = self.Gui,
            })
        end,
        Update = function(self)
            local me = LocalPlayer.Team and LocalPlayer.Team.Name
            for _, e in ipairs(Targets.Killers) do
                if not self.Shown[e.Model] then
                    self.Shown[e.Model] = true
                    if me ~= CONFIG.Teams.Killer or Toggles.Hud_KillerInfoKiller.Value then
                        local kt = KillerTypeText(e.Model, e.Player)
                        if kt == "" and e.Player then kt = tostring(e.Player:GetAttribute("SelectedKiller") or "") end
                        local plat = e.Player and e.Player:GetAttribute("platform")
                        local lines = { Escape(Library.StreamerMode and "Killer" or e.Name) }
                        if kt ~= "" then lines[#lines + 1] = RGBTag(Library.Scheme.AccentColor, Escape(kt)) end
                        if plat ~= nil and tostring(plat) ~= "" then lines[#lines + 1] = Escape(tostring(plat)) end
                        self.Label.Text = table.concat(lines, "\n")
                        self.At = os.clock()
                    end
                end
            end
        end,
        Render = function(self)
            if not self.Label then return end
            local t = os.clock() - self.At
            local life = Options.Hud_KillerInfoTime.Value
            local a = 0 -- видимость 0..1: появление 0.3 с, исчезание 0.6 с
            if t >= 0 and t < life then a = math.min(t / 0.3, 1, (life - t) / 0.6) end
            local tr = 1 - math.clamp(a, 0, 1)
            SetIf(self.Label, "TextTransparency", tr)
            SetIf(self.Label, "TextStrokeTransparency", 0.4 + 0.6 * tr)
        end,
        Disable = function(self) self.Gui, self.Label = nil, nil end,
    })

    -- DBD medkit: персонаж.Bandage."Right Arm" -> MeshPartweld + Bandage.MeshPart (структура - по коду конкурента,
    -- в дампах модели бинта в руке нет). Меш / цвет / материал / размер / посадка в руке; при выключении - назад.
    DefineFeature({
        Id = "CosMedkit_",
        Toggle = "Cos_Medkit",
        Kit = { MeshId = "rbxassetid://91599546902559", Color = Color3.fromRGB(170, 0, 0),
            C1 = CFrame.new(-0.2, 0.37, 0), Angle = 0.1, Scale = 0.9 },
        Enable = function(self) self.Saved = setmetatable({}, { __mode = "k" }) end,
        Update = function(self)
            local char = LocalPlayer.Character
            local band = char and char:FindFirstChild("Bandage")
            local arm = band and band:FindFirstChild("Right Arm")
            local weld = arm and arm:FindFirstChild("MeshPartweld")
            local inner = arm and arm:FindFirstChild("Bandage")
            local mp = inner and inner:FindFirstChild("MeshPart")
            if not (weld and mp) or self.Saved[mp] then return end
            local s = { Weld = weld, MeshId = mp.MeshId, Color = mp.Color, Material = mp.Material, Size = mp.Size }
            pcall(function() s.C1 = weld.C1 end)
            pcall(function() s.Angle = weld.DesiredAngle end)
            self.Saved[mp] = s
            if not pcall(function() mp.MeshId = self.Kit.MeshId end) then
                s.Failed = true
                NotifyOnce("medkit", "DBD medkit: this executor can't change MeshId.")
                return
            end
            mp.Color, mp.Material, mp.Size = self.Kit.Color, Enum.Material.Wood, s.Size * self.Kit.Scale
            pcall(function() weld.C1 = self.Kit.C1 end)
            pcall(function() weld.DesiredAngle = self.Kit.Angle end)
        end,
        Disable = function(self)
            for mp, s in pairs(self.Saved or {}) do
                if mp.Parent and not s.Failed then
                    pcall(function()
                        mp.MeshId, mp.Color, mp.Material, mp.Size = s.MeshId, s.Color, s.Material, s.Size
                    end)
                    if s.Weld.Parent then
                        if s.C1 then pcall(function() s.Weld.C1 = s.C1 end) end
                        if s.Angle then pcall(function() s.Weld.DesiredAngle = s.Angle end) end
                    end
                end
            end
            self.Saved = nil
        end,
    })

    -- Triple T: модель rbxassetid://123969132800771 (game:GetObjects) на торсе, своё тело прячется.
    -- Модель создана у тебя - на сервер не уходит. В отличие от оригинала: без скриптов, Massless (не меняет
    -- физику персонажа), все детали приварены к главной (не разваливается).
    DefineFeature({
        Id = "CosTripleT_",
        Toggle = "Cos_TripleT",
        Enable = function(self)
            self.Hidden = {}
            self.Token = {}
            self.Maid:Give(LocalPlayer.CharacterAdded:Connect(function(c)
                self:Remove()
                self.Hidden = {}
                local token = self.Token
                task.delay(0.5, function() if self.Token == token then SafeRun(self, "Apply", c) end end)
            end))
            if LocalPlayer.Character then
                local token, c = self.Token, LocalPlayer.Character
                task.spawn(function() if self.Token == token then SafeRun(self, "Apply", c) end end)
            end
        end,
        Remove = function(self)
            if self.Model then pcall(function() self.Model:Destroy() end) end
            self.Model = nil
        end,
        Apply = function(self, char)
            local torso = char:WaitForChild("Torso", 5) or char:FindFirstChild("UpperTorso")
            if not torso or not Toggles.Cos_TripleT.Value then return end
            local token = self.Token
            local ok, objs = pcall(function() return game:GetObjects("rbxassetid://123969132800771") end)
            if self.Token ~= token or not Toggles.Cos_TripleT.Value then return end
            local model = ok and type(objs) == "table" and objs[1]
            if typeof(model) ~= "Instance" then
                NotifyOnce("triplet", "Triple T: could not load the model (game:GetObjects).")
                return
            end
            local parts = {}
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("LuaSourceContainer") then
                    d:Destroy()
                elseif d:IsA("BasePart") then
                    d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, false, true
                    parts[#parts + 1] = d
                end
            end
            local main = model:IsA("Model") and model.PrimaryPart or parts[1]
            if not main then model:Destroy() return end
            if model:IsA("Model") then model.PrimaryPart = main end
            self:Remove()
            model.Name = RandomName()
            model:PivotTo(torso.CFrame * CFrame.new(0, -0.7, 0))
            for _, p in ipairs(parts) do
                if p ~= main then New("WeldConstraint", { Part0 = main, Part1 = p, Parent = main }) end
            end
            New("WeldConstraint", { Part0 = main, Part1 = torso, Parent = main })
            model.Parent = workspace
            self.Model = model
            -- своё тело: детали, ручки аксессуаров, лицо - прозрачные (как в оригинале)
            local function hide(inst)
                if self.Hidden[inst] == nil then self.Hidden[inst] = inst.Transparency end
                inst.Transparency = 1
            end
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("BasePart") then hide(c)
                elseif c:IsA("Accessory") then
                    local h = c:FindFirstChild("Handle")
                    if h then hide(h) end
                end
            end
            local head = char:FindFirstChild("Head")
            if head then
                for _, c in ipairs(head:GetChildren()) do
                    if c:IsA("Decal") then hide(c) end
                end
            end
        end,
        Disable = function(self)
            self.Token = nil
            self:Remove()
            for inst, t in pairs(self.Hidden or {}) do
                if inst.Parent then pcall(function() inst.Transparency = t end) end
            end
            self.Hidden = nil
        end,
    })
end

------------------------------------------------------------
-- [v80] из Ambient.lua: Auto Crouch, Auto Pallet, Twist of Fate aim, Aim FOV circle / dots / Spear info,
-- Smooth camera, Game aura colors, Hide health bar, Unlock cursor (клавиши игры / визуал / только у тебя)
------------------------------------------------------------
do
    -- нажатие клавиши (или кнопки мыши) игры через VirtualInputManager
    function ESPUI.SendRaw(raw, down)
        local vim = game:GetService("VirtualInputManager")
        if typeof(raw) ~= "EnumItem" then return end
        local button = (raw == Enum.UserInputType.MouseButton1 and 0) or (raw == Enum.UserInputType.MouseButton2 and 1)
            or (raw == Enum.UserInputType.MouseButton3 and 2) or nil
        if button then
            pcall(function() vim:SendMouseButtonEvent(0, 0, button, down, game, 0) end)
        else
            pcall(function() vim:SendKeyEvent(down, raw, false, game) end)
        end
    end

    -- я - живой выживший (не лежу, не на крюке); ближайший киллер и смотрит ли он на меня (60°)
    function ESPUI.MyThreat(maxDist)
        local team = LocalPlayer.Team
        if not team or not string.find(string.lower(team.Name), "survivor", 1, true) then return nil end
        local char = LocalPlayer.Character
        local root = GetRoot(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return nil end
        if ReadAttr(char, LocalPlayer, "Knocked") or ReadAttr(char, LocalPlayer, "IsHooked") or ReadAttr(char, LocalPlayer, "IsCarried") then return nil end
        local best, bestD
        for _, e in ipairs(Targets.Killers) do
            if e.Root and e.Root.Parent then
                local d = (e.Root.Position - root.Position).Magnitude
                if d <= maxDist and (not bestD or d < bestD) then best, bestD = e, d end
            end
        end
        if not best then return { Char = char, Root = root, Hum = hum } end
        local look = best.Root.CFrame.LookVector
        local to = root.Position - best.Root.Position
        local flatL, flatT = Vector3.new(look.X, 0, look.Z), Vector3.new(to.X, 0, to.Z)
        local facing = flatL.Magnitude > 1e-3 and flatT.Magnitude > 1e-3 and flatL.Unit:Dot(flatT.Unit) >= math.cos(math.rad(60))
        return { Char = char, Root = root, Hum = hum, Killer = best, Dist = bestD, Facing = facing }
    end

    -- Auto Crouch: присед игры (SurvivorAnimationsController): держишь клавишу crouch - сидишь
    -- (или по нажатию, если у игрока атрибут crouchtoggle); атрибут персонажа Crouching; только при HP > 50.
    DefineFeature({
        Id = "AutoCrouch_",
        Toggle = "AutoCrouch_Enabled",
        Enable = function(self)
            self.Held, self.Ours, self.PressAt = false, false, 0
            self.Key = ESPUI.GameKey and ESPUI.GameKey({ "crouch" }, Enum.KeyCode.LeftControl) or Enum.KeyCode.LeftControl
            self.Maid:Give(function() self:Set(false, nil) end)
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Tick") end))
        end,
        Tick = function(self)
            local now = os.clock()
            if now - (self.TickAt or 0) < 0.05 then return end
            self.TickAt = now
            local t = ESPUI.MyThreat(Options.AutoCrouch_Radius.Value)
            local want = t ~= nil and t.Killer ~= nil and t.Hum.Health > 50
                and (not Toggles.AutoCrouch_Facing.Value or t.Facing)
            self:Set(want, t and t.Char)
        end,
        Set = function(self, on, char)
            local now = os.clock()
            local crouched = char ~= nil and char:GetAttribute("Crouching") == true
            if LocalPlayer:GetAttribute("crouchtoggle") then
                -- режим «по нажатию»: жмём, пока состояние не совпадёт; поднимаем только если садили мы
                if self.Held then ESPUI.SendRaw(self.Key, false) self.Held = false end
                if not char then self.Ours = false return end
                if (on and not crouched) or (not on and crouched and self.Ours) then
                    if now - self.PressAt >= 0.3 then
                        self.PressAt = now
                        ESPUI.SendRaw(self.Key, true)
                        ESPUI.SendRaw(self.Key, false)
                    end
                end
                if on and crouched then self.Ours = true end
                if not on and not crouched then self.Ours = false end
                return
            end
            -- режим «держать» (по умолчанию)
            if on and char then
                if not self.Held then
                    self.Held, self.PressAt = true, now
                    ESPUI.SendRaw(self.Key, true)
                elseif not crouched and now - self.PressAt >= 0.3 then
                    self.PressAt = now -- не сел (бег, действие) - жмём заново
                    ESPUI.SendRaw(self.Key, false)
                    ESPUI.SendRaw(self.Key, true)
                end
            elseif self.Held then
                self.Held = false
                ESPUI.SendRaw(self.Key, false)
            end
        end,
    })

    -- Auto Pallet: стоишь у стоящей паллеты (PalletState Upright), киллер ближе Killer distance -> клавиша droppallet
    DefineFeature({
        Id = "AutoPallet_",
        Toggle = "AutoPallet_Enabled",
        Enable = function(self)
            self.LastAt, self.Hist = 0, setmetatable({}, { __mode = "k" })
            self.Key = ESPUI.GameKey and ESPUI.GameKey({ "droppallet" }, Enum.KeyCode.Space) or Enum.KeyCode.Space
            self.Maid:Give(RunService.Heartbeat:Connect(function() SafeRun(self, "Tick") end))
        end,
        PalletState = function(self, part)
            local p = part
            for _ = 1, 4 do
                if not p then break end
                local st = p:GetAttribute("PalletState")
                if st ~= nil then return st end
                p = p.Parent
            end
            return nil
        end,
        Tick = function(self)
            local now = os.clock()
            if now - (self.TickAt or 0) < 1 / 30 then return end
            self.TickAt = now
            local radius = Options.AutoPallet_Radius.Value
            local lungeOn = Toggles.AutoPallet_Lunge.Value -- [v81] рывок: ищем киллера на 6 ст. дальше
            local t = ESPUI.MyThreat(radius + (lungeOn and 6 or 0))
            if not t or not t.Killer then return end
            -- сближение: дистанция меньше, чем 0.15 с назад
            local h = self.Hist[t.Killer.Model]
            local closing = h ~= nil and t.Dist < h.D - 0.05
            local speed = (h and now > h.T) and (h.D - t.Dist) / (now - h.T) or 0
            if not h or now - h.T >= 0.15 then self.Hist[t.Killer.Model] = { T = now, D = t.Dist } end
            local lunge = lungeOn and speed >= 22
            if t.Dist > radius and not lunge then return end
            if not lunge then
                if Toggles.AutoPallet_Facing.Value and not t.Facing then return end
                if Toggles.AutoPallet_Closing.Value and not closing then return end
            end
            if now - self.LastAt < 1 then return end
            local reach = Options.AutoPallet_Reach.Value
            for _, part in ipairs(Collect.Pallets()) do
                if part:IsA("BasePart") and (part.Position - t.Root.Position).Magnitude <= reach then
                    local st = self:PalletState(part)
                    if st == nil or st == "Upright" then
                        self.LastAt = now
                        ESPUI.SendRaw(self.Key, true)
                        task.delay(0.05, function() ESPUI.SendRaw(self.Key, false) end)
                        if Toggles.AutoParry_Log and Toggles.AutoParry_Log.Value then
                            print(string.format("[%s] auto pallet: killer %.1f studs", CONFIG.ScriptName, t.Dist))
                        end
                        return
                    end
                end
            end
        end,
    })

    -- Twist of Fate aim: пока целишься (атрибут персонажа Aiming, предмет EquippedItem = Twist of Fate) -
    -- взгляд камеры на ближайшего к прицелу киллера (выстрел игры летит по LookVector камеры)
    DefineFeature({
        Id = "TOFAim_",
        Toggle = "TOFAim_Enabled",
        Enable = function(self)
            self.Target = nil
            Projectiles.BindStep(self)
        end,
        Step = function(self)
            local cam = workspace.CurrentCamera
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not cam or not hum or hum.Health <= 0 or UserInputService:GetFocusedTextBox() then self.Target = nil return end
            if tostring(LocalPlayer:GetAttribute("EquippedItem")) ~= "Twist of Fate" or char:GetAttribute("Aiming") ~= true then
                self.Target, self.LastCmd, self.NoResp = nil, nil, 0
                return
            end
            local look = cam.CFrame.LookVector
            local camPos = cam.CFrame.Position
            local fov = math.rad(Options.TOFAim_FOV.Value) / 2
            local partName = Options.TOFAim_Part.Value
            local best, bestAng, bestModel
            for _, e in ipairs(Targets.Killers) do
                local part = e.Model and (partName == "Head" and e.Model:FindFirstChild("Head")
                    or e.Model:FindFirstChild("Torso") or e.Model:FindFirstChild("UpperTorso") or e.Root)
                if part and part:IsA("BasePart") then
                    if Toggles.TOFAim_WallCheck.Value and not Projectiles.CanSee(camPos, part.Position, { char, e.Model }) then
                        part = nil
                    end
                end
                if part then
                    local to = part.Position - camPos
                    if to.Magnitude > 1 and to.Magnitude <= Options.TOFAim_MaxDist.Value then -- [v81] Max distance
                        local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
                        if ang <= fov and (not bestAng or ang < bestAng) then best, bestAng, bestModel = part, ang, e.Model end
                    end
                end
            end
            self.Target = best
            ESPUI.AimState = { At = os.clock(), FOV = Options.TOFAim_FOV.Value, List = Targets.Killers, Target = bestModel }
            if best then
                Projectiles.MouseAim(self, cam, (best.Position - camPos).Unit, Options.TOFAim_Smooth.Value / 100)
            end
        end,
        Disable = function(self) self.Target, self.LastCmd = nil, nil end,
    })

    -- Aim FOV circle / Aim target dots / Spear distance + flight time: состояние пишут помощники наводки
    -- (ESPUI.AimState от Spear / Flashlight / Twist of Fate, ESPUI.SpearInfo от Spear path + landing)
    DefineFeature({
        Id = "AimFX_",
        Gate = { "AimFX_Circle", "AimFX_Dots", "SpearLand_Info" },
        Enable = function(self)
            self.Gui = self.Maid:Give(NewOverlayGui())
            self.Circle = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
                BackgroundTransparency = 1, Visible = false, Parent = self.Gui })
            New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Circle })
            self.Stroke = New("UIStroke", { Thickness = 1, Transparency = 0.3, Parent = self.Circle })
            self.Dots = {}
            self.Info = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(160, 16), BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3,
                Visible = false, Parent = self.Gui })
        end,
        Dot = function(self, i)
            local d = self.Dots[i]
            if not d then
                d = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Parent = self.Gui })
                New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = d })
                New("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.2, Parent = d })
                self.Dots[i] = d
            end
            return d
        end,
        Render = function(self)
            local cam = workspace.CurrentCamera
            if not cam or not self.Circle then return end
            local now = os.clock()
            local st = ESPUI.AimState
            local live = st ~= nil and now - st.At < 0.15
            -- круг: радиус FOV в пикселях (по вертикальному FOV камеры)
            local showC = live and Toggles.AimFX_Circle.Value
            SetIf(self.Circle, "Visible", showC)
            if showC then
                local vp = cam.ViewportSize
                local half = math.rad(cam.FieldOfView or 70) / 2
                local r = (vp.Y / 2) * math.tan(math.min(math.rad(st.FOV) / 2, math.rad(89))) / math.tan(half)
                r = math.min(r, vp.Magnitude)
                SetIf(self.Circle, "Size", UDim2.fromOffset(math.floor(r * 2 + 0.5), math.floor(r * 2 + 0.5)))
                SetIf(self.Stroke, "Color", Options.AimFX_Color.Value)
            end
            -- точки на головах возможных целей
            local n = 0
            if live and Toggles.AimFX_Dots.Value then
                for _, e in ipairs(st.List or {}) do
                    local head = e.Model and e.Model ~= st.Skip and e.Model:FindFirstChild("Head")
                    if head and head:IsA("BasePart") then
                        local sp, on = cam:WorldToViewportPoint(head.Position)
                        if on and sp.Z > 0 then
                            n += 1
                            local d = self:Dot(n)
                            local tgt = e.Model == st.Target
                            local sz = tgt and 9 or 6
                            d.Position = UDim2.fromOffset(math.floor(sp.X + 0.5), math.floor(sp.Y + 0.5))
                            SetIf(d, "Size", UDim2.fromOffset(sz, sz))
                            SetIf(d, "BackgroundColor3", tgt and Color3.fromRGB(255, 60, 60) or Color3.new(1, 1, 1))
                            SetIf(d, "Visible", true)
                        end
                    end
                end
            end
            for i = n + 1, #self.Dots do SetIf(self.Dots[i], "Visible", false) end
            -- копьё: дистанция до точки падения и время полёта
            local si = ESPUI.SpearInfo
            local showI = Toggles.SpearLand_Info.Value and si ~= nil and now - si.At < 0.15
            if showI then
                local sp, on = cam:WorldToViewportPoint(si.Pos)
                showI = on and sp.Z > 0
                if showI then
                    self.Info.Position = UDim2.fromOffset(math.floor(sp.X + 0.5), math.floor(sp.Y - 10 + 0.5))
                    self.Info.Text = string.format("%s · %.2fs", FormatDist((si.Pos - si.From).Magnitude), si.T or 0)
                    SetIf(self.Info, "TextColor3", Options.SpearLand_Color.Value)
                end
            end
            SetIf(self.Info, "Visible", showI == true)
        end,
        Disable = function(self) self.Gui, self.Circle, self.Stroke, self.Dots, self.Info = nil, nil, nil, nil, nil end,
    })

    -- Smooth camera: держим атрибут CameraStiffness у character.SmoothCamera (дефолт 8), при выключении - назад
    DefineFeature({
        Id = "CamSmooth_",
        Toggle = "Cam_StiffOn", -- [v81] было Cam_Smooth (это id теперь у своей плавной камеры)
        Watch = { "Cam_Stiffness" },
        Enable = function(self) self.Saved = setmetatable({}, { __mode = "k" }) end,
        Update = function(self)
            local char = LocalPlayer.Character
            local sc = char and char:FindFirstChild("SmoothCamera")
            if not sc then return end
            if self.Saved[sc] == nil then self.Saved[sc] = sc:GetAttribute("CameraStiffness") or 8 end
            local v = Options.Cam_Stiffness.Value
            if sc:GetAttribute("CameraStiffness") ~= v then sc:SetAttribute("CameraStiffness", v) end
        end,
        Disable = function(self)
            for sc, v in pairs(self.Saved or {}) do
                if sc.Parent then pcall(function() sc:SetAttribute("CameraStiffness", v) end) end
            end
            self.Saved = nil
        end,
    })

    -- Game aura colors: цвета аур игры - атрибуты LocalPlayer (Highlight-new: genaura / survaura / spikeaura /
    -- leveraura; настройки: killeraura; BloodPoolColor: bloodpoolscolor). Держим свои, при выключении - назад.
    DefineFeature({
        Id = "GameAura_",
        Toggle = "GameAura_Enabled",
        Watch = { "GameAura_Gen", "GameAura_Surv", "GameAura_Hook", "GameAura_Lever", "GameAura_Killer", "GameAura_Blood" },
        Attrs = { genaura = "GameAura_Gen", survaura = "GameAura_Surv", spikeaura = "GameAura_Hook",
            leveraura = "GameAura_Lever", killeraura = "GameAura_Killer", bloodpoolscolor = "GameAura_Blood" },
        Enable = function(self)
            self.Saved = {}
            for attr in pairs(self.Attrs) do
                self.Saved[attr] = { V = LocalPlayer:GetAttribute(attr) }
                self.Maid:Give(LocalPlayer:GetAttributeChangedSignal(attr):Connect(function()
                    local want = Options[self.Attrs[attr]].Value
                    local cur = LocalPlayer:GetAttribute(attr)
                    if cur ~= want then
                        self.Saved[attr].V = cur -- игра поставила своё (загрузились настройки) - вернём его потом
                        LocalPlayer:SetAttribute(attr, want)
                    end
                end))
            end
        end,
        Update = function(self)
            for attr, id in pairs(self.Attrs) do
                local want = Options[id].Value
                if LocalPlayer:GetAttribute(attr) ~= want then LocalPlayer:SetAttribute(attr, want) end
            end
        end,
        Disable = function(self)
            for attr, s in pairs(self.Saved or {}) do pcall(function() LocalPlayer:SetAttribute(attr, s.V) end) end
            self.Saved = nil
        end,
    })

    -- Hide Roblox health bar (CoreGui Health)
    DefineFeature({
        Id = "HideHealth_",
        Toggle = "Hud_HideHealth",
        Enable = function(self)
            local sg = game:GetService("StarterGui")
            local ok, was = pcall(function() return sg:GetCoreGuiEnabled(Enum.CoreGuiType.Health) end)
            self.Was = not ok or was ~= false
            pcall(function() sg:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)
        end,
        Disable = function(self)
            local was = self.Was ~= false
            pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Health, was) end)
        end,
    })

    -- Unlock cursor: каждый кадр после камеры игры мышь свободна и видна (меню открыто - мышью управляет меню)
    DefineFeature({
        Id = "UnlockCursor_",
        Toggle = "Hud_UnlockCursor",
        Enable = function(self)
            local name = RandomName()
            RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value, function()
                if Library.Toggled then return end
                if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then UserInputService.MouseBehavior = Enum.MouseBehavior.Default end
                if not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
            end)
            self.Maid:Give(function() RunService:UnbindFromRenderStep(name) end)
        end,
    })
end

------------------------------------------------------------
-- [v81] из Ambient.lua (2): Smooth camera, Blinded, Anonymous mode, Blur effect, Low graphics
------------------------------------------------------------
do
    -- Smooth camera: после камеры игры сдвигаем камеру к «отстающей» точке P (догоняет корень персонажа:
    -- мёртвая зона, скорость догона, возврат на месте). В начале следующего кадра сдвиг снимаем - камера игры
    -- считает от своего положения и ничего не копится. Только третье лицо (у киллера вид от первого лица).
    DefineFeature({
        Id = "SmoothCam_",
        Toggle = "Cam_Smooth",
        Enable = function(self)
            self.P, self.Applied, self.T = nil, nil, os.clock()
            local undo, step = RandomName(), RandomName()
            RunService:BindToRenderStep(undo, Enum.RenderPriority.First.Value, function()
                local cam = workspace.CurrentCamera
                if self.Applied and cam then cam.CFrame = cam.CFrame - self.Applied end
                self.Applied = nil
            end)
            RunService:BindToRenderStep(step, Enum.RenderPriority.Camera.Value + 5, function() SafeRun(self, "Step") end)
            self.Maid:Give(function()
                RunService:UnbindFromRenderStep(undo)
                RunService:UnbindFromRenderStep(step)
                local cam = workspace.CurrentCamera
                if self.Applied and cam then cam.CFrame = cam.CFrame - self.Applied end
                self.Applied = nil
            end)
        end,
        Step = function(self)
            local now = os.clock()
            local dt = math.clamp(now - (self.T or now), 0, 0.1)
            self.T = now
            local cam = workspace.CurrentCamera
            local char = LocalPlayer.Character
            local root = GetRoot(char)
            local head = char and char:FindFirstChild("Head")
            if not cam or not root or not head or (cam.CFrame.Position - head.Position).Magnitude < 2 then
                self.P = nil
                return
            end
            local target = root.Position
            local P = self.P or target
            local d = target - P
            local dz = Options.Cam_Deadzone.Value
            if d.Magnitude > dz then
                P = P:Lerp(target - d.Unit * dz, 1 - math.exp(-Options.Cam_FollowSpeed.Value * dt))
            end
            local v = root.AssemblyLinearVelocity
            local idle = Options.Cam_IdleReturn.Value
            if idle > 0 and Vector3.new(v.X, 0, v.Z).Magnitude < 1 then
                P = P:Lerp(target, 1 - math.exp(-idle * dt))
            end
            local lag = target - P
            if lag.Magnitude > 8 then P = target - lag.Unit * 8 end -- не дальше 8 ст. (телепорт, респавн)
            self.P = P
            local off = P - target
            if off.Magnitude > 1e-3 then
                cam.CFrame = cam.CFrame + off
                self.Applied = off
            end
        end,
        Disable = function(self) self.P = nil end,
    })

    -- Blinded: у киллера атрибут Blindness 0..100 (FlashBlindEffect игры: эффект ослепления фонариком)
    DefineFeature({
        Id = "KillerBlind_",
        Toggle = "KillerState_Blind",
        Watch = { "KillerState_BlindColor", "KillerState_TextSize" },
        Update = function(self)
            local seen = {}
            for _, e in ipairs(Targets.Killers) do
                local b = e.Model and tonumber(ReadAttr(e.Model, e.Player, "Blindness"))
                if b and b > 0 then
                    seen[e.Model] = true
                    Tags.Set(e.Model, "Blind", RGBTag(Options.KillerState_BlindColor.Value, string.format("BLINDED %d%%", math.floor(b + 0.5))),
                        Options.KillerState_TextSize.Value, Color3.new(1, 1, 1))
                end
            end
            Tags.PruneSlot("Blind", seen)
        end,
        Disable = function(self) Tags.RemoveSlotAll("Blind") end,
    })

    -- Anonymous mode ([v91] расширен): свой ник в любом TextLabel игрового GUI (PlayerGui), где написан твой Name /
    -- DisplayName (карточки SurvivorHUD, лобби, Results/.../Username); по желанию чужие карточки -> Player N;
    -- свой уровень: TextLabel с текстом = атрибут Level игрока, в пути которого есть level / lvl (Results: Border/Level;
    -- в строке результатов - только если Username этой строки твой). Ник в ватермарке - Library.NameOverride.
    -- Серые дамми: у карточек Survivor<N> свой ViewportFrame с серым манекеном поверх их ViewportFrame (их прячем
    -- ImageTransparency = 1). Игра переписывает текст / прозрачность - ставим снова; при выключении всё назад.
    DefineFeature({
        Id = "Anon_",
        Toggle = "Hud_Anon",
        Watch = { "Hud_AnonName", "Hud_AnonAll", "Hud_AnonDummy", "Hud_AnonLevel", "Hud_AnonLevelValue" },
        Enable = function(self)
            self.Real = setmetatable({}, { __mode = "k" }) -- [label] = настоящий текст
            self.Mine = setmetatable({}, { __mode = "k" }) -- [label] = что поставили мы
            self.Dummies = setmetatable({}, { __mode = "k" }) -- [ViewportFrame игры] = { VF = наш, Saved = прозрачность }
            self.ScanAt = -math.huge
            self.Maid:Give(function() Library.NameOverride = nil end)
        end,
        Nick = function(self)
            local nick = tostring(Options.Hud_AnonName.Value or "")
            return nick ~= "" and nick or "Me"
        end,
        IsMe = function(self, t)
            return t ~= "" and (t == LocalPlayer.Name or t == LocalPlayer.DisplayName)
        end,
        IsLevelLabel = function(self, label, real)
            if not Toggles.Hud_AnonLevel.Value then return false end
            local lvl = LocalPlayer:GetAttribute("Level")
            if lvl == nil or real ~= tostring(lvl) then return false end
            local x, hit = label, false
            for _ = 1, 3 do
                if not x then break end
                local n = string.lower(x.Name)
                if string.find(n, "level", 1, true) or string.find(n, "lvl", 1, true) then hit = true break end
                x = x.Parent
            end
            if not hit then return false end
            -- строка результатов (Row/Border/Level + Row/Username): только своя
            local row = label.Parent and label.Parent.Parent
            local user = row and row:FindFirstChild("Username")
            if user and user:IsA("TextLabel") then
                local ut = self.Real[user] or user.Text
                return self:IsMe(ut)
            end
            return true
        end,
        Want = function(self, label, real)
            if real == "" or real == "Label" then return nil end
            if self:IsMe(real) then return self:Nick() end
            if self:IsLevelLabel(label, real) then return tostring(math.floor(Options.Hud_AnonLevelValue.Value)) end
            local card = label.Parent and label.Parent.Name
            if Toggles.Hud_AnonAll.Value and label.Name == "TextLabel" and card and string.match(card, "^Survivor%d+$") then
                return "Player " .. (card:match("%d+") or "")
            end
            return nil
        end,
        Apply = function(self, label)
            local cur = label.Text
            if self.Mine[label] ~= cur then self.Real[label] = cur end -- игра поставила своё
            local want = self:Want(label, self.Real[label] or cur)
            if want and cur ~= want then
                self.Mine[label] = want
                label.Text = want
            elseif not want and self.Mine[label] and self.Real[label] then
                self.Mine[label] = nil
                label.Text = self.Real[label]
            end
        end,
        Hook = function(self, label)
            if self.Real[label] ~= nil then return end
            self.Real[label] = label.Text
            self.Maid:Give(label:GetPropertyChangedSignal("Text"):Connect(function() SafeRun(self, "Apply", label) end))
        end,
        -- серый манекен (R6 из Part, как обычный Dummy) в своём ViewportFrame
        BuildDummy = function(self, gameVF)
            local vf = New("ViewportFrame", { Name = RandomName(), BackgroundTransparency = 1, BorderSizePixel = 0,
                Parent = gameVF.Parent })
            pcall(function() vf.Ambient = Color3.fromRGB(170, 170, 170) vf.LightColor = Color3.new(1, 1, 1) end)
            local model = New("Model", { Name = "Dummy" })
            local grey = Color3.fromRGB(163, 162, 165)
            local function part(name, size, pos)
                local p = New("Part", { Name = name, Anchored = true, CanCollide = false, Size = size, Color = grey,
                    Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(pos), Parent = model })
                return p
            end
            part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
            local head = part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0))
            pcall(function() New("SpecialMesh", { MeshType = Enum.MeshType.Head, Scale = Vector3.new(1.25, 1.25, 1.25), Parent = head }) end)
            part("Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0))
            part("Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0))
            part("Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0))
            part("Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0))
            model.Parent = vf
            local cam = New("Camera", { Parent = vf })
            pcall(function()
                cam.FieldOfView = 40
                cam.CFrame = CFrame.lookAt(Vector3.new(0, 4.4, -5.2), Vector3.new(0, 3.9, 0)) -- лицо (перед = -Z), голова + плечи
                vf.CurrentCamera = cam
            end)
            return vf
        end,
        Dummy = function(self, gameVF, on)
            local d = self.Dummies[gameVF]
            if on and gameVF.Parent then
                if not d then
                    d = { VF = self:BuildDummy(gameVF), Saved = gameVF.ImageTransparency }
                    self.Dummies[gameVF] = d
                end
                local vf = d.VF
                if gameVF.ImageTransparency ~= 1 then d.Saved = gameVF.ImageTransparency gameVF.ImageTransparency = 1 end
                SetIf(vf, "AnchorPoint", gameVF.AnchorPoint)
                SetIf(vf, "Position", gameVF.Position)
                SetIf(vf, "Size", gameVF.Size)
                SetIf(vf, "ZIndex", gameVF.ZIndex)
                SetIf(vf, "Visible", gameVF.Visible)
                pcall(SetIf, vf, "ImageColor3", gameVF.ImageColor3) -- игра темнит портрет вышедших / мёртвых
            elseif d then
                pcall(function() d.VF:Destroy() end)
                if gameVF.Parent then pcall(function() gameVF.ImageTransparency = d.Saved or 0 end) end
                self.Dummies[gameVF] = nil
            end
        end,
        Update = function(self)
            Library.NameOverride = self:Nick()
            local now = os.clock()
            local dummyOn = Toggles.Hud_AnonDummy.Value
            if now - self.ScanAt >= 2 then
                self.ScanAt = now
                local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                for _, d in ipairs(pg and pg:GetDescendants() or {}) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        local t = d.Text
                        local card = d.Parent and string.match(d.Parent.Name, "^Survivor%d+$")
                        if (card and d.Name == "TextLabel") or self:IsMe(t) or (Toggles.Hud_AnonLevel.Value and self:IsLevelLabel(d, t)) then
                            self:Hook(d)
                        end
                    elseif dummyOn and d:IsA("ViewportFrame") and d.Parent and string.match(d.Parent.Name, "^Survivor%d+$")
                        and d.Name == "ViewportFrame" and not self.Dummies[d] then
                        self:Dummy(d, true)
                    end
                end
            end
            for label in pairs(self.Real) do
                if label.Parent then SafeRun(self, "Apply", label) end
            end
            for gameVF in pairs(self.Dummies) do self:Dummy(gameVF, dummyOn) end
        end,
        Disable = function(self)
            for label, real in pairs(self.Real or {}) do
                if label.Parent and self.Mine[label] then pcall(function() label.Text = real end) end
            end
            for gameVF in pairs(self.Dummies or {}) do self:Dummy(gameVF, false) end
            Library.NameOverride = nil
            self.Real, self.Mine, self.Dummies = nil, nil, nil
        end,
    })

    -- [v87] перки на карточках выживших (SurvivorHUD игры, слева снизу). Карточка Survivor<N> с атрибутом UserId
    -- (ставит updateSurvivorGui игры), карточки в ряд. Игровой GUI не трогаем: иконки в нашем ScreenGui, каждый кадр
    -- ставятся по AbsolutePosition / AbsoluteSize карточки (поэтому идут и за её анимацией).
    DefineFeature({
        Id = "CardPerks_",
        Toggle = "Hud_CardPerks",
        Watch = { "Hud_CardPerksBg" },
        Enable = function(self)
            self.Cards, self.Over, self.ScanAt = {}, {}, -math.huge
            self.Maid:Give(function()
                for _, o in pairs(self.Over or {}) do pcall(function() o.Frame:Destroy() end) end
                self.Over = {}
            end)
        end,
        Shown = function(self, g)
            -- карточка и все предки видимы, ScreenGui включён
            local x = g
            while x and not x:IsA("ScreenGui") do
                if x:IsA("GuiObject") and not x.Visible then return false end
                x = x.Parent
            end
            return x ~= nil and x.Enabled ~= false, x
        end,
        Overlay = function(self, card)
            local o = self.Over[card]
            if o then return o end
            local f = New("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), ZIndex = 20,
                Parent = Library.ScreenGui })
            o = { Frame = f, Icons = {} }
            for k = 1, 3 do
                local bg = New("Frame", { BackgroundColor3 = Color3.fromRGB(12, 12, 12), BackgroundTransparency = 0.35, BorderSizePixel = 0,
                    ZIndex = 20, Parent = f })
                local st = New("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Parent = bg })
                local img = New("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.08, 0.08), Size = UDim2.fromScale(0.84, 0.84),
                    ZIndex = 21, Parent = bg })
                o.Icons[k] = { Bg = bg, Img = img, Stroke = st }
            end
            self.Over[card] = o
            return o
        end,
        Update = function(self)
            local now = os.clock()
            if now - self.ScanAt >= 2 then
                self.ScanAt = now
                local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local cards = {}
                for _, d in ipairs(pg and pg:GetDescendants() or {}) do
                    if d:IsA("GuiObject") and string.match(d.Name, "^Survivor%d+$") and d:FindFirstChild("ViewportFrame") then
                        cards[#cards + 1] = d
                    end
                end
                self.Cards = cards
            end
            -- данные перков по UserId карточки (раз в 0.5 c, JSON кешируется в PerkData)
            if now - (self.DataAt or 0) >= 0.5 then
                self.DataAt = now
                local alive = {}
                for _, card in ipairs(self.Cards) do
                    local uid = card.Parent and tonumber(card:GetAttribute("UserId"))
                    local pd = uid and ESPUI.PerkData(uid)
                    if pd and #pd.Perks > 0 then
                        alive[card] = true
                        local o = self:Overlay(card)
                        o.Perks = pd.Perks
                        for k = 1, 3 do
                            local pk = pd.Perks[k]
                            o.Icons[k].Img.Image = pk and (ESPUI.PerkIcon(pk.Name, pk.Level) or "") or ""
                            o.Icons[k].Bg.Visible = pk ~= nil
                            o.Icons[k].Bg.BackgroundTransparency = Toggles.Hud_CardPerksBg.Value and 0.35 or 1
                            o.Icons[k].Stroke.Enabled = Toggles.Hud_CardPerksBg.Value
                        end
                    end
                end
                for card, o in pairs(self.Over) do
                    if not alive[card] then o.Frame:Destroy() self.Over[card] = nil end
                end
            end
        end,
        Render = function(self)
            local inset = game:GetService("GuiService"):GetGuiInset()
            local pos = Options.Hud_CardPerksPos.Value
            local scale = (Options.Hud_CardPerksSize.Value or 100) / 100
            for card, o in pairs(self.Over) do
                local shown, sg = self:Shown(card)
                local ap, as = card.AbsolutePosition, card.AbsoluteSize
                shown = shown and card.Parent ~= nil and as.X > 4 and as.Y > 4
                o.Frame.Visible = shown and true or false
                if shown then
                    -- у игрового GUI другой IgnoreGuiInset -> сдвиг на высоту топбара
                    local dy = (sg.IgnoreGuiInset and not Library.ScreenGui.IgnoreGuiInset) and -inset.Y
                        or ((not sg.IgnoreGuiInset and Library.ScreenGui.IgnoreGuiInset) and inset.Y) or 0
                    local n = #o.Perks > 3 and 3 or #o.Perks
                    local sz = math.max(math.floor(as.X / 3 * scale + 0.5), 8)
                    local gap = sz >= 18 and 2 or 1
                    local w = n * sz + (n - 1) * gap
                    local x = ap.X + (as.X - w) / 2
                    local y = (pos == "Below" and ap.Y + as.Y + 2) or (pos == "Inside" and ap.Y + as.Y - sz - 2) or (ap.Y - sz - 2)
                    o.Frame.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + dy + 0.5))
                    o.Frame.Size = UDim2.fromOffset(w, sz)
                    for k = 1, 3 do
                        o.Icons[k].Bg.Position = UDim2.fromOffset((k - 1) * (sz + gap), 0)
                        o.Icons[k].Bg.Size = UDim2.fromOffset(sz, sz)
                    end
                end
            end
        end,
    })

    -- [v92] серые персонажи для анонимайзера: у всех (игроки + боты) тело серое SmoothPlastic, без текстур мешей,
    -- одежды, аксессуаров и SurfaceAppearance, лицо стандартное. Свой персонаж - только пока не надет скинченджер
    -- (Skin.Applied): перед Skin.Apply своё возвращаем, чтобы скин сохранил настоящий вид. Игра меняет - ставим снова.
    DefineFeature({
        Id = "AnonGrey_",
        Toggle = "Hud_Anon",
        Watch = { "Hud_AnonGrey" },
        Grey = Color3.fromRGB(163, 162, 165),
        Face = "rbxasset://textures/face.png",
        Enable = function(self)
            self.Saved = setmetatable({}, { __mode = "k" }) -- [inst] = { Owner = модель, props..., SA = parent }
            self.ScanAt = -math.huge
            local orig = Skin.Apply
            Skin.Apply = function(...)
                SafeRun(self, "RestoreModel", LocalPlayer.Character)
                return orig(...)
            end
            self.Maid:Give(function() if Skin.Apply ~= orig then Skin.Apply = orig end end)
        end,
        Models = function(self)
            local list = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                local c = plr.Character
                if c and not (plr == LocalPlayer and Skin.Applied) then list[#list + 1] = c end
            end
            for _, m in ipairs(CollectionService:GetTagged("SurvivorBot")) do
                if m:IsDescendantOf(workspace) then list[#list + 1] = m end
            end
            return list
        end,
        Paint = function(self, inst, owner)
            local s = self.Saved[inst]
            if inst:IsA("BasePart") then
                if inst.Name == "HumanoidRootPart" then return end
                local acc = inst:FindFirstAncestorOfClass("Accessory")
                if not s then
                    s = { Owner = owner, Color = inst.Color, Material = inst.Material, Transparency = inst.Transparency }
                    if inst:IsA("MeshPart") then s.TextureID = inst.TextureID end
                    self.Saved[inst] = s
                end
                if acc then
                    if inst.Transparency ~= 1 then inst.Transparency = 1 end
                else
                    if inst.Color ~= self.Grey then inst.Color = self.Grey end
                    if inst.Material ~= Enum.Material.SmoothPlastic then inst.Material = Enum.Material.SmoothPlastic end
                    if s.TextureID and inst.TextureID ~= "" then pcall(function() inst.TextureID = "" end) end
                end
            elseif inst:IsA("Shirt") or inst:IsA("Pants") then
                local prop = inst:IsA("Shirt") and "ShirtTemplate" or "PantsTemplate"
                if not s then s = { Owner = owner, Prop = prop, Value = inst[prop] } self.Saved[inst] = s end
                if inst[prop] ~= "" then inst[prop] = "" end
            elseif inst:IsA("ShirtGraphic") then
                if not s then s = { Owner = owner, Prop = "Graphic", Value = inst.Graphic } self.Saved[inst] = s end
                if inst.Graphic ~= "" then inst.Graphic = "" end
            elseif inst:IsA("Decal") and inst.Parent and inst.Parent.Name == "Head" then
                if not s then s = { Owner = owner, Prop = "Texture", Value = inst.Texture } self.Saved[inst] = s end
                if inst.Texture ~= self.Face then inst.Texture = self.Face end
            elseif inst:IsA("SurfaceAppearance") then
                if not s then s = { Owner = owner, SA = inst.Parent } self.Saved[inst] = s end
                if inst.Parent then pcall(function() inst.Parent = nil end) end
            end
        end,
        Restore = function(self, inst, s)
            pcall(function()
                if s.SA ~= nil then
                    if s.SA.Parent then inst.Parent = s.SA end
                elseif s.Prop then
                    inst[s.Prop] = s.Value
                else
                    inst.Color, inst.Material, inst.Transparency = s.Color, s.Material, s.Transparency
                    if s.TextureID then inst.TextureID = s.TextureID end
                end
            end)
        end,
        RestoreModel = function(self, model)
            if not model or not self.Saved then return end
            for inst, s in pairs(self.Saved) do
                if s.Owner == model then self:Restore(inst, s) self.Saved[inst] = nil end
            end
        end,
        RestoreAll = function(self)
            for inst, s in pairs(self.Saved or {}) do self:Restore(inst, s) end
            if self.Saved then table.clear(self.Saved) end
        end,
        Update = function(self)
            if not Toggles.Hud_AnonGrey.Value then
                if next(self.Saved) then self:RestoreAll() end
                return
            end
            if Skin.Applied then self:RestoreModel(LocalPlayer.Character) end
            local now = os.clock()
            if now - self.ScanAt < 0.5 then return end
            self.ScanAt = now
            for _, m in ipairs(self:Models()) do
                for _, d in ipairs(m:GetDescendants()) do SafeRun(self, "Paint", d, m) end
            end
        end,
        Disable = function(self) self:RestoreAll() self.Saved = nil end,
    })

    -- [v91] предмет выжившего у карточки SurvivorHUD. Предмет - ребёнок персонажа с именем из ReplicatedStorage.Items
    -- (там Decal на предмет = иконка), иначе атрибут игрока EquippedItem. Заряд / речарж - только то, что реплицируется:
    -- фонарик: атрибут remaining у детали (секунды, FlashlightClient), бинт: charge, Twist of Fate: shots,
    -- адреналин: usable, Monkey Paw: MonkeyPawReadyAt игрока - ItemRechargeClock.now (как MonkeyPawClient),
    -- кинжал: кулдаун из parryResult (как ParryESP). У остальных предметов кулдаун живёт только у владельца.
    DefineFeature({
        Id = "CardItems_",
        Toggle = "Hud_CardItems",
        Enable = function(self)
            self.Cards, self.Over, self.ScanAt = {}, {}, -math.huge
            self.Parry = setmetatable({}, { __mode = "k" }) -- [персонаж] = { CdUntil, Permanent }
            local folder
            pcall(function() folder = game:GetService("ReplicatedStorage").Remotes.Items["Parrying Dagger"] end)
            local result = folder and folder:FindFirstChild("parryResult")
            if result then
                self.Maid:Give(result.OnClientEvent:Connect(function(_success, cooldown, permanent, clear, character)
                    if typeof(character) ~= "Instance" then return end
                    local st = self.Parry[character] or {}
                    self.Parry[character] = st
                    if clear == true then st.CdUntil, st.Permanent, st.UsedAt = nil, false, nil return end
                    st.UsedAt = os.clock() -- [v93]
                    if permanent == true then st.Permanent = true end
                    local cd = tonumber(cooldown)
                    if cd and cd > 0 then st.CdUntil = os.clock() + cd st.CdLen = cd end
                end))
            end
            self.Maid:Give(function()
                for _, o in pairs(self.Over or {}) do pcall(function() o.Frame:Destroy() end) end
                self.Over = {}
            end)
        end,
        Norm = function(_, n) return (string.gsub(string.lower(tostring(n)), "[^%w]", "")) end,
        -- иконки: [норм. имя] = { Name, Texture }
        Catalog = function(self)
            if self.Cat then return self.Cat end
            local cat = {}
            local items = game:GetService("ReplicatedStorage"):FindFirstChild("Items")
            for _, d in ipairs(items and items:GetChildren() or {}) do
                if d:IsA("Decal") then cat[self:Norm(d.Name)] = { Name = d.Name, Texture = d.Texture } end
            end
            self.Cat = cat
            return cat
        end,
        Lookup = function(self, name)
            if not name or name == "" then return nil end
            local cat, n = self:Catalog(), self:Norm(name)
            if cat[n] then return cat[n] end
            for k, v in pairs(cat) do -- похожее имя (скины / сокращения)
                if #k > 3 and (string.find(n, k, 1, true) or string.find(k, n, 1, true)) then return v end
            end
            return nil
        end,
        ItemOf = function(self, plr, char)
            if char then
                for _, c in ipairs(char:GetChildren()) do
                    if not c:IsA("BasePart") and not c:IsA("Humanoid") then
                        local it = self:Lookup(c.Name)
                        if it then return it, c end
                    end
                end
            end
            return self:Lookup(plr and plr:GetAttribute("EquippedItem")), nil
        end,
        Attr = function(_, obj, name)
            if not obj then return nil end
            local v = obj:GetAttribute(name)
            if v ~= nil then return v end
            for _, d in ipairs(obj:GetDescendants()) do
                v = d:GetAttribute(name)
                if v ~= nil then return v end
            end
            return nil
        end,
        RechargeNow = function(_, plr)
            local okT, now = pcall(function() return workspace:GetServerTimeNow() end)
            if not okT or type(now) ~= "number" then now = os.time() end
            local epoch = game:GetService("ReplicatedStorage"):GetAttribute("ItemRechargeEpoch")
            local clk = plr:GetAttribute("ItemRechargeClock")
            local shift = 0
            if typeof(clk) == "Vector2" then
                shift = clk.X + ((clk.Y > 0 and type(epoch) == "number") and math.max(now - epoch - clk.Y, 0) or 0)
            end
            return now - shift
        end,
        -- текст и «готов ли» предмет
        Status = function(self, it, obj, plr, char)
            local n = it.Name
            if n == "Flashlight" then
                local rem = tonumber(self:Attr(obj or char, "remaining"))
                if rem then return string.format("%.1fs", math.max(rem, 0)), rem > 0 end
            elseif n == "Bandage" then
                local ch = tonumber(self:Attr(obj, "charge"))
                if ch then return tostring(math.floor(ch + 0.5)), ch > 0 end
            elseif n == "Twist of Fate" then
                local sh = tonumber(self:Attr(obj, "shots"))
                if sh then return "x" .. math.floor(sh), sh > 0 end
            elseif n == "Adrenaline Shot" then
                local u = self:Attr(obj, "usable")
                if u == false then return "used", false end
                if u == true then return "", true end
            elseif n == "Monkey Paw" then
                local at = tonumber(plr and plr:GetAttribute("MonkeyPawReadyAt"))
                local left = at and plr and (at - self:RechargeNow(plr)) or 0
                local fingers = tonumber(self:Attr(obj, "FingersUsed"))
                if left > 0 then return string.format("%ds", math.ceil(left)), false end
                if fingers then return (5 - fingers) .. "/5", fingers < 5 end
            elseif n == "Parrying Dagger" then
                -- [v93] кулдаун из parryResult: обычный - обратный отсчёт; «постоянный» (_startPermanentCooldown игры:
                -- кинжал ждёт, пока киллер снимет его цепью - длительности нет) - сколько секунд уже идёт
                local st = char and self.Parry[char]
                local left = st and st.CdUntil and (st.CdUntil - os.clock()) or 0
                if left > 0 then return string.format("%.1fs", left), false end
                if st and st.Permanent then return string.format("+%ds", math.floor(os.clock() - (st.UsedAt or os.clock()))), false end
            end
            return "", true
        end,
        Overlay = function(self, card)
            local o = self.Over[card]
            if o then return o end
            local f = New("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 0), ZIndex = 20,
                Parent = Library.ScreenGui })
            local bg = New("Frame", { BackgroundColor3 = Color3.fromRGB(12, 12, 12), BackgroundTransparency = 0.35, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 1, 0), ZIndex = 20, Parent = f })
            New("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Parent = bg })
            local img = New("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromScale(0.1, 0.1), Size = UDim2.fromScale(0.8, 0.8),
                ZIndex = 21, Parent = bg })
            local txt = New("TextLabel", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 1),
                Size = UDim2.fromOffset(60, 13), TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.5,
                Text = "", ZIndex = 21, Parent = f })
            pcall(function() txt.FontFace = Library.BindFonts[Enum.FontWeight.SemiBold] or Library.Scheme.Font end)
            o = { Frame = f, Img = img, Text = txt, Bg = bg }
            self.Over[card] = o
            return o
        end,
        Update = function(self)
            local now = os.clock()
            if now - self.ScanAt >= 2 then
                self.ScanAt = now
                local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local cards = {}
                for _, d in ipairs(pg and pg:GetDescendants() or {}) do
                    if d:IsA("GuiObject") and string.match(d.Name, "^Survivor%d+$") and d:FindFirstChild("ViewportFrame") then
                        cards[#cards + 1] = d
                    end
                end
                self.Cards = cards
            end
            local alive = {}
            for _, card in ipairs(self.Cards) do
                local uid = card.Parent and tonumber(card:GetAttribute("UserId"))
                local plr = uid and Players:GetPlayerByUserId(uid)
                local char = plr and plr.Character
                local it, obj
                if plr then it, obj = self:ItemOf(plr, char) end
                if it then
                    alive[card] = true
                    local o = self:Overlay(card)
                    o.Img.Image = it.Texture or ""
                    local text, ready = self:Status(it, obj, plr, char)
                    o.Text.Text = Toggles.Hud_CardItemsText.Value and text or ""
                    o.Text.TextColor3 = ready and Color3.new(1, 1, 1) or Color3.fromRGB(255, 110, 90)
                    o.Img.ImageTransparency = ready and 0 or 0.55
                end
            end
            for card, o in pairs(self.Over) do
                if not alive[card] then o.Frame:Destroy() self.Over[card] = nil end
            end
        end,
        Render = function(self)
            local inset = game:GetService("GuiService"):GetGuiInset()
            local scale = (Options.Hud_CardItemsSize.Value or 100) / 100
            for card, o in pairs(self.Over) do
                local x, sg, shown = card, nil, true
                while x and not x:IsA("ScreenGui") do
                    if x:IsA("GuiObject") and not x.Visible then shown = false break end
                    x = x.Parent
                end
                sg = x
                local ap, as = card.AbsolutePosition, card.AbsoluteSize
                shown = shown and sg ~= nil and sg.Enabled ~= false and as.X > 4 and as.Y > 4
                o.Frame.Visible = shown and true or false
                if shown then
                    local dy = (sg.IgnoreGuiInset and not Library.ScreenGui.IgnoreGuiInset) and -inset.Y
                        or ((not sg.IgnoreGuiInset and Library.ScreenGui.IgnoreGuiInset) and inset.Y) or 0
                    local sz = math.max(math.floor(as.X * 0.4 * scale + 0.5), 10)
                    -- слева от карточки, наполовину на ней (как метки крюков игры справа сверху)
                    o.Frame.Position = UDim2.fromOffset(math.floor(ap.X - sz * 0.55 + 0.5), math.floor(ap.Y + 2 + dy + 0.5))
                    o.Frame.Size = UDim2.fromOffset(sz, sz)
                end
            end
        end,
    })

    -- Blur effect: свой BlurEffect в Lighting (No Blur его не трогает - ESPUI.OwnBlur в IsBlur)
    DefineFeature({
        Id = "Blur_",
        Toggle = "World_Blur",
        Watch = { "World_BlurSize" },
        Enable = function(self)
            local b = New("BlurEffect", { Name = RandomName() })
            pcall(function() b.Size = Options.World_BlurSize.Value end) -- (pcall: в моке Size только UDim2)
            ESPUI.OwnBlur = b
            b.Parent = Lighting
            self.Maid:Give(b)
            self.Maid:Give(function() ESPUI.OwnBlur = nil end)
        end,
        Update = function(self)
            if ESPUI.OwnBlur then pcall(SetIf, ESPUI.OwnBlur, "Size", Options.World_BlurSize.Value) end
        end,
    })

    -- Low graphics: только workspace.Map - простой материал, без текстур / наклеек / SurfaceAppearance / частиц;
    -- трава Terrain выключена. Новые детали карты тоже. При выключении всё назад.
    DefineFeature({
        Id = "LowGfx_",
        Toggle = "World_LowGfx",
        FX = { ParticleEmitter = true, Trail = true, Smoke = true, Fire = true, Sparkles = true, Beam = true },
        Enable = function(self)
            self.Saved, self.Store, self.Token = setmetatable({}, { __mode = "k" }), Stash.new(), {} -- слабые ключи: старые карты не держим
            local function save(inst, prop, value)
                local per = self.Saved[inst]
                if not per then per = {} self.Saved[inst] = per end
                if per[prop] == nil then per[prop] = inst[prop] end
                if inst[prop] ~= value then pcall(function() inst[prop] = value end) end
            end
            local function apply(d)
                if d:IsA("BasePart") then
                    save(d, "Material", Enum.Material.SmoothPlastic)
                    if d:IsA("MeshPart") then save(d, "TextureID", "") end
                elseif d:IsA("Decal") then -- Decal и Texture
                    save(d, "Transparency", 1)
                elseif d:IsA("SurfaceAppearance") then
                    self.Store:Hide(d)
                elseif self.FX[d.ClassName] then
                    save(d, "Enabled", false)
                end
            end
            self.Apply = apply
            pcall(function() save(workspace.Terrain, "Decoration", false) end)
            self.MapBound = nil
            self:Update()
        end,
        -- новая карта (раунд) -> обходим её и следим за новыми деталями
        Update = function(self)
            local map = MapIndex.Map or workspace:FindFirstChild("Map")
            if not map or map == self.MapBound or not self.Apply then return end
            self.MapBound = map
            local token, apply = self.Token, self.Apply
            self.Maid:Give(map.DescendantAdded:Connect(function(d) task.defer(function() if self.Token == token then pcall(apply, d) end end) end))
            task.spawn(function()
                for i, d in ipairs(map:GetDescendants()) do
                    if self.Token ~= token then return end
                    pcall(apply, d)
                    if i % 2000 == 0 then task.wait() end
                end
            end)
        end,
        Disable = function(self)
            self.Token = nil
            for inst, props in pairs(self.Saved or {}) do
                for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
            end
            if self.Store then self.Store:RestoreAll() end
            self.Saved, self.Store, self.Apply, self.MapBound = nil, nil, nil, nil
        end,
    })
end

------------------------------------------------------------
-- [v86] перки игроков во время матча. Данные - ReplicatedStorage.MatchResults (ResultsView.readRoster игры):
-- папка на игрока (имя = UserId), атрибуты UserId, Username, Perks (JSON [{name, level}]), Item, IsKiller, Outcome.
-- Иконка перка: ReplicatedStorage.Perks[имя][уровень] (Decal.Texture / ImageLabel.Image), у перков киллеров -
-- ReplicatedStorage.Killers[*].Perks[имя] (как perkInfo игры, но с найденной папкой).
------------------------------------------------------------
do
    local decoded = {} -- [JSON] = список
    -- [v88] во время матча MatchResults пуст (проверено сканом: сервер не отдаёт чужие перки клиенту). Видно только то,
    -- что перк сам пишет атрибутом на персонажа, и только когда он сработал (по коду игры: SurvivorAnimationsController
    -- читает snakestep, SurvivorController - karma; builtdifferent замечен сканом у игрока с Built different).
    -- Замеченное запоминаем до смены персонажа (новый раунд).
    local SEEN_ATTR = { builtdifferent = "Built different", snakestep = "Snake Step", karma = "High Karma",
        -- [v89] из полного дампа RS: SurvivorController читает Flowstate (finesse vault), модуль аур -
        -- visual_learner_bonus (выживший) и enhanced_senses_aura_bonus (перк киллера Hidden), все на персонаже
        Flowstate = "Flowstate", visual_learner_bonus = "Visual Learner", enhanced_senses_aura_bonus = "Enhanced Senses" }
    local seen = {} -- [UserId] = { Char = модель, List = { {Name, Level} }, Has = { [имя] = true } }
    ESPUI.PerkSeen = seen
    local function inRound(plr)
        local t = plr.Team and plr.Team.Name
        return t == CONFIG.Teams.Survivors or t == CONFIG.Teams.Killer
    end
    local function scanSeen(plr)
        local char = plr.Character
        local rec = seen[plr.UserId]
        if not char then return rec end
        if not rec or rec.Char ~= char then
            rec = { Char = char, List = {}, Has = {} }
            seen[plr.UserId] = rec
        end
        for attr, name in pairs(SEEN_ATTR) do
            local v = char:GetAttribute(attr)
            if v ~= nil and v ~= false and v ~= 0 and not rec.Has[name] then
                rec.Has[name] = true
                rec.List[#rec.List + 1] = { Name = name, Level = 1, Seen = true }
            end
        end
        return rec
    end
    function ESPUI.PerkData(player)
        local rs = game:GetService("ReplicatedStorage")
        local mr = rs:FindFirstChild("MatchResults")
        local uid = type(player) == "number" and player or (player and player.UserId) -- [v87] можно передать UserId
        local entry = mr and uid and mr:FindFirstChild(tostring(uid))
        if not entry then
            -- [v88] матч идёт: только замеченное по атрибутам + предмет из атрибута EquippedItem игрока
            local plr = type(player) == "number" and Players:GetPlayerByUserId(player) or player
            if not (plr and inRound(plr)) then return nil end
            local rec = scanSeen(plr)
            local perks, names = {}, {}
            for _, pk in ipairs(rec and rec.List or {}) do
                perks[#perks + 1] = pk
                names[#names + 1] = pk.Name
            end
            local killer = plr.Team and plr.Team.Name == CONFIG.Teams.Killer
            return { Perks = perks, Names = names, Item = not killer and plr:GetAttribute("EquippedItem") or nil, IsKiller = killer,
                Username = plr.Name, Source = "seen" }
        end
        local raw = entry:GetAttribute("Perks")
        local list = {}
        if type(raw) == "string" and raw ~= "" then
            if decoded[raw] == nil then
                local ok, t = pcall(function() return HttpService:JSONDecode(raw) end)
                decoded[raw] = ok and type(t) == "table" and t or false
            end
            list = decoded[raw] or {}
        end
        local names, perks = {}, {}
        for _, pk in ipairs(list) do
            if type(pk) == "table" and type(pk.name) == "string" and pk.name ~= "" then
                perks[#perks + 1] = { Name = pk.name, Level = tonumber(pk.level) or 1 }
                names[#names + 1] = pk.name
            end
        end
        return { Perks = perks, Names = names, Item = entry:GetAttribute("Item"), IsKiller = entry:GetAttribute("IsKiller") == true,
            Username = entry:GetAttribute("Username"), Outcome = entry:GetAttribute("Outcome"), Entry = entry,
            Source = "last" } -- [v88] итоги матча (в лобби - прошлого)
    end

    local iconCache = {}
    function ESPUI.PerkIcon(name, level)
        local key = tostring(name) .. "#" .. tostring(level or 1)
        if iconCache[key] ~= nil then return iconCache[key] or nil end
        local rs = game:GetService("ReplicatedStorage")
        local folder = rs:FindFirstChild("Perks") and rs.Perks:FindFirstChild(name)
        if not folder and rs:FindFirstChild("Killers") then
            for _, k in ipairs(rs.Killers:GetChildren()) do
                local pf = k:FindFirstChild("Perks")
                folder = pf and pf:FindFirstChild(name)
                if folder then break end
            end
        end
        local img = folder and (folder:FindFirstChild(tostring(level or 1)) or folder:FindFirstChild("1"))
        local id = ""
        if img then
            if img:IsA("Decal") then id = img.Texture
            elseif img:IsA("ImageLabel") or img:IsA("ImageButton") then id = img.Image end
        end
        iconCache[key] = id ~= "" and id or false
        return id ~= "" and id or nil
    end

    -- панель: строка на игрока - ник (киллер красным, ты - цветом меню), предмет справа; ниже 3 иконки + имена
    local ROW_H, W = 34, 270
    DefineFeature({
        Id = "HudPerks_",
        Toggle = "Hud_Perks",
        Enable = function(self)
            self.Panel = Library:CreateHudPanel("perks", "perks", W, 19 + ROW_H + 4, UDim2.new(1, -W - 20, 0.3, 0))
            self.Rows, self.Sig = {}, nil
            self.Panel:SetVisible(true)
            self.Maid:Give(function()
                if self.Panel then self.Panel:SetVisible(false) end
                for _, r in ipairs(self.Rows or {}) do pcall(function() r.Frame:Destroy() end) end
                self.Rows = {}
            end)
        end,
        Text = function(self, parent, props)
            props.BackgroundTransparency = 1
            props.ZIndex = 33
            props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
            props.Parent = parent
            local t = New("TextLabel", props)
            pcall(function() t.FontFace = self.Panel.Title.FontFace end)
            return t
        end,
        Row = function(self, i)
            local r = self.Rows[i]
            if r then return r end
            local f = New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 2 + (i - 1) * ROW_H),
                Size = UDim2.new(1, 0, 0, ROW_H), ZIndex = 32, Parent = self.Panel.Body })
            r = { Frame = f, Icons = {}, Names = {} }
            r.Name = self:Text(f, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 0, 15), TextSize = 12, Text = "" })
            r.Item = self:Text(f, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 0, 15), TextSize = 11, Text = "",
                TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(150, 150, 150) })
            for k = 1, 3 do
                local x = 6 + (k - 1) * 87
                r.Icons[k] = New("ImageLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(x, 16), Size = UDim2.fromOffset(15, 15),
                    ZIndex = 33, Parent = f })
                r.Names[k] = self:Text(f, { Position = UDim2.fromOffset(x + 17, 16), Size = UDim2.fromOffset(68, 15), TextSize = 10, Text = "",
                    TextColor3 = Color3.fromRGB(175, 175, 175), TextTruncate = Enum.TextTruncate.AtEnd })
            end
            self.Rows[i] = r
            return r
        end,
        Update = function(self)
            if not self.Panel then return end
            local now = os.clock()
            if now - (self.At or 0) < 1 then return end
            self.At = now
            -- игроки по MatchResults: сначала киллер, потом остальные по нику
            local list = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                local pd = ESPUI.PerkData(plr)
                if pd and (#pd.Perks > 0 or pd.Source == "seen") then list[#list + 1] = { Player = plr, D = pd } end -- [v88]
            end
            table.sort(list, function(a, b)
                if a.D.IsKiller ~= b.D.IsKiller then return a.D.IsKiller end
                return tostring(a.Player.Name) < tostring(b.Player.Name)
            end)
            for i, it in ipairs(list) do
                local r = self:Row(i)
                r.Frame.Visible = true
                local nm = Library.StreamerMode and (it.D.IsKiller and "Killer" or ("Player " .. i)) or it.Player.Name
                r.Name.Text = nm
                r.Name.TextColor3 = (it.Player == LocalPlayer and Library.Scheme.AccentColor)
                    or (it.D.IsKiller and Color3.fromRGB(255, 80, 80)) or Color3.fromRGB(220, 220, 220)
                r.Item.Text = tostring(it.D.Item or "")
                for k = 1, 3 do
                    local pk = it.D.Perks[k]
                    r.Icons[k].Image = pk and (ESPUI.PerkIcon(pk.Name, pk.Level) or "") or ""
                    r.Icons[k].Visible = pk ~= nil
                    r.Names[k].Text = pk and pk.Name or ""
                end
                -- [v88] в матче перков ещё не замечено - пишем это вместо пустоты
                if #it.D.Perks == 0 then r.Names[1].Text = "none seen yet" r.Names[1].Size = UDim2.fromOffset(200, 15)
                else r.Names[1].Size = UDim2.fromOffset(68, 15) end
                r.Names[1].Position = UDim2.fromOffset(#it.D.Perks == 0 and 6 or 23, 16)
            end
            for i = #list + 1, #self.Rows do self.Rows[i].Frame.Visible = false end
            -- [v88] откуда данные: итоги матча (в лобби - прошлого) или замеченное в матче
            local src = list[1] and list[1].D.Source
            local title = (src == "last" and "perks · last match") or (src == "seen" and "perks · seen in match") or "perks"
            if self.Panel.Title and self.Panel.Title.Text ~= title then self.Panel.Title.Text = title end
            self.Panel:SetSize(W, 19 + math.max(#list, 1) * ROW_H + 6)
        end,
    })
end

------------------------------------------------------------
-- Boot
------------------------------------------------------------
MapIndex.Bind(workspace:FindFirstChild("Map"))
GlobalMaid:Give(workspace.ChildAdded:Connect(function(child)
    if child.Name == "Map" then MapIndex.Bind(child) end
end))
GlobalMaid:Give(workspace.ChildRemoved:Connect(function(child)
    if child == MapIndex.Map then MapIndex.Bind(workspace:FindFirstChild("Map")) end
end))
GlobalMaid:Give(function() MapIndex.Maid:Clean() end)

Targets.Refresh()

local accumulator = 0
GlobalMaid:Give(RunService.Heartbeat:Connect(function(dt)
    if Library.Unloaded then return end
    accumulator += dt
    if accumulator < CONFIG.UpdateRate then return end
    accumulator = 0

    local ok, err = pcall(Targets.Refresh)
    if not ok and not WarnedErrors.Targets then
        WarnedErrors.Targets = true
        warn("[" .. CONFIG.ScriptName .. "] Targets.Refresh failed: " .. tostring(err))
    end

    for _, f in ipairs(Features) do
        if f.Active and f.Update then SafeRun(f, "Update") end
    end
    ApplyHighlights()
end))

do
    local renderName = RandomName()
    RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value, function()
        if Library.Unloaded then return end
        for _, f in ipairs(Features) do
            if f.Active and f.Render then SafeRun(f, "Render") end
        end
    end)
    GlobalMaid:Give(function() RunService:UnbindFromRenderStep(renderName) end)
end

local function GetElement(idx)
    return Toggles[idx] or Options[idx]
end

for _, f in ipairs(Features) do
    local gate = f.Gate or { f.Toggle }

    local function refresh()
        local on = false
        for _, name in ipairs(gate) do
            if Toggles[name].Value then
                on = true
                break
            end
        end
        SetFeatureActive(f, on and not Library.Unloaded)
    end

    for _, name in ipairs(gate) do
        Toggles[name]:OnChanged(refresh)
    end
    for _, idx in ipairs(f.Watch) do
        local el = GetElement(idx)
        if el then
            el:OnChanged(function()
                if f.Active then
                    SafeRun(f, "Update")
                    ApplyHighlights()
                end
            end)
        else
            warn("[" .. CONFIG.ScriptName .. "] missing UI element: " .. idx)
        end
    end
    refresh()
end

-- [v71] Config как у skeet: слева Presets (SaveManager), справа Settings (Menu key, Menu color, анимация,
-- подтверждения, DPI, Streamer mode, автозагрузка, Unload) и под ним Lua [v72]
local MenuGroup = Tabs.Config:AddRightGroupbox("Settings")
MenuGroup:AddLabel("Menu key"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

-- [v72] Debug убран из Config (по просьбе): на его месте справа - Lua

-- [v72] Lua (как у gamesense): справа в Config. Скрипты - файлы VisualsHub/scripts/*.lua.
-- Скрипт запускается в песочнице (setfenv): там только безопасные функции и таблица hub. «Allow unsafe scripts»
-- даёт ему полное окружение экзекутора. Выгрузка скрипта убирает его UI, рисование и обработчики.
-- Настройки менеджера (вкл., unsafe, автозапуск) - в scripts/lua.json, а не в конфиге: чужой конфиг их не меняет.
-- Своя функция: в главном чанке занято 199 из 200 локалов.
;(function()
    local DIR = CONFIG.ScriptName .. "/scripts"
    local SETTINGS = DIR .. "/lua.json"
    local LM = { Loaded = {}, Order = {}, Errors = {}, Startup = {}, Unsafe = false, Enabled = true }
    ESPUI.Lua = LM
    local hasFS = (readfile and writefile and listfiles and isfile and isfolder and makefolder) ~= nil

    local EXAMPLE = [[
-- Пример скрипта для gamesense (Visuals Hub). Документация API - README.md, раздел «Lua».
local g = hub.ui.group("Example")              -- групбокс в Misc (справа)
local names = g:checkbox("Show killer distance", true)
local col = g:color("Text color", Color3.fromRGB(147, 197, 57))
local size = g:slider("Text size", 13, 8, 24)

hub.on("render", function()
    if not names.Value then return end
    for _, t in ipairs(hub.targets()) do
        if t.team == "Killer" then
            hub.draw.text(t.position + Vector3.new(0, 3.5, 0), string.format("%s  %d st", t.name, t.distance), col.Value, size.Value, true)
        end
    end
end)

hub.on("hit", function(kind, info)
    if kind == "parry" then hub.notify("Nice parry!") end
end)
]]

    local function notify(text, t) Library:Notify({ Title = "Lua", Description = tostring(text), Time = t or 4 }) end
    local function saveSettings()
        if not hasFS then return end
        pcall(function()
            writefile(SETTINGS, HttpService:JSONEncode({ enabled = LM.Enabled, unsafe = LM.Unsafe, startup = LM.Startup }))
        end)
    end
    local function ensureDir()
        if not hasFS then return end
        pcall(function()
            if not isfolder(CONFIG.ScriptName) then makefolder(CONFIG.ScriptName) end
            if not isfolder(DIR) then
                makefolder(DIR)
                writefile(DIR .. "/example.lua", EXAMPLE)
            end
        end)
    end
    function LM.List()
        local out = {}
        if not hasFS then return out end
        ensureDir()
        local ok, files = pcall(listfiles, DIR)
        if not ok or type(files) ~= "table" then return out end
        for _, f in ipairs(files) do
            local n = string.match(tostring(f), "([^/\\]+)%.lua$")
            if n then out[#out + 1] = n end
        end
        table.sort(out)
        return out
    end
    do -- настройки менеджера
        ensureDir()
        if hasFS and isfile(SETTINGS) then
            local ok, d = pcall(function() return HttpService:JSONDecode(readfile(SETTINGS)) end)
            if ok and type(d) == "table" then
                LM.Enabled = d.enabled ~= false
                LM.Unsafe = d.unsafe == true
                if type(d.startup) == "table" then LM.Startup = d.startup end
            end
        end
    end

    ------------------------------------------------ рисование (пул GUI-объектов, сбрасывается каждый кадр)
    local Draw = { Pools = {} }
    local function pool(kind, make)
        local p = Draw.Pools[kind]
        if not p then p = { List = {}, Used = 0, Make = make } Draw.Pools[kind] = p end
        p.Used += 1
        local o = p.List[p.Used]
        if not o then
            if not Draw.Gui then Draw.Gui = NewOverlayGui() end
            o = make(Draw.Gui)
            p.List[p.Used] = o
        end
        o.Visible = true
        return o
    end
    local function toScreen(pos)
        if typeof(pos) == "Vector2" then return pos, true end
        if typeof(pos) ~= "Vector3" then return nil, false end
        local cam = workspace.CurrentCamera
        if not cam then return nil, false end
        local v, on = cam:WorldToViewportPoint(pos)
        if not on or v.Z <= 0 then return nil, false end
        return Vector2.new(v.X, v.Y), true, v.Z
    end
    local DrawAPI = {}
    function DrawAPI.text(pos, text, color, size, center)
        local p = toScreen(pos)
        if not p then return end
        local l = pool("text", function(gui)
            local t = New("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                TextStrokeTransparency = 0.4, Font = Enum.Font.SourceSans, ZIndex = 5, Parent = gui })
            pcall(Library.ApplyESPFont, Library, t)
            return t
        end)
        l.Text = tostring(text)
        l.TextColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
        l.TextSize = tonumber(size) or 13
        l.AnchorPoint = center and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
        l.Position = UDim2.fromOffset(math.floor(p.X), math.floor(p.Y))
    end
    function DrawAPI.line(a, b, color, thickness)
        local pa, pb = toScreen(a), toScreen(b)
        if not (pa and pb) then return end
        local f = pool("line", function(gui)
            return New("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 4, Parent = gui })
        end)
        local d = pb - pa
        local mid = (pa + pb) / 2
        f.BackgroundColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
        f.Size = UDim2.fromOffset(math.max(d.Magnitude, 1), tonumber(thickness) or 1)
        f.Position = UDim2.fromOffset(mid.X, mid.Y)
        f.Rotation = math.deg(math.atan2(d.Y, d.X))
    end
    local function rect(kind, pos, size, color, filled, round)
        local p = toScreen(pos)
        if not p then return end
        local f = pool(kind, function(gui)
            local fr = New("Frame", { BorderSizePixel = 0, ZIndex = 4, Parent = gui })
            New("UIStroke", { Thickness = 1, Parent = fr })
            if round then New("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fr }) end
            return fr
        end)
        local c = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
        local s = typeof(size) == "Vector2" and size or Vector2.new(tonumber(size) or 10, tonumber(size) or 10)
        f.AnchorPoint = round and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
        f.Position = UDim2.fromOffset(math.floor(p.X), math.floor(p.Y))
        f.Size = UDim2.fromOffset(math.floor(s.X), math.floor(s.Y))
        f.BackgroundColor3 = c
        f.BackgroundTransparency = filled and 0 or 1
        local st = f:FindFirstChildOfClass("UIStroke")
        if st then st.Color = c end
    end
    function DrawAPI.box(pos, size, color, filled) rect("box", pos, size, color, filled, false) end
    function DrawAPI.circle(pos, radius, color, filled)
        local r = (tonumber(radius) or 5) * 2
        rect("circle", pos, Vector2.new(r, r), color, filled, true)
    end
    local function beginFrame() for _, p in pairs(Draw.Pools) do p.Used = 0 end end
    local function endFrame()
        for _, p in pairs(Draw.Pools) do
            for i = p.Used + 1, #p.List do p.List[i].Visible = false end
        end
    end

    ------------------------------------------------ снимок целей для скриптов (без Instance в безопасном режиме)
    local function snapshot(e, team, unsafe, myPos)
        local hum, root = e.Humanoid, e.Root
        local pos = root and root.Position or Vector3.zero
        local t = {
            name = Library.StreamerMode and (team == "Killer" and "Killer" or "Player") or e.Name,
            team = team, position = pos,
            health = hum and hum.Health or 0, maxhealth = hum and hum.MaxHealth or 100,
            distance = myPos and math.floor((pos - myPos).Magnitude + 0.5) or 0, -- стады
            knocked = ReadAttr(e.Model, e.Player, "Knocked") == true,
            hooked = ReadAttr(e.Model, e.Player, "IsHooked") == true,
            stunned = ReadAttr(e.Model, e.Player, "IsStunned") == true,
        }
        if unsafe then t.model, t.player, t.humanoid, t.root = e.Model, e.Player, hum, root end
        return t
    end

    ------------------------------------------------ загрузка / выгрузка
    local function safeId(s) return (string.gsub(tostring(s), "[^%w]", "_")) end
    local function fail(S, where, err)
        local msg = tostring(err)
        LM.Errors[S.Name] = msg
        warn("[gamesense lua] " .. S.Name .. " (" .. where .. "): " .. msg)
        notify(S.Name .. ": " .. msg, 6)
        if LM.Loaded[S.Name] == S then task.defer(LM.Unload, S.Name) end
        if LM.Refresh then LM.Refresh() end
    end
    local function call(S, where, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then fail(S, where, err) end
        return ok
    end
    local function stashAndRemove(idx)
        local t, o = Toggles[idx], Options[idx]
        local rec
        if t then rec = { type = "Toggle", idx = idx, value = t.Value }
        elseif o then
            if o.Type == "Slider" then rec = { type = "Slider", idx = idx, value = tostring(o.Value) }
            elseif o.Type == "ColorPicker" then rec = { type = "ColorPicker", idx = idx, value = o.Value:ToHex(), transparency = o.Transparency }
            elseif o.Type == "Dropdown" then rec = { type = "Dropdown", idx = idx, value = o.Value }
            elseif o.Type == "Input" then rec = { type = "Input", idx = idx, text = o.Value } end
        end
        if rec and SaveManager.Pending then SaveManager.Pending[idx] = rec end
        Toggles[idx], Options[idx] = nil, nil
    end

    local function makeHub(S, unsafe)
        local hub = { name = S.Name, version = "v72", unsafe = unsafe, draw = DrawAPI, ui = {} }
        local prefix = "Lua_" .. safeId(S.Name) .. "_"
        function hub.ui.group(title, opts)
            opts = type(opts) == "table" and opts or {}
            local tab = Tabs[opts.tab or "MiscOther"]
            if not tab or not tab.AddLeftGroupbox or opts.tab == "Players" or opts.tab == "Misc" then tab = Tabs.MiscOther end -- [v91] Misc -> подвкладка Other -- [v73] World - подвкладка Visuals, работает
            local box = (opts.side == "left") and tab:AddLeftGroupbox(tostring(title)) or tab:AddRightGroupbox(tostring(title))
            table.insert(S.Groups, box)
            local G = {}
            local function reg(name)
                local idx = prefix .. safeId(name)
                table.insert(S.Ids, idx)
                return idx
            end
            local function done(idx, el)
                if SaveManager.ApplyPending then SaveManager:ApplyPending(idx) end
                local onChanged = el.OnChanged
                if onChanged then -- обработчики скрипта - с защитой: ошибка выгружает скрипт, а не ломает меню
                    function el:OnChanged(fn)
                        return onChanged(self, function(...) call(S, "OnChanged", fn, ...) end)
                    end
                end
                return el
            end
            function G:checkbox(name, default, tooltip)
                local idx = reg(name)
                return done(idx, box:AddCheckbox(idx, { Text = tostring(name), Default = default == true, Tooltip = tooltip }))
            end
            function G:slider(name, default, min, max, o)
                o = type(o) == "table" and o or {}
                local idx = reg(name)
                return done(idx, box:AddSlider(idx, { Text = tostring(name), Default = tonumber(default) or 0, Min = tonumber(min) or 0,
                    Max = tonumber(max) or 100, Rounding = tonumber(o.rounding) or 0, Suffix = o.suffix }))
            end
            function G:color(name, default)
                local idx = reg(name)
                box:AddLabel(tostring(name)):AddColorPicker(idx, { Default = typeof(default) == "Color3" and default or Color3.new(1, 1, 1),
                    Title = tostring(name) })
                return done(idx, Options[idx])
            end
            function G:dropdown(name, values, default, multi)
                local idx = reg(name)
                return done(idx, box:AddDropdown(idx, { Text = tostring(name), Values = type(values) == "table" and values or {},
                    Default = default, Multi = multi == true }))
            end
            function G:input(name, default)
                local idx = reg(name)
                return done(idx, box:AddInput(idx, { Text = tostring(name), Default = default and tostring(default) or "" }))
            end
            function G:button(name, fn)
                return box:AddButton({ Text = tostring(name), Func = function() if type(fn) == "function" then call(S, "button", fn) end end })
            end
            function G:label(text)
                local l = box:AddLabel(tostring(text))
                return { set = function(_, t) l:SetText(t) end }
            end
            return G
        end
        function hub.on(ev, fn)
            if type(fn) ~= "function" then error("hub.on: handler must be a function", 2) end
            ev = ev == "paint" and "render" or ev
            if not S.Events[ev] then error("hub.on: unknown event '" .. tostring(ev) .. "' (render, update, hit, unload)", 2) end
            table.insert(S.Events[ev], fn)
        end
        function hub.targets()
            local out = {}
            local root = GetRoot(LocalPlayer.Character)
            local my = root and root.Position
            for _, e in ipairs(Targets.Killers) do out[#out + 1] = snapshot(e, "Killer", unsafe, my) end
            for _, e in ipairs(Targets.Survivors) do out[#out + 1] = snapshot(e, "Survivor", unsafe, my) end
            for _, e in ipairs(Targets.Bots) do out[#out + 1] = snapshot(e, "Bot", unsafe, my) end
            return out
        end
        function hub.me()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local root = GetRoot(char)
            local team = LocalPlayer.Team and LocalPlayer.Team.Name
            return {
                name = Library.StreamerMode and "user" or LocalPlayer.Name,
                team = (team == CONFIG.Teams.Killer and "Killer") or (team == CONFIG.Teams.Survivors and "Survivor") or "Spectator",
                position = root and root.Position, health = hum and hum.Health or 0, maxhealth = hum and hum.MaxHealth or 100,
            }
        end
        hub.w2s = toScreen
        function hub.notify(text, t) Library:Notify({ Title = S.Name, Description = tostring(text), Time = tonumber(t) or 4 }) end
        function hub.log(parts) if Library.HitLogObj then Library.HitLogObj:Push(parts) end end
        function hub.accent() return Library.Scheme.AccentColor end
        function hub.get(id) -- только чтение настроек хаба
            local el = Toggles[id] or Options[id]
            return el and el.Value
        end
        function hub.screen()
            local cam = workspace.CurrentCamera
            return cam and cam.ViewportSize or Vector2.new(1920, 1080)
        end
        return hub
    end

    local SAFE = { "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring", "type", "typeof",
        "unpack", "xpcall", "rawequal", "rawget", "rawlen", "setmetatable", "getmetatable", "tick", "time",
        "Vector2", "Vector3", "CFrame", "Color3", "UDim", "UDim2", "Enum", "Ray", "NumberRange", "NumberSequence",
        "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "Rect", "BrickColor", "TweenInfo" }
    local LIBS = { "math", "string", "table", "coroutine", "bit32", "utf8" }
    local function makeEnv(S, hub, unsafe)
        local function out(...)
            local t = table.pack(...)
            for i = 1, t.n do t[i] = tostring(t[i]) end
            return "[" .. S.Name .. "] " .. table.concat(t, " ", 1, t.n)
        end
        local env = { hub = hub, print = function(...) print(out(...)) end, warn = function(...) warn(out(...)) end }
        if unsafe then
            local base = (getgenv and getgenv()) or getfenv(0)
            return setmetatable(env, { __index = function(_, k)
                local v = base[k]
                if v == nil then v = getfenv(0)[k] end
                return v
            end })
        end
        local g = getfenv(0)
        for _, k in ipairs(SAFE) do env[k] = g[k] end
        for _, k in ipairs(LIBS) do
            local lib = g[k]
            if type(lib) == "table" then env[k] = table.clone(lib) end
        end
        env.os = { clock = os.clock, time = os.time, date = os.date }
        env.task = { wait = task.wait, delay = task.delay, spawn = task.spawn, defer = task.defer }
        env._G = env
        return env
    end

    function LM.Load(name)
        if LM.Loaded[name] then return true end
        if not LM.Enabled then return false, "Lua is disabled" end
        if not (loadstring and setfenv) then return false, "executor has no loadstring / setfenv" end
        local path = DIR .. "/" .. name .. ".lua"
        if not (hasFS and isfile(path)) then return false, "file not found" end
        local src = readfile(path)
        local fn, err = loadstring(src, "=" .. name)
        if not fn then LM.Errors[name] = tostring(err) return false, tostring(err) end
        local S = { Name = name, Groups = {}, Ids = {}, Events = { render = {}, update = {}, hit = {}, unload = {} } }
        local unsafe = LM.Unsafe
        local hub = makeHub(S, unsafe)
        setfenv(fn, makeEnv(S, hub, unsafe))
        LM.Loaded[name] = S
        table.insert(LM.Order, name)
        LM.Errors[name] = nil
        local ok, rerr = pcall(fn)
        if not ok then
            LM.Unload(name)
            LM.Errors[name] = tostring(rerr)
            warn("[gamesense lua] " .. name .. ": " .. tostring(rerr))
            return false, tostring(rerr)
        end
        return true
    end

    function LM.Unload(name)
        local S = LM.Loaded[name]
        if not S then return false end
        LM.Loaded[name] = nil
        local i = table.find(LM.Order, name)
        if i then table.remove(LM.Order, i) end
        for _, fn in ipairs(S.Events.unload) do pcall(fn) end
        for _, idx in ipairs(S.Ids) do stashAndRemove(idx) end
        for _, g in ipairs(S.Groups) do if g.Destroy then pcall(g.Destroy, g) end end
        table.clear(S.Events.render) table.clear(S.Events.update) table.clear(S.Events.hit)
        return true
    end

    function LM.UnloadAll()
        for i = #LM.Order, 1, -1 do LM.Unload(LM.Order[i]) end
    end

    function LM.Emit(ev, ...)
        for _, name in ipairs(table.clone(LM.Order)) do
            local S = LM.Loaded[name]
            if S then
                for _, fn in ipairs(S.Events[ev] or {}) do
                    if not call(S, ev, fn, ...) then break end
                end
            end
        end
    end
    ESPUI.LuaEmit = function(ev, ...) if #LM.Order > 0 then LM.Emit(ev, ...) end end

    GlobalMaid:Give(RunService.RenderStepped:Connect(function(dt)
        if #LM.Order == 0 and not Draw.Gui then return end
        beginFrame()
        if #LM.Order > 0 then LM.Emit("render", dt) end
        endFrame()
    end))
    GlobalMaid:Give(RunService.Heartbeat:Connect(function(dt)
        if #LM.Order > 0 then LM.Emit("update", dt) end
    end))
    GlobalMaid:Give(function() if Draw.Gui then pcall(function() Draw.Gui:Destroy() end) end end)
    Library:OnUnload(function() LM.UnloadAll() end)

    ------------------------------------------------ групбокс «Lua» (как у skeet)
    local box = Tabs.Config:AddRightGroupbox("Lua")
    local en = box:AddCheckbox("LuaMgr_Enabled", { Text = "Enable Lua scripts", Default = LM.Enabled,
        Tooltip = "Scripts live in " .. DIR .. " (.lua files). See README, section Lua." })
    local unsafeT = box:AddCheckbox("LuaMgr_Unsafe", { Text = "Allow unsafe scripts", Default = LM.Unsafe,
        Tooltip = "Gives scripts the full executor environment (game, files, getgenv ...). Only for scripts you trust. Applies on next load." })
    box:AddButton({ Text = "Reload active scripts", Func = function()
        local names = table.clone(LM.Order)
        LM.UnloadAll()
        local okN = 0
        for _, n in ipairs(names) do if LM.Load(n) then okN += 1 end end
        notify("Reloaded " .. okN .. "/" .. #names .. " scripts")
        if LM.Refresh then LM.Refresh() end
    end })
    local search = box:AddInput("LuaMgr_Search", { Placeholder = "search", Clear = true })
    local function filtered()
        local q = string.lower(tostring(search.Value or ""))
        local out = {}
        for _, n in ipairs(LM.List()) do
            if q == "" or string.find(string.lower(n), q, 1, true) then out[#out + 1] = n end
        end
        return out
    end
    local lb = box:AddListbox("LuaMgr_List", { Rows = 6, Values = filtered })
    local status = box:AddLabel("Status: -")
    local startup = box:AddCheckbox("LuaMgr_Startup", { Text = "Load on startup", Default = false })
    local loadBtn
    loadBtn = box:AddButton({ Text = "Load script", Func = function()
        local n = lb.Value
        if not n then return notify("Select a script first") end
        if LM.Loaded[n] then
            LM.Unload(n)
            notify("Unloaded " .. n)
        else
            local ok, err = LM.Load(n)
            notify(ok and ("Loaded " .. n) or (n .. ": " .. tostring(err)), ok and 4 or 6)
        end
        LM.Refresh()
    end })
    box:AddButton({ Text = "Refresh list", Tooltip = "Put .lua files into workspace/" .. DIR, Func = function()
        lb:SetValues(filtered())
        LM.Refresh()
    end })
    local syncing = false
    function LM.Refresh()
        local n = lb.Value
        local st
        if not n then st = "-"
        elseif LM.Loaded[n] then st = "running"
        elseif LM.Errors[n] then st = "error: " .. LM.Errors[n]
        else st = "not loaded" end
        status:SetText("Status: " .. st)
        local t = LM.Loaded[n] and "Unload script" or "Load script"
        loadBtn.Text = t
        loadBtn:SetText(t)
        syncing = true
        startup:SetValue(n ~= nil and table.find(LM.Startup, n) ~= nil)
        syncing = false
    end
    lb:OnChanged(function() LM.Refresh() end)
    search:OnChanged(function() lb:SetValues(filtered()) end)
    startup:OnChanged(function(v)
        if syncing then return end
        local n = lb.Value
        if not n then return end
        local i = table.find(LM.Startup, n)
        if v and not i then table.insert(LM.Startup, n) elseif not v and i then table.remove(LM.Startup, i) end
        saveSettings()
    end)
    en:OnChanged(function(v)
        LM.Enabled = v == true
        if not LM.Enabled then LM.UnloadAll() end
        saveSettings()
        LM.Refresh()
    end)
    unsafeT:OnChanged(function(v) LM.Unsafe = v == true saveSettings() end)
    SaveManager:SetIgnoreIndexes({ "LuaMgr_Enabled", "LuaMgr_Unsafe", "LuaMgr_Search", "LuaMgr_List", "LuaMgr_Startup" })
    LM.Refresh()

    -- после автозагрузки конфига (вызов в конце файла): скрипты из «Load on startup»
    function LM.RunStartup()
        if not LM.Enabled then return end
        for _, n in ipairs(LM.Startup) do
            local ok, err = LM.Load(n)
            if not ok then notify(n .. ": " .. tostring(err), 6) end
        end
        LM.Refresh()
    end
end)()

local function UnloadSelf()
    if not Library.Unloaded then Library:Unload() end
end

Library:OnUnload(function()
    for _, f in ipairs(Features) do
        if f.Active then
            local ok = pcall(SetFeatureActive, f, false)
            if not ok then f.Active = false end
        end
    end
    for _, g in ipairs(HighlightGroup.All) do g:Clear() end
    Tags.DestroyAll()
    GlobalMaid:Clean()
    if GENV.__VisualsHubUnload == UnloadSelf then GENV.__VisualsHubUnload = nil end
end)

GENV.__VisualsHubUnload = UnloadSelf

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder(CONFIG.ScriptName)
SaveManager:SetFolder(CONFIG.ScriptName .. "/" .. CONFIG.GameFolder)
ThemeManager:BuildMenuSettings(MenuGroup) -- [v71] Menu color / animation speed / confirmations / DPI / Streamer mode
SaveManager:BuildAutoload(MenuGroup)      -- [v71]
MenuGroup:AddButton({ Text = "Unload", Confirm = true, Func = function() Library:Unload() end })
SaveManager:BuildConfigSection(Tabs.Config)
ThemeManager:ApplyToTab(Tabs.MiscOther) -- [v91] подвкладка Other, [v60] тема из Config переехала в Misc (справа)
SaveManager:LoadAutoloadConfig()
if ESPUI.Lua then ESPUI.Lua.RunStartup() end -- [v72] Lua-скрипты с «Load on startup» - после конфига