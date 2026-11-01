-- ===== [v81] Smooth camera, Blinded, Anonymous mode, Blur, Low graphics, ESP (corners / HP text / team / tracer origin /
-- max distance), прицел (картинка, смещение, динамика), TOF max distance, Spear aim part, Auto pallet lunge, Sakura =====
FLUSH_TWEENS() RUN_DEFERRED()
local function featureById(id) for _, f in ipairs(Features) do if f.Id == id then return f end end end
if workspace.Parent == nil then workspace.Parent = game end
local LP = game:GetService("Players").LocalPlayer
local LPx = rawget(LP, "__extra")
local oldTeam, oldChar = LPx.Team, LPx.Character

for _, id in ipairs({ "Cam_Smooth", "Cam_StiffOn", "KillerState_Blind", "Hud_Anon", "Hud_AnonAll", "World_Blur", "World_LowGfx",
    "SurvESP_HealthText", "SurvESP_Team", "AutoPallet_Lunge", "Crosshair_Image", "Crosshair_Dynamic" }) do
    assert(Toggles[id], "toggle " .. id)
end
for _, id in ipairs({ "Cam_Deadzone", "Cam_FollowSpeed", "Cam_IdleReturn", "KillerState_BlindColor", "Hud_AnonName", "World_BlurSize",
    "SurvESP_BoxStyle", "SurvESP_TracerOrigin", "SurvESP_MaxDist", "TOFAim_MaxDist", "SpearAim_Part", "Crosshair_ImageId",
    "Crosshair_OffsetX", "Crosshair_Position", "Crosshair_DotShape", "Crosshair_StaticRot", "Crosshair_RainbowSpeed", "Crosshair_PulseAmp" }) do
    assert(Options[id], "option " .. id)
end
local sak = false
for _, v in ipairs(Options.Amb_Particles.Values) do if v == "Sakura" then sak = true end end
assert(sak, "Sakura in Air particles")

local function mkChar(name)
    local m = Instance.new("Model") m.Name = name
    local root = Instance.new("Part") root.Name = "HumanoidRootPart" root.Position = Vector3.new(0, 0, 0) root.Parent = m
    local head = Instance.new("Part") head.Name = "Head" head.Position = Vector3.new(0, 2, 0) head.Parent = m
    local hum = Instance.new("Humanoid") hum.Health = 100 hum.MaxHealth = 100 hum.Parent = m
    return m, root, hum
end

-- Blinded: Blindness > 0 -> тег BLINDED
local km, kRoot = mkChar("Killer")
km:SetAttribute("Blindness", 60)
Targets.Killers = { { Model = km, Root = kRoot, Name = "Killer" } }
Toggles.KillerState_Blind:SetValue(true)
assert(Tags.Map.Head[km] and Tags.Map.Head[km].Slots.Blind and Tags.Map.Head[km].Slots.Blind.Text:find("BLINDED 60%%"), "blinded tag")
km:SetAttribute("Blindness", 0) featureById("KillerBlind_"):Update()
assert(not (Tags.Map.Head[km] and Tags.Map.Head[km].Slots.Blind), "tag removed")
Toggles.KillerState_Blind:SetValue(false)

-- Anonymous mode: своя карточка -> ник, игра меняет текст -> держим, выключили -> настоящее имя
local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:FindFirstChild("PlayerGui")
local hud = Instance.new("ScreenGui") hud.Name = "SurvHud" hud.Parent = pg
local card1 = Instance.new("Frame") card1.Name = "Survivor1" card1.Parent = hud
local lbl1 = Instance.new("TextLabel") lbl1.Name = "TextLabel" lbl1.Text = LP.Name lbl1.Parent = card1
local card2 = Instance.new("Frame") card2.Name = "Survivor2" card2.Parent = hud
local lbl2 = Instance.new("TextLabel") lbl2.Name = "TextLabel" lbl2.Text = "SomeoneElse" lbl2.Parent = card2
Options.Hud_AnonName:SetValue("Ghost")
Toggles.Hud_Anon:SetValue(true)
assert(lbl1.Text == "Ghost" and lbl2.Text == "SomeoneElse", "own name hidden: " .. lbl1.Text)
lbl1.Text = LP.Name
assert(lbl1.Text == "Ghost", "held when the game rewrites it")
Toggles.Hud_AnonAll:SetValue(true)
assert(lbl2.Text == "Player 2", "others hidden: " .. lbl2.Text)
Toggles.Hud_Anon:SetValue(false)
assert(lbl1.Text == LP.Name and lbl2.Text == "SomeoneElse", "names restored")
Toggles.Hud_AnonAll:SetValue(false)
hud:Destroy()

