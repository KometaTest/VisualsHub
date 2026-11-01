-- Minimal Roblox mock for smoke-testing UI code paths under plain Luau.
local unknownProps = {}

-- datatypes ------------------------------------------------
local function mkvec(name, fields)
    local mt = {}
    mt.__index = function(t, k)
        if k == "Magnitude" then
            local s = 0 for _, f in ipairs(fields) do s += rawget(t, f) ^ 2 end return math.sqrt(s)
        elseif k == "Unit" then
            local m = t.Magnitude; local o = {} for _, f in ipairs(fields) do o[f] = m > 0 and rawget(t, f) / m or 0 end return setmetatable(o, mt)
        elseif k == "Dot" then
            return function(a, b) local s = 0 for _, f in ipairs(fields) do s += rawget(a, f) * rawget(b, f) end return s end
        elseif k == "Lerp" then
            return function(a, b, al) local o = {} for _, f in ipairs(fields) do o[f] = rawget(a, f) + (rawget(b, f) - rawget(a, f)) * al end return setmetatable(o, mt) end
        elseif k == "Cross" then
            return function(a, b) return a end
        end
        return nil
    end
    local function bin(op) return function(a, b)
        local o = {}
        for _, f in ipairs(fields) do
            local av = type(a) == "number" and a or rawget(a, f)
            local bv = type(b) == "number" and b or rawget(b, f)
            o[f] = op(av, bv)
        end
        return setmetatable(o, mt)
    end end
    mt.__add = bin(function(a, b) return a + b end)
    mt.__sub = bin(function(a, b) return a - b end)
    mt.__mul = bin(function(a, b) return a * b end)
    mt.__div = bin(function(a, b) return a / b end)
    mt.__unm = function(a) local o = {} for _, f in ipairs(fields) do o[f] = -rawget(a, f) end return setmetatable(o, mt) end
    mt.__eq = function(a, b) for _, f in ipairs(fields) do if rawget(a, f) ~= rawget(b, f) then return false end end return true end
    mt.__type = name
    -- [v24] второй __index убран: он затирал Unit/Dot/Lerp
    local lib = {}
    lib.new = function(...) local a = { ... } local o = {} for i, f in ipairs(fields) do o[f] = a[i] or 0 end return setmetatable(o, mt) end
    lib.zero = lib.new()
    lib.one = lib.new(1, 1, 1)
    return lib, mt
end
Vector2 = mkvec("Vector2", { "X", "Y" })
Vector3 = mkvec("Vector3", { "X", "Y", "Z" })

local TYPES = setmetatable({}, { __mode = "k" })
local function tag(t, name) TYPES[t] = name return t end
local rawtypeof = typeof
typeof = function(v)
    if type(v) == "table" then
        if TYPES[v] then return TYPES[v] end
        local mt = getmetatable(v)
        if mt and rawget(mt, "__type") then return mt.__type end
        if mt and rawget(mt, "__isInstance") then return "Instance" end
    end
    return rawtypeof(v)
end

