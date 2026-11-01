-- ===== [v78] Hook ESP, Killer info, прицел при прицеливании, косметика, фикс OnScreen автопарри =====
FLUSH_TWEENS() RUN_DEFERRED()
local function featureById(id) for _, f in ipairs(Features) do if f.Id == id then return f end end end
if workspace.Parent == nil then workspace.Parent = game end
local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
local oldTeam, oldChar = LPx.Team, LPx.Character

-- 1. Hook ESP: Map.Hook -> общий Highlight по копиям деталей
local map = Instance.new("Model") map.Name = "Map" map.Parent = workspace
MapIndex.Bind(map)
local hook = Instance.new("Model") hook.Name = "Hook" hook.Parent = map
-- (мок: Size типа Vector3 разрешён только у Part, поэтому вместо MeshPart - Part)
local mesh = Instance.new("Part") mesh.Name = "Hook.001" mesh.Transparency = 0 mesh.Size = Vector3.new(1, 4, 1) mesh.Parent = hook
local point = Instance.new("Part") point.Name = "HookPoint" point.Transparency = 1 point.Size = Vector3.new(1, 1, 1) point.Parent = hook
FIRE(map.DescendantAdded, hook) FIRE(map.DescendantAdded, mesh) FIRE(map.DescendantAdded, point)
assert(MapIndex.Sets.Hooks[hook], "hook indexed")
local hooks = Collect.Hooks()
assert(#hooks == 1 and hooks[1] == hook, "Collect.Hooks")
assert(Toggles.HookChams_Enabled and Options.HookChams_Color, "hook ui")
Toggles.HookChams_Enabled:SetValue(true)
local hf = featureById("HookChams_")
assert(hf and hf.Active, "hook chams active")
local grp
for _, g in ipairs(HighlightGroup.All) do if g.Static and g.Desired and g.Desired[1] == hook then grp = g end end
assert(grp and grp.Group and grp.Ghosts[hook], "static highlight group for hooks")
local nParts = 0 for _ in pairs(grp.Ghosts[hook].Parts) do nParts += 1 end
assert(nParts == 1, "only visible hook mesh copied (HookPoint is invisible): " .. nParts)
Toggles.HookChams_Enabled:SetValue(false)
assert(grp.Group == nil and next(grp.Ghosts) == nil, "hook chams cleared")
MapIndex.Bind(nil) map:Destroy()

-- 3. Killer info: новый киллер -> текст с ником, персонажем и платформой; плавно гаснет
local kp = Instance.new("Player") kp.Name = "BadGuy"
kp:SetAttribute("SelectedKiller", "Veil") kp:SetAttribute("platform", "Mobile")
local km = Instance.new("Model") km.Name = "BadGuy"
local kRoot = Instance.new("Part") kRoot.Name = "HumanoidRootPart" kRoot.Parent = km
Targets.Killers = { { Model = km, Player = kp, Name = "BadGuy", Root = kRoot } }
LPx.Team = { Name = "Survivors" }
Toggles.Hud_KillerInfo:SetValue(true)
local ki = featureById("KillerInfo_")
assert(ki.Active and ki.Label, "killer info active")
assert(ki.Label.Text:find("BadGuy", 1, true) and ki.Label.Text:find("Veil", 1, true) and ki.Label.Text:find("Mobile", 1, true), "killer info text: " .. ki.Label.Text)
ki.At = os.clock() - 1 ki:Render()
assert(ki.Label.TextTransparency == 0, "shown")
ki.At = os.clock() - 100 ki:Render()
assert(ki.Label.TextTransparency == 1, "faded")
ki.Label.Text = "" ki:Update()
assert(ki.Label.Text == "", "same killer is shown once")
-- ты киллер: по умолчанию не показываем
local km2 = Instance.new("Model") km2.Name = "Other"
LPx.Team = { Name = CONFIG.Teams.Killer }
Targets.Killers = { { Model = km2, Player = nil, Name = "Other" } }
ki:Update()
assert(ki.Label.Text == "", "not shown when you are the killer")
Library.StreamerMode = true
local km3 = Instance.new("Model") km3.Name = "Third"
LPx.Team = { Name = "Survivors" }
Targets.Killers = { { Model = km3, Player = nil, Name = "Third" } }
ki:Update()
assert(not ki.Label.Text:find("Third", 1, true) and ki.Label.Text:find("Killer", 1, true), "streamer mode hides the name")
Library.StreamerMode = false
Toggles.Hud_KillerInfo:SetValue(false)
assert(not ki.Active and ki.Label == nil, "killer info off")
Targets.Killers = {}

-- 4. прицел только при прицеливании
local me = Instance.new("Model") me.Name = "Me"
LPx.Character = me
Toggles.Crosshair_Enabled:SetValue(true)
local ch = featureById("Crosshair_")
ch:Render()
assert(ch.Root.Visible == true, "crosshair always visible by default")
Toggles.Crosshair_OnlyAim:SetValue(true)
ch:Render()
assert(ch.Root.Visible == false, "hidden while not aiming")
me:SetAttribute("Aiming", true) ch:Render()
assert(ch.Root.Visible == true, "shown while aiming")
Toggles.Crosshair_AimTOF:SetValue(true) ch:Render()
assert(ch.Root.Visible == false, "TOF only: other item hidden")
game:GetService("Players").LocalPlayer:SetAttribute("EquippedItem", "Twist of Fate") ch:Render()
assert(ch.Root.Visible == true, "TOF only: twist of fate shown")
me:SetAttribute("Aiming", nil) me:SetAttribute("spearmode", true)
game:GetService("Players").LocalPlayer:SetAttribute("EquippedItem", nil) ch:Render()
assert(ch.Root.Visible == true, "killer spear mode shown")
Toggles.Crosshair_AimTOF:SetValue(false) Toggles.Crosshair_OnlyAim:SetValue(false) Toggles.Crosshair_Enabled:SetValue(false)


-- 6b. аптечка DBD
local band = Instance.new("Model") band.Name = "Bandage" band.Parent = me
local arm = Instance.new("Model") arm.Name = "Right Arm" arm.Parent = band
local weld = Instance.new("Motor6D") weld.Name = "MeshPartweld" weld.C1 = CFrame.new() weld.Parent = arm
local inner = Instance.new("Model") inner.Name = "Bandage" inner.Parent = arm
local mp = Instance.new("Part") mp.Name = "MeshPart" mp.MeshId = "rbxassetid://5" mp.Size = Vector3.new(1, 1, 1) -- (мок: Part)
mp.Color = Color3.new(1, 1, 1) mp.Material = Enum.Material.Plastic mp.Parent = inner
Toggles.Cos_Medkit:SetValue(true)
assert(mp.MeshId == "rbxassetid://91599546902559" and mp.Material == Enum.Material.Wood, "medkit applied")
local sz = mp.Size
featureById("CosMedkit_"):Update()
assert(mp.Size.X == sz.X and math.abs(sz.X - 0.9) < 1e-6, "applied once (size not shrunk again)")
Toggles.Cos_Medkit:SetValue(false)
assert(mp.MeshId == "rbxassetid://5" and mp.Material == Enum.Material.Plastic and mp.Size.X == 1, "medkit restored")

-- 6c. Triple T: в моке нет game:GetObjects -> уведомление, тело не трогаем, без ошибок
local torso = Instance.new("Part") torso.Name = "Torso" torso.Transparency = 0 torso.Parent = me
Toggles.Cos_TripleT:SetValue(true)
RUN_DEFERRED()
assert(torso.Transparency == 0 and featureById("CosTripleT_").Model == nil, "no model -> body untouched")
Toggles.Cos_TripleT:SetValue(false)

-- фикс OnScreen: киллер на экране -> парри жмётся, за спиной -> нет
local ap = featureById("AutoParry_")
local pressed = 0
local origPress = ap.Press
ap.Press = function() pressed += 1 end
Options.AutoParry_Chance:SetValue(100) Options.AutoParry_Delay:SetValue(0) Options.AutoParry_React:SetValue(0)
Toggles.AutoParry_Humanize:SetValue(false) Toggles.AutoParry_PingComp:SetValue(false)
Toggles.AutoParry_OnScreen:SetValue(true)
local kr = Instance.new("Part") kr.Position = Vector3.new(0, 0, -10)
ap:Fire(me, nil, nil, nil, { Root = kr }, "test", 5)
assert(pressed == 1, "on-screen killer -> parry pressed (v78 fix)")
kr.Position = Vector3.new(0, 0, 10)
ap:Fire(me, nil, nil, nil, { Root = kr }, "test", 5)
assert(pressed == 1 and ap.LastFire == -math.huge, "killer behind -> no press")
ap.Press = origPress
Toggles.AutoParry_OnScreen:SetValue(false)

LPx.Team, LPx.Character = oldTeam, oldChar
print("tests_v78 passed")
