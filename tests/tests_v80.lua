-- ===== [v80] Auto Crouch, Auto Pallet, Twist of Fate aim, Aim FX, Smooth camera, Game aura colors, Head dot =====
FLUSH_TWEENS() RUN_DEFERRED()
local function featureById(id) for _, f in ipairs(Features) do if f.Id == id then return f end end end
if workspace.Parent == nil then workspace.Parent = game end
local LP = game:GetService("Players").LocalPlayer
local LPx = rawget(LP, "__extra")
local oldTeam, oldChar = LPx.Team, LPx.Character

local function mkChar(name, hp)
    local m = Instance.new("Model") m.Name = name
    local root = Instance.new("Part") root.Name = "HumanoidRootPart" root.Position = Vector3.new(0, 0, 0) root.Parent = m
    local head = Instance.new("Part") head.Name = "Head" head.Position = Vector3.new(0, 2, 0) head.Parent = m
    local hum = Instance.new("Humanoid") hum.Health = hp or 100 hum.MaxHealth = 100 hum.Parent = m
    return m, root, hum
end

-- UI на месте
for _, id in ipairs({ "AutoCrouch_Enabled", "AutoPallet_Enabled", "TOFAim_Enabled", "AimFX_Circle", "AimFX_Dots", "SpearLand_Info",
    "Cam_Smooth", "GameAura_Enabled", "Hud_HideHealth", "Hud_UnlockCursor", "Crosshair_Pulse", "Crosshair_Rainbow",
    "Crosshair_HideCursor", "SurvESP_HeadDot", "KillerESP_HeadDot" }) do
    assert(Toggles[id], "toggle " .. id)
end
for _, id in ipairs({ "AutoCrouch_Radius", "AutoPallet_Radius", "AutoPallet_Reach", "TOFAim_FOV", "TOFAim_Part", "Cam_Stiffness",
    "Crosshair_Spin", "GameAura_Gen", "GameAura_Killer", "GameAura_Blood", "SurvESP_HeadDotColor" }) do
    assert(Options[id], "option " .. id)
end

