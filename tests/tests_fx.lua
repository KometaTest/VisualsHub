-- ===== effects tests =====
-- [v48] skeet: окно непрозрачное, без теней и свечения; прозрачность и блюр - по настройке в Config
FLUSH_TWEENS()
local SG = Library.ScreenGui
local MainF = SG:FindFirstChild("Main")
local BodyF = MainF:FindFirstChild("Body")
local Lighting = game:GetService("Lighting")
local Cam = workspace.CurrentCamera
local function dofs() local o = {} for _, c in ipairs(Lighting:GetChildren()) do if c.ClassName == "DepthOfFieldEffect" then table.insert(o, c) end end return o end
local function glass() for _, c in ipairs(Cam:GetChildren()) do if c.ClassName == "Part" and c.Material == Enum.Material.Glass then return c end end end
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end

-- рамка skeet: 5 колец по 1px внутри Body, внутри - Inner (фон контента)
local inner = Library._Inner
assert(inner and inner.Name == "Inner", "inner frame")
local depth, p = 0, inner.Parent
while p and p ~= BodyF do depth += 1 p = p.Parent end
assert(p == BodyF and depth == 5, "5 border rings: " .. depth)
-- [v50] рамка оригинала: 12 / 70 / 40 / 40 / 70 / 0
assert(string.lower(BodyF.BackgroundColor3:ToHex()) == "0c0c0c", "outer ring 12")
local ringHex = {}
p = inner.Parent
while p ~= BodyF do table.insert(ringHex, 1, string.lower(p.BackgroundColor3:ToHex())) p = p.Parent end
assert(table.concat(ringHex, ",") == "464646,282828,282828,464646,000000", "rings 70/40/40/70/0: " .. table.concat(ringHex, ","))
assert(inner:FindFirstChild("Pattern"), "skeet background pattern")
assert(find(inner, function(d) return d.Name == "Rainbow" end), "rainbow line on top")
-- без тени
assert(BodyF:FindFirstChild("FX_shadow") == nil, "no window shadow")
-- непрозрачно по умолчанию; прозрачность из настройки ложится на фон контента и колонку вкладок
assert(inner.BackgroundTransparency == 0, "opaque by default")
local side = inner:FindFirstChild("Side")
assert(side and side.Size.X.Offset == 75 and side.BackgroundTransparency == 0, "tab column 75px") -- [v54] по Menu.cpp
Options.ThemeManager_Transparency:SetValue(10)
assert(math.abs(inner.BackgroundTransparency - 0.1) < 1e-9 and math.abs(side.BackgroundTransparency - 0.1) < 1e-9, "transparency applied")
Options.ThemeManager_Transparency:SetValue(0)
assert(inner.BackgroundTransparency == 0, "back to opaque")

-- чекбоксы: квадрат с градиентом акцента, без свечения
local onT, offT
for _, t in pairs(Toggles) do
    if t.Right then
        if t.Value and not onT then onT = t elseif not t.Value and not offT then offT = t end
    end
end
assert(onT and offT, "have on/off toggles")
local function gradOf(t)
    for _, c in ipairs(t.Row:GetChildren()) do
        if c.ClassName == "Frame" and c.Size.X.Offset == 6 and c.Size.Y.Offset == 6 then return c:FindFirstChildOfClass("UIGradient") end -- [v49] 6x6 + рамка
    end
end
assert(gradOf(onT) and gradOf(onT).Color[1] == Library.Scheme.AccentColor, "on box uses accent")
assert(gradOf(offT).Color[1] == Library.Scheme.OffTrack, "off box grey")
assert(not find(onT.Row, function(d) return d.Name == "FX_glow" end), "no glow")
offT:SetValue(true)
assert(gradOf(offT).Color[1] == Library.Scheme.AccentColor, "box follows value")
offT:SetValue(false)
assert(Toggles.ThemeManager_Glow == nil, "glow setting removed")