-- Blur effect: свой BlurEffect, No Blur его не прячет
Toggles.World_Blur:SetValue(true)
local blur = ESPUI.OwnBlur
assert(blur and blur.Parent == game:GetService("Lighting"), "own blur in Lighting")
Toggles.World_NoBlur:SetValue(true)
assert(blur.Parent == game:GetService("Lighting"), "No Blur keeps our blur")
Toggles.World_NoBlur:SetValue(false)
Toggles.World_Blur:SetValue(false)
assert(ESPUI.OwnBlur == nil and blur.Parent == nil, "blur removed")

-- Low graphics: материал / наклейки / частицы на карте, при выключении назад
local map = Instance.new("Model") map.Name = "Map" map.Parent = workspace
MapIndex.Bind(map)
local wall = Instance.new("Part") wall.Material = Enum.Material.Brick wall.Parent = map
local dec = Instance.new("Decal") dec.Transparency = 0 dec.Parent = wall
local pe = Instance.new("ParticleEmitter") pe.Enabled = true pe.Parent = wall
Toggles.World_LowGfx:SetValue(true)
RUN_DEFERRED()
assert(wall.Material == Enum.Material.SmoothPlastic and dec.Transparency == 1 and pe.Enabled == false, "low graphics applied")
Toggles.World_LowGfx:SetValue(false)
assert(wall.Material == Enum.Material.Brick and dec.Transparency == 0 and pe.Enabled == true, "low graphics restored")
MapIndex.Bind(nil) map:Destroy()

-- Smooth camera: включается / выключается без ошибок, без персонажа ничего не сдвигает
Toggles.Cam_Smooth:SetValue(true)
featureById("SmoothCam_"):Step()
assert(featureById("SmoothCam_").Applied == nil, "no character -> no offset")
Toggles.Cam_Smooth:SetValue(false)

-- ESP: Team в подписи, Max distance прячет дальних
local sm, sRoot = mkChar("Surv")
sRoot.Position = Vector3.new(0, 0, 50)
Targets.Survivors = { { Model = sm, Root = sRoot, Name = "Surv", Humanoid = sm:FindFirstChildOfClass("Humanoid") } }
Toggles.SurvESP_Team:SetValue(true)
local esp = featureById("SurvESP_")
assert(Tags.Map.Head[sm] and Tags.Map.Head[sm].Slots.SurvESP_.Text:find("SURVIVOR", 1, true), "team label")
Options.SurvESP_MaxDist:SetValue(10) esp:Update()
assert(not (Tags.Map.Head[sm] and Tags.Map.Head[sm].Slots.SurvESP_), "far target hidden by max distance")
Options.SurvESP_MaxDist:SetValue(0) esp:Update()
assert(Tags.Map.Head[sm] and Tags.Map.Head[sm].Slots.SurvESP_, "shown again")
Toggles.SurvESP_Team:SetValue(false)
-- Health text / Corners включают рисунок ESP
Toggles.SurvESP_HealthText:SetValue(true)
assert(featureById("SurvESP_Draw").Active, "health text gates esp draw")
Toggles.SurvESP_HealthText:SetValue(false)
Targets.Survivors = {} Targets.Killers = {}

-- прицел: картинка прячет линии, смещение, мышь
Toggles.Crosshair_Enabled:SetValue(true)
local ch = featureById("Crosshair_")
Toggles.Crosshair_Image:SetValue(true) Options.Crosshair_OffsetX:SetValue(20)
ch:Render()
assert(ch.Img and ch.Img.Visible and ch.Img.Image == "rbxassetid://4463666440", "crosshair image")
assert(ch.Dot.Visible == false and ch.Root.Position.X.Offset == 20, "lines hidden, offset applied")
Options.Crosshair_DotShape:SetValue("Circle") Toggles.Crosshair_Dynamic:SetValue(true) Options.Crosshair_Position:SetValue("Mouse")
ch:Render()
assert(ch.DotCorner ~= nil, "round dot")
Toggles.Crosshair_Image:SetValue(false) Options.Crosshair_OffsetX:SetValue(0) Options.Crosshair_DotShape:SetValue("Square")
Toggles.Crosshair_Dynamic:SetValue(false) Options.Crosshair_Position:SetValue("Center")
ch:Render()
assert(ch.Img.Visible == false and ch.DotCorner == nil, "image off, square dot")
Toggles.Crosshair_Enabled:SetValue(false)

LPx.Team, LPx.Character = oldTeam, oldChar
print("tests_v81 passed")