UDim = { new = function(s, o) return tag({ Scale = s or 0, Offset = o or 0 }, "UDim") end }
local UD2mt = { __type = "UDim2" }
UDim2 = {
    new = function(a, b, c, d) return setmetatable({ X = UDim.new(a, b), Y = UDim.new(c, d), Width = UDim.new(a, b), Height = UDim.new(c, d) }, UD2mt) end,
}
UD2mt.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UD2mt.__eq = function(a, b) return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
UDim2.fromScale = function(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end

local C3mt = { __type = "Color3" }
C3mt.__index = {
    ToHSV = function(c)
        local r, g, b = c.R, c.G, c.B
        local mx, mn = math.max(r, g, b), math.min(r, g, b)
        local d = mx - mn
        local h = 0
        if d > 0 then
            if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
            h /= 6
        end
        return h, mx == 0 and 0 or d / mx, mx
    end,
    ToHex = function(c) return string.format("%02x%02x%02x", math.floor(c.R * 255 + .5), math.floor(c.G * 255 + .5), math.floor(c.B * 255 + .5)) end,
    Lerp = function(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end,
}
Color3 = {}
Color3.new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3mt) end
Color3.fromRGB = function(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
Color3.fromHSV = function(h, s, v)
    local i = math.floor(h * 6) local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i %= 6
    if i == 0 then return Color3.new(v, t, p) elseif i == 1 then return Color3.new(q, v, p) elseif i == 2 then return Color3.new(p, v, t)
    elseif i == 3 then return Color3.new(p, q, v) elseif i == 4 then return Color3.new(t, p, v) end
    return Color3.new(v, p, q)
end
Color3.fromHex = function(h)
    h = h:gsub("#", "")
    assert(#h == 6, "bad hex")
    return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

Rect = { new = function(a, b, c, d) return tag({ Min = Vector2.new(a, b), Max = Vector2.new(c, d) }, "Rect") end }
Font = { new = function(f, w) return tag({ Family = f, Weight = w }, "Font") end, fromEnum = function() return tag({}, "Font") end }
TweenInfo = { new = function(...) return tag({ ... }, "TweenInfo") end }
NumberSequence = { new = function(...) return tag({ ... }, "NumberSequence") end }
ColorSequence = { new = function(...) return tag({ ... }, "ColorSequence") end }
ColorSequenceKeypoint = { new = function(...) return tag({ ... }, "ColorSequenceKeypoint") end }
NumberSequenceKeypoint = ColorSequenceKeypoint
NumberRange = { new = function(...) return { ... } end }
RaycastParams = { new = function() return {} end }
PhysicalProperties = { new = function() return {} end }
local CFmt = {}
CFmt.__index = function(t, k)
    if k == "Position" then return Vector3.new() end
    if k == "LookVector" then return Vector3.new(0, 0, -1) end
    if k == "RightVector" then return Vector3.new(1, 0, 0) end
    if k == "UpVector" then return Vector3.new(0, 1, 0) end
    if k == "PointToObjectSpace" or k == "VectorToObjectSpace" then return function(_, p) return p end end -- identity
    return function(...) return setmetatable({}, CFmt) end
end
CFmt.__mul = function() return setmetatable({}, CFmt) end
CFmt.__add = CFmt.__mul
CFrame = setmetatable({ identity = setmetatable({}, CFmt) }, { __index = function() return function() return setmetatable({}, CFmt) end end })

local enumCache = {}
Enum = setmetatable({}, { __index = function(_, cat)
    enumCache[cat] = enumCache[cat] or setmetatable({}, { __index = function(t, name)
        local v = tag({ Name = name, EnumType = cat, Value = 0 }, "EnumItem")
        rawset(t, name, v)
        return v
    end })
    return enumCache[cat]
end })

-- signals ---------------------------------------------------
local function Signal()
    local s = { _c = {} }
    function s:Connect(fn)
        local c = { Connected = true }
        function c:Disconnect() self.Connected = false end
        c.disconnect = c.Disconnect
        table.insert(s._c, { c, fn })
        return tag(c, "RBXScriptConnection")
    end
    s.connect = s.Connect
    s.Once = s.Connect
    function s:Fire(...)
        for _, p in ipairs(table.clone(s._c)) do if p[1].Connected then p[2](...) end end
    end
    function s:Wait() return nil end
    return s
end

-- instances -------------------------------------------------
local KNOWN = {}
for p in string.gmatch([[
Name Parent Size Position AnchorPoint BackgroundColor3 BackgroundTransparency BorderSizePixel Visible ZIndex LayoutOrder
Text TextColor3 TextSize TextTransparency TextStrokeTransparency TextXAlignment TextYAlignment TextWrapped TextTruncate TextScaled
FontFace Font RichText AutomaticSize ClipsDescendants Active AutoButtonColor Modal Rotation Image ImageColor3 ImageTransparency
CornerRadius Thickness Color Transparency ApplyStrokeMode PaddingLeft PaddingRight PaddingTop PaddingBottom FillDirection Padding
SortOrder HorizontalAlignment VerticalAlignment ScrollBarThickness ScrollBarImageColor3 ScrollBarImageTransparency CanvasSize
AutomaticCanvasSize ScrollingDirection ClearTextOnFocus PlaceholderText PlaceholderColor3 Scale MaxSize MinSize ZIndexBehavior
ResetOnSpawn IgnoreGuiInset DisplayOrder Enabled Rotation Adornee StudsOffsetWorldSpace SizeOffset AlwaysOnTop LightInfluence
GroupTransparency Interactable LocalTransparencyModifier ShirtTemplate Texture CanQuery Massless Part0 Part1 C0 C1 MaxDistance FillColor FillTransparency OutlineColor OutlineTransparency DepthMode Anchored CanCollide CanQuery CanTouch CastShadow
Material CFrame StudsOffset FieldOfView CameraType MouseIconEnabled AbsolutePosition AbsoluteSize Value Keypoints
]], "%S+") do KNOWN[p] = true end

local EVENTS = {}
for e in string.gmatch([[MouseButton1Click MouseButton1Down MouseEnter MouseLeave InputBegan InputChanged InputEnded FocusLost
Changed Activated DescendantAdded DescendantRemoving ChildAdded ChildRemoved Destroying Heartbeat RenderStepped Stepped
WindowFocused WindowFocusReleased PlayerAdded PlayerRemoving CharacterAdded CharacterRemoving Died HealthChanged Running
StateChanged OnClientEvent Event AncestryChanged TextChanged MouseButton2Click]], "%S+") do EVENTS[e] = true end

local Instance_ = {}
local instMT = { __isInstance = true }
local function newInst(class, name)
    local self = { __class = class, __props = { Name = name or class }, __children = {}, __signals = {}, __attrs = {} }
    return setmetatable(self, instMT)
end
local function propSignal(self, prop)
    local key = "prop:" .. prop
    self.__signals[key] = self.__signals[key] or Signal()
    return self.__signals[key]
end
local METHODS = {
    Destroy = function(self)
        local p = rawget(self, "__props").Parent
        if p then
            local ch = rawget(p, "__children")
            for i, c in ipairs(ch) do if c == self then table.remove(ch, i) break end end
        end
        rawget(self, "__props").Parent = nil
        for _, c in ipairs(table.clone(rawget(self, "__children"))) do c:Destroy() end
        rawset(self, "__destroyed", true)
    end,
    GetChildren = function(self) return table.clone(rawget(self, "__children")) end,
    GetDescendants = function(self)
        local out = {}
        local function rec(i) for _, c in ipairs(rawget(i, "__children")) do table.insert(out, c) rec(c) end end
        rec(self)
        return out
    end,
    FindFirstChild = function(self, n, rec)
        for _, c in ipairs(rawget(self, "__children")) do if c.Name == n then return c end end
        if rec then for _, c in ipairs(rawget(self, "__children")) do local r = c:FindFirstChild(n, true) if r then return r end end end
        return nil
    end,
    WaitForChild = function(self, n)
        local c = self:FindFirstChild(n)
        if not c then c = newInst("Folder", n) c.Parent = self end
        return c
    end,
    FindFirstChildOfClass = function(self, cl) for _, c in ipairs(rawget(self, "__children")) do if rawget(c, "__class") == cl then return c end end return nil end,
    FindFirstChildWhichIsA = function(self, cl, rec)
        for _, c in ipairs(rawget(self, "__children")) do if c:IsA(cl) then return c end end
        if rec then for _, c in ipairs(rawget(self, "__children")) do local r = c:FindFirstChildWhichIsA(cl, true) if r then return r end end end
        return nil
    end,
    Clone = function(self)
        local n = newInst(rawget(self, "__class"))
        for k, v in pairs(rawget(self, "__props")) do if k ~= "Parent" then rawget(n, "__props")[k] = v end end
        for _, c in ipairs(rawget(self, "__children")) do local cc = c:Clone() cc.Parent = n end
        return n
    end,
    FindFirstAncestorOfClass = function() return nil end,
    FindFirstAncestorWhichIsA = function() return nil end,
    IsA = function(self, cl)
        local c = rawget(self, "__class")
        if c == cl then return true end
        if cl == "GuiObject" then return c:find("Text") ~= nil or c == "Frame" or c:find("Image") ~= nil or c == "ScrollingFrame" end
        if cl == "LayerCollector" then return c == "ScreenGui" or c == "BillboardGui" end
        if cl == "GuiButton" then return c == "TextButton" or c == "ImageButton" end
        if cl == "BasePart" then return c == "Part" or c == "MeshPart" or c == "WedgePart" end
        return false
    end,
    IsDescendantOf = function(self, other)
        local p = rawget(self, "__props").Parent
        while p do if p == other then return true end p = rawget(p, "__props").Parent end
        return false
    end,
    GetPropertyChangedSignal = function(self, prop) return propSignal(self, prop) end,
    GetAttributeChangedSignal = function(self, a) return propSignal(self, "attr:" .. a) end,
    GetAttribute = function(self, a) return rawget(self, "__attrs")[a] end,
    SetAttribute = function(self, a, v)
        local old = rawget(self, "__attrs")[a]
        rawget(self, "__attrs")[a] = v
        local sig = rawget(self, "__signals")["prop:attr:" .. a]
        if sig and old ~= v then sig:Fire() end
    end,
    GetAttributes = function(self) return table.clone(rawget(self, "__attrs")) end,
    CaptureFocus = function() end, ReleaseFocus = function() end, IsFocused = function() return false end,
    GetPivot = function() return CFrame.new() end,
    ClearAllChildren = function(self) for _, c in ipairs(self:GetChildren()) do c:Destroy() end end,
    GetFullName = function(self) return self.Name end,
}
instMT.__index = function(self, k)
    local props = rawget(self, "__props")
    if props[k] ~= nil then return props[k] end
    if METHODS[k] then return METHODS[k] end
    local extra = rawget(self, "__extra")
    if extra and extra[k] ~= nil then return extra[k] end
    if EVENTS[k] then
        local s = rawget(self, "__signals")
        s[k] = s[k] or Signal()
        return s[k]
    end
    if k == "ClassName" then return rawget(self, "__class") end
    if k == "AbsolutePosition" then return Vector2.new(100, 100) end
    if k == "AbsoluteSize" then return Vector2.new(1280, 720) end
    if k == "Visible" or k == "Enabled" then return true end
    -- child lookup like obj.Child
    for _, c in ipairs(rawget(self, "__children")) do if c.Name == k then return c end end
    return nil
end
instMT.__newindex = function(self, k, v)
    if rawget(self, "__destroyed") and k == "Parent" and v ~= nil then error("Parent property is locked (destroyed)", 2) end
    if not KNOWN[k] then unknownProps[k] = (unknownProps[k] or 0) + 1 end
    local props = rawget(self, "__props")
    if k == "Parent" then
        local old = props.Parent
        if old then
            local ch = rawget(old, "__children")
            for i, c in ipairs(ch) do if c == self then table.remove(ch, i) break end end
        end
        if v then table.insert(rawget(v, "__children"), self) end
    end
    if (k == "Size" or k == "Position") and v ~= nil and typeof(v) ~= "UDim2" and not (typeof(v) == "Vector3" and rawget(self, "__class") == "Part") and typeof(v) ~= "NumberSequence" then error("bad " .. k .. " type " .. typeof(v), 2) end
    if (k == "BackgroundColor3" or k == "TextColor3" or k == "Color") and typeof(v) ~= "Color3" and k ~= "Color" then error("bad color for " .. k .. ": " .. typeof(v), 2) end
    props[k] = v
    local s = rawget(self, "__signals")["prop:" .. k]
    if s then s:Fire() end
    if k == "Parent" and v ~= nil then
        local ca = rawget(v, "__signals").ChildAdded
        if ca then ca:Fire(self) end
    end
end
instMT.__tostring = function(self) return rawget(self, "__class") end
Instance = { new = function(class, parent) local i = newInst(class) if parent then i.Parent = parent end return i end }

-- task ------------------------------------------------------
local deferred = {}
task = {
    spawn = function(f, ...) if type(f) == "function" then f(...) end end,
    defer = function(f, ...) table.insert(deferred, { f, { ... } }) end,
    delay = function(_, f, ...) table.insert(deferred, { f, { ... } }) end,
    wait = function() return 0 end,
}
function RUN_DEFERRED()
    local d = deferred
    deferred = {}
    for _, p in ipairs(d) do p[1](table.unpack(p[2])) end
end
wait = task.wait

-- services --------------------------------------------------
local services = {}
local function svc(name, extra)
    local s = newInst(name, name)
    rawset(s, "__extra", extra or {})
    services[name] = s
    return s
end
local LocalPlayer = newInst("Player", "TestPlayer")
rawset(LocalPlayer, "__extra", { UserId = 1, DisplayName = "Tester", Character = nil, Team = nil })
local PlayerGui = newInst("PlayerGui", "PlayerGui")
PlayerGui.Parent = LocalPlayer
svc("Players", {
    LocalPlayer = LocalPlayer,
    GetPlayers = function() return { LocalPlayer } end,
    GetPlayerFromCharacter = function() return nil end,
    GetPlayerByUserId = function(_, id) if id == LocalPlayer.UserId then return LocalPlayer end return nil end,
    GetUserThumbnailAsync = function() return "rbxthumb://x" end,
})
MOUSE = Vector2.new(0, 0)
HELD_KEYS = {}
SENT_KEYS = {}
svc("UserInputService", {
    IsKeyDown = function(_, k) return HELD_KEYS[k] == true end,
    IsMouseButtonPressed = function() return false end,
    GetMouseLocation = function() return MOUSE end,
    GetFocusedTextBox = function() return nil end,
    TouchEnabled = false, KeyboardEnabled = true,
})
-- твины: значения ставятся сразу, Completed приходит асинхронно (FLUSH_TWEENS),
-- новый твин тех же свойств отменяет старый (Completed(Cancelled)), как в Roblox
TWEEN_QUEUE, TWEEN_ACTIVE, TWEEN_COUNT = {}, setmetatable({}, { __mode = "k" }), 0
svc("TweenService", { Create = function(_, inst, info, props)
    local tw = { Completed = Signal(), State = "Begin", Info = info }
    function tw.Cancel() if tw.State == "Playing" then tw.State = "Cancelled" end end
    function tw.Play()
        TWEEN_COUNT += 1
        local act = TWEEN_ACTIVE[inst] or {}
        TWEEN_ACTIVE[inst] = act
        for k, v in pairs(props) do
            if act[k] and act[k] ~= tw and act[k].State == "Playing" then act[k].State = "Cancelled" end
            act[k] = tw
            inst[k] = v
        end
        tw.State = "Playing"
        table.insert(TWEEN_QUEUE, tw)
    end
    return tw
end })
function FLUSH_TWEENS()
    local n = 0
    while #TWEEN_QUEUE > 0 do
        local q = TWEEN_QUEUE
        TWEEN_QUEUE = {}
        for _, tw in ipairs(q) do
            n += 1
            if tw.State == "Playing" then tw.State = "Completed" tw.Completed:Fire(Enum.PlaybackState.Completed)
            else tw.Completed:Fire(Enum.PlaybackState.Cancelled) end
        end
        if n > 100000 then error("tween loop") end
    end
end
local guidN = 0
local jsonStore = {}
svc("HttpService", {
    GenerateGUID = function() guidN += 1 return "GUID" .. guidN end,
    JSONEncode = function(_, t) local k = "json#" .. (#jsonStore + 1) jsonStore[#jsonStore + 1] = t return k end,
    JSONDecode = function(_, s) local i = tonumber(s:match("json#(%d+)")) return jsonStore[i] end,
    HttpGet = function() return "" end,
})
svc("RunService", { BindToRenderStep = function() end, UnbindFromRenderStep = function() end })
svc("GuiService", { GetGuiInset = function() return Vector2.new(0, 36), Vector2.new() end })
svc("CoreGui")
svc("Lighting")
svc("CollectionService", { GetTagged = function() return {} end, HasTag = function() return false end,
    GetInstanceAddedSignal = function() return Signal() end, GetInstanceRemovedSignal = function() return Signal() end })
svc("ReplicatedStorage")
svc("Teams")
svc("VirtualInputManager", { SendKeyEvent = function(_, down, k) table.insert(SENT_KEYS, { down, k }) end, SendTouchEvent = function() end })
workspace = svc("Workspace", { Gravity = 196.2, Raycast = function() return nil end, GetServerTimeNow = function() return 0 end })
local cam = newInst("Camera", "Camera")
rawset(cam, "__extra", { ViewportSize = Vector2.new(1280, 720),
    ScreenPointToRay = function(_, x, y) return { Origin = Vector3.new(0, 0, 0), Direction = Vector3.new((x - 640) / 640, (360 - y) / 640, -1) } end,
    WorldToViewportPoint = function(_, p) return Vector3.new(640 + p.X, 360 - p.Y, -p.Z), p.Z < 0 end })
cam.Parent = workspace
rawset(workspace, "__extra", { Gravity = 196.2, Raycast = function() return nil end, GetServerTimeNow = function() return 0 end, CurrentCamera = cam })

game = newInst("DataModel", "game")
rawset(game, "__extra", {
    GetService = function(_, n) return services[n] or svc(n) end,
    HttpGet = function() return "" end,
    GameId = 123,
})

-- executor fs ----------------------------------------------
FILES, FOLDERS = {}, {}
writefile = function(p, d) FILES[p] = d end
readfile = function(p) return FILES[p] end
isfile = function(p) return FILES[p] ~= nil end
isfolder = function(p) return FOLDERS[p] == true end
makefolder = function(p) FOLDERS[p] = true end
delfile = function(p) FILES[p] = nil end
listfiles = function(dir) local o = {} for p in pairs(FILES) do if p:sub(1, #dir + 1) == dir .. "/" then table.insert(o, p) end end return o end
getgenv = function() return _G end
gethui = function() return services.CoreGui end
UserSettings = function() return { IsUserFeatureEnabled = function() return false end } end

function UNKNOWN_PROPS() return unknownProps end
function FIRE(sig, ...) sig:Fire(...) end
warn = function(...) print("WARN:", ...) end
local GENV_ = {}
getgenv = function() return GENV_ end
rawget(cam, "__props").CFrame = CFrame.new()
getcustomasset = function(p) return "rbxasset://custom/" .. p end