-- блюр (по умолчанию выключен): включается настройкой, стекло под окном, чужой DoF выключен и потом возвращён
local gameDof = Instance.new("DepthOfFieldEffect")
gameDof.Enabled = true
gameDof.Parent = Lighting
assert(Library.Blur == false and glass() == nil, "blur off by default")
Toggles.ThemeManager_Blur:SetValue(true)
assert(glass() ~= nil, "blur setting on")
local gp = glass()
assert(gp.Transparency == 0.98, "glass part in camera")
assert(#dofs() == 2 and gameDof.Enabled == false, "our dof added, game dof disabled")
FIRE(game:GetService("RunService").RenderStepped, 0.016)
local mesh = gp:FindFirstChildOfClass("SpecialMesh")
assert(mesh and mesh.Scale and mesh.Scale.X > 0 and mesh.Scale.Y > 0, "glass sized to window")
Library:Toggle(false)
assert(glass() == nil and gameDof.Enabled == true, "blur off immediately on close, game dof restored")
FLUSH_TWEENS()
Library:Toggle(true)
assert(glass() == nil, "blur waits for open anim")
FLUSH_TWEENS()
assert(glass() ~= nil, "blur back after open")
glass():Destroy()
FIRE(game:GetService("RunService").RenderStepped, 0.016)
assert(glass() ~= nil, "glass rebuilt")
Toggles.ThemeManager_Blur:SetValue(false)
assert(glass() == nil and gameDof.Enabled, "blur setting off")

-- popup: непрозрачный, без тени, вплотную под полем
local popups = SG:FindFirstChild("Popups")
local cfgBtn
for _, d in ipairs(MainF:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "default" then cfgBtn = d.Parent end end
cfgBtn = cfgBtn or Options.ThemeManager_Theme.Row:FindFirstChildOfClass("TextButton") -- [v49] нижней строки нет
FIRE(cfgBtn.MouseButton1Click) FLUSH_TWEENS()
local pf = popups:GetChildren()[2]
assert(pf:FindFirstChild("FX_shadow") == nil and pf.BackgroundTransparency == 0, "popup opaque, no shadow")
assert(pf:FindFirstChildOfClass("UIStroke"), "popup outline")
Library:ClosePopup() FLUSH_TWEENS()
assert(#popups:GetChildren() == 0, "popup gone")
-- открытие/закрытие: только прозрачность, масштаб не меняется
local s0 = Library._UIScale.Scale
Library:Toggle(false)
assert(BodyF.Parent.ClassName == "CanvasGroup" and math.abs(Library._UIScale.Scale - s0) < 1e-9, "fade only, no zoom")
FLUSH_TWEENS()
Library:Toggle(true) FLUSH_TWEENS()
-- тема сохраняет эффекты
ThemeManager:Save()
gameDof:Destroy()
print("FX TESTS PASSED")

-- [v51] растягивание окна за правый нижний угол (как у skeet)
do
    local grip = Library._Inner:FindFirstChild("ResizeGrip")
    assert(grip and grip.ClassName == "TextButton", "resize grip in the corner")
    local UIS_ = game:GetService("UserInputService")
    local MB1 = Enum.UserInputType.MouseButton1
    local w0, h0 = MainF.Size.X.Offset, MainF.Size.Y.Offset
    local p0 = MainF.Position
    local sc = Library._UIScale.Scale
    FIRE(grip.InputBegan, { UserInputType = MB1, Position = Vector3.new(500, 500, 0) })
    FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(500 + 100 * sc, 500 + 40 * sc, 0) })
    assert(MainF.Size.X.Offset == w0 + 100 and MainF.Size.Y.Offset == h0 + 40, "resized: " .. MainF.Size.X.Offset .. "x" .. MainF.Size.Y.Offset)
    -- [v79] левый верхний угол на месте: на время тяги якорь (0, 0), позиция не меняется - только размер (без тряски)
    assert(MainF.AnchorPoint.X == 0 and MainF.AnchorPoint.Y == 0, "anchor top-left while resizing")
    local pd = MainF.Position
    FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(500 + 101 * sc, 500 + 41 * sc, 0) })
    assert(MainF.Position.X.Offset == pd.X.Offset and MainF.Position.Y.Offset == pd.Y.Offset, "top-left corner kept (position untouched)")
    -- пределы
    FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(-5000, -5000, 0) })
    assert(MainF.Size.X.Offset == 600 and MainF.Size.Y.Offset == 440, "min size")
    FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(9000, 9000, 0) })
    assert(MainF.Size.X.Offset == 1200 and MainF.Size.Y.Offset == 900, "max size")
    FIRE(UIS_.InputEnded, { UserInputType = MB1, Position = Vector3.new(9000, 9000, 0) })
    assert(MainF.AnchorPoint.X == 0.5 and MainF.AnchorPoint.Y == 0.5 and MainF.Position.X.Scale == 0.5, "[v79] anchor back to center after release")
    -- размер сохраняется в theme_skeet.json и загружается
    local saved
    for path, data in pairs(FILES) do if path:match("theme_skeet%.json$") then saved = game:GetService("HttpService"):JSONDecode(data) end end
    assert(saved and saved.menuW == 1200 and saved.menuH == 900, "size saved")
    Library:SetMenuSize(w0, h0)
    assert(MainF.Size.X.Offset == w0 and Library.MenuSize.W == w0, "size restored")
    print("RESIZE TESTS PASSED")
end