-- Auto Crouch: киллер в радиусе -> зажали клавишу приседа игры (LeftControl), ушёл -> отпустили
local me, myRoot = mkChar("Me", 100)
LPx.Character, LPx.Team = me, { Name = "Survivors" }
local km, kRoot = mkChar("Killer", 100)
rawset(kRoot, "__extra", { CFrame = { LookVector = Vector3.new(0, 0, -1) } })
kRoot.Position = Vector3.new(0, 0, 10)
Targets.Killers = { { Model = km, Root = kRoot, Name = "Killer" } }
table.clear(SENT_KEYS)
Toggles.AutoCrouch_Enabled:SetValue(true)
local ac = featureById("AutoCrouch_")
ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 1 and SENT_KEYS[1][1] == true and SENT_KEYS[1][2] == Enum.KeyCode.LeftControl, "crouch key held")
kRoot.Position = Vector3.new(0, 0, 500)
ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 2 and SENT_KEYS[2][1] == false, "crouch key released when killer leaves")
-- HP <= 50: игра не даёт сесть - не жмём
kRoot.Position = Vector3.new(0, 0, 10)
me:FindFirstChildOfClass("Humanoid").Health = 40
ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 2, "no crouch at 40 HP")
me:FindFirstChildOfClass("Humanoid").Health = 100
-- режим crouchtoggle: нажали-отпустили один раз, сели -> больше не жмём
LP:SetAttribute("crouchtoggle", true)
table.clear(SENT_KEYS)
ac.PressAt = 0 ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 2 and SENT_KEYS[1][1] == true and SENT_KEYS[2][1] == false, "toggle mode: tap")
me:SetAttribute("Crouching", true)
ac.PressAt = 0 ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 2, "toggle mode: already crouched")
kRoot.Position = Vector3.new(0, 0, 500)
ac.PressAt = 0 ac.TickAt = 0 ac:Tick()
assert(#SENT_KEYS == 4, "toggle mode: tap again to stand up (we crouched)")
me:SetAttribute("Crouching", nil) LP:SetAttribute("crouchtoggle", nil)
Toggles.AutoCrouch_Enabled:SetValue(false)

-- Auto Pallet: у стоящей паллеты, киллер близко и сближается -> droppallet (Space)
local map = Instance.new("Model") map.Name = "Map" map.Parent = workspace
MapIndex.Bind(map)
local pal = Instance.new("Model") pal.Name = "Newpallet" pal:SetAttribute("PalletState", "Upright") pal.Parent = map
local intact = Instance.new("Model") intact.Name = "Intact" intact.Parent = pal
local board = Instance.new("Part") board.Name = "Pallet" board.Position = Vector3.new(2, 0, 0) board.Parent = intact
FIRE(map.DescendantAdded, pal)
assert(#Collect.Pallets() == 1, "pallet collected")
table.clear(SENT_KEYS)
Toggles.AutoPallet_Enabled:SetValue(true)
local ap = featureById("AutoPallet_")
kRoot.Position = Vector3.new(0, 0, 8)
ap.TickAt = 0 ap:Tick() -- первая точка истории сближения
kRoot.Position = Vector3.new(0, 0, 6)
ap.Hist[km].T = os.clock() - 1
ap.TickAt = 0 ap:Tick()
RUN_DEFERRED()
assert(#SENT_KEYS == 2 and SENT_KEYS[1][2] == Enum.KeyCode.Space and SENT_KEYS[1][1] == true and SENT_KEYS[2][1] == false, "pallet dropped: " .. #SENT_KEYS)
-- упавшая паллета - не жмём
pal:SetAttribute("PalletState", "Dropped") ap.LastAt = 0
ap.Hist[km] = { T = os.clock() - 1, D = 9 }
ap.TickAt = 0 ap:Tick() RUN_DEFERRED()
assert(#SENT_KEYS == 2, "dropped pallet ignored")
Toggles.AutoPallet_Enabled:SetValue(false)
MapIndex.Bind(nil) map:Destroy()

-- Twist of Fate aim: только при Aiming + Twist of Fate; пишет AimState для круга / точек
Toggles.TOFAim_Enabled:SetValue(true)
local tof = featureById("TOFAim_")
ESPUI.AimState = nil
tof:Step()
assert(ESPUI.AimState == nil, "not aiming -> nothing")
LP:SetAttribute("EquippedItem", "Twist of Fate") me:SetAttribute("Aiming", true)
Options.TOFAim_FOV:SetValue(180) Toggles.TOFAim_WallCheck:SetValue(false)
kRoot.Position = Vector3.new(0, 0, -20) -- перед камерой (мок: LookVector камеры ~ -Z)
tof:Step()
assert(ESPUI.AimState and ESPUI.AimState.FOV == 180, "aim state written")
LP:SetAttribute("EquippedItem", nil) me:SetAttribute("Aiming", nil)
Toggles.TOFAim_Enabled:SetValue(false)

-- Aim FX: круг и точки из AimState
Toggles.AimFX_Circle:SetValue(true) Toggles.AimFX_Dots:SetValue(true)
local fx = featureById("AimFX_")
ESPUI.AimState = { At = os.clock(), FOV = 60, List = Targets.Killers, Target = km }
fx:Render()
assert(fx.Circle.Visible == true and fx.Circle.Size.X.Offset > 0, "fov circle shown")
ESPUI.AimState.At = os.clock() - 5 fx:Render()
assert(fx.Circle.Visible == false, "circle hidden when no aim helper works")
ESPUI.SpearInfo = { At = os.clock(), Pos = Vector3.new(0, 0, -30), T = 0.42, From = Vector3.new(0, 0, 0) }
Toggles.SpearLand_Info:SetValue(true) fx:Render()
assert(fx.Info.Visible == true and fx.Info.Text:find("0.42s", 1, true), "spear info: " .. tostring(fx.Info.Text))
Toggles.AimFX_Circle:SetValue(false) Toggles.AimFX_Dots:SetValue(false) Toggles.SpearLand_Info:SetValue(false)
assert(not fx.Active, "aim fx off")

-- Smooth camera: CameraStiffness держится, при выключении - назад
local smc = Instance.new("Folder") smc.Name = "SmoothCamera" smc:SetAttribute("CameraStiffness", 8) smc.Parent = me
Toggles.Cam_StiffOn:SetValue(true)
assert(smc:GetAttribute("CameraStiffness") == Options.Cam_Stiffness.Value, "stiffness set")
Toggles.Cam_StiffOn:SetValue(false)
assert(smc:GetAttribute("CameraStiffness") == 8, "stiffness restored")

-- Game aura colors: атрибуты LocalPlayer, игра меняет -> держим своё, при выключении - последнее значение игры
LP:SetAttribute("genaura", Color3.new(0, 0, 1))
Toggles.GameAura_Enabled:SetValue(true)
assert(LP:GetAttribute("genaura") == Options.GameAura_Gen.Value and LP:GetAttribute("killeraura") == Options.GameAura_Killer.Value, "aura colors set")
LP:SetAttribute("genaura", Color3.new(0, 1, 0))
assert(LP:GetAttribute("genaura") == Options.GameAura_Gen.Value, "aura held")
Toggles.GameAura_Enabled:SetValue(false)
assert(LP:GetAttribute("genaura"):ToHex() == "00ff00" and LP:GetAttribute("killeraura") == nil, "aura restored")

-- Head dot: у рисунка ESP есть кружок, включение по HeadDot
Targets.Survivors = { { Model = km, Root = kRoot, Name = "S", Humanoid = km:FindFirstChildOfClass("Humanoid") } }
Toggles.SurvESP_HeadDot:SetValue(true)
local draw = featureById("SurvESP_Draw")
assert(draw.Active and draw.Draw[km] and draw.Draw[km].HeadDot, "head dot frame created")
Toggles.SurvESP_HeadDot:SetValue(false)
Targets.Survivors = {} Targets.Killers = {}

-- Crosshair: вращение / пульс / радуга без ошибок
Toggles.Crosshair_Enabled:SetValue(true)
local ch = featureById("Crosshair_")
Options.Crosshair_Spin:SetValue(90) Toggles.Crosshair_Pulse:SetValue(true) Toggles.Crosshair_Rainbow:SetValue(true)
ch:Render()
assert(ch.Scale ~= nil, "pulse scale")
Options.Crosshair_Spin:SetValue(0) Toggles.Crosshair_Pulse:SetValue(false) Toggles.Crosshair_Rainbow:SetValue(false)
ch:Render()
assert(ch.Root.Rotation == 0, "no spin")
Toggles.Crosshair_Enabled:SetValue(false)

-- Hide health / Unlock cursor включаются и выключаются без ошибок
Toggles.Hud_HideHealth:SetValue(true) Toggles.Hud_HideHealth:SetValue(false)
Toggles.Hud_UnlockCursor:SetValue(true) Toggles.Hud_UnlockCursor:SetValue(false)

LPx.Team, LPx.Character = oldTeam, oldChar
print("tests_v80 passed")
