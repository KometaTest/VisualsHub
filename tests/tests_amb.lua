
-- ===== ambience tests =====
FLUSH_TWEENS() RUN_DEFERRED()
local SG = Library.ScreenGui
local MainF = SG:FindFirstChild("Main")
local L = game:GetService("Lighting")
local function lchild(class) for _, c in ipairs(L:GetChildren()) do if c.ClassName == class then return c end end end
local function count(class) local n = 0 for _, c in ipairs(L:GetChildren()) do if c.ClassName == class then n += 1 end end return n end
L.Ambient = Color3.fromRGB(10, 20, 30)
L.OutdoorAmbient = Color3.fromRGB(10, 20, 30)
L.Brightness = 1
L.ClockTime = 14

-- [v75] кнопки Ambience и панели нет: всё прямо в World > Environment, выбора игры нет
Tabs.Players:SelectSub(Tabs.World) Window:SelectTab(Tabs.Players) FLUSH_TWEENS() -- [v73] World - подвкладка Visuals
local function hasText(root, t) for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == t then return d end end end
local ov = Tabs.World.Scroll
for _, d in ipairs(MainF:GetDescendants()) do assert(d.Name ~= "Overlay", "no ambience overlay") end
for _, t in ipairs({ "Environment", "Delete Fog", "Nightmode", "Fullbright", "Override Sky", "Custom skybox", "Skybox", "Override Sunlight",
    "Override Fog", "Override DoF", "Color grading", "Bloom", "Sun rays", "Weather" }) do
    assert(hasText(ov, t), "environment has " .. t)
end
for _, t in ipairs({ "Ambience", "Map Selection", "Removals", "+ Add" }) do assert(not hasText(ov, t), "removed: " .. t) end

-- Nightmode -> ColorCorrection с цветом
Toggles.Amb_Night:SetValue(true)
local cc = lchild("ColorCorrectionEffect")
assert(cc and cc.TintColor:ToHex() == Options.Amb_NightColor.Value:ToHex(), "nightmode cc")
Options.Amb_NightColor:SetValueRGB(Color3.fromRGB(50, 60, 90))
assert(lchild("ColorCorrectionEffect").TintColor:ToHex() == "323c5a", "nightmode color live")
Toggles.Amb_Night:SetValue(false)
assert(count("ColorCorrectionEffect") == 0, "nightmode off")

-- [v67] Nightmode: Props - красим только детали карты, без фильтра на экран; выкл - цвета возвращаются
do
    local map = Instance.new("Model") map.Name = "Map" map.Parent = workspace
    local prop = Instance.new("Part") prop.Color = Color3.new(1, 1, 1) prop.Parent = map
    MapIndex.Map = map
    Options.Amb_NightMode:SetValue("Props")
    Toggles.Amb_Night:SetValue(true)
    FLUSH_TWEENS()
    assert(count("ColorCorrectionEffect") == 0, "props: no screen filter")
    assert(prop.Color:ToHex() ~= "ffffff", "props: map part tinted " .. prop.Color:ToHex())
    Options.Amb_NightMode:SetValue("Both")
    assert(count("ColorCorrectionEffect") == 1, "both: filter too")
    Toggles.Amb_Night:SetValue(false)
    assert(prop.Color:ToHex() == "ffffff", "props restored")
    Options.Amb_NightMode:SetValue("Atmosphere")
    map.Parent = nil MapIndex.Map = nil
end

-- Fullbright: держит Ambient и возвращает оригинал
Toggles.Amb_Full:SetValue(true)
assert(L.Ambient:ToHex() == Options.Amb_FullColor.Value:ToHex() and L.Brightness == 2, "fullbright on")
L.Ambient = Color3.new(0, 0, 0) -- игра пытается вернуть свой свет
assert(L.Ambient:ToHex() == Options.Amb_FullColor.Value:ToHex(), "fullbright holds")
Toggles.Amb_Full:SetValue(false)
assert(L.Ambient:ToHex() == "000000" and L.Brightness == 1, "fullbright restores the game's latest light")

-- Override Sky: время суток
Toggles.Amb_Sky:SetValue(true)
Options.Amb_SkyTime:SetValue(22)
assert(L.ClockTime == 22, "sky time")
Toggles.Amb_Sky:SetValue(false)
assert(L.ClockTime == 14, "sky restored")

-- Override Fog выключает Delete Fog и наоборот
Toggles.World_NoFog:SetValue(true)
Toggles.Amb_Fog:SetValue(true)
assert(Toggles.World_NoFog.Value == false, "fog override turns off Delete Fog")
local atm = lchild("Atmosphere")
assert(atm and math.abs(atm.Density - 0.35) < 1e-6 and atm.Color:ToHex() == Options.Amb_FogColor.Value:ToHex(), "fog atmosphere")
Options.Amb_FogDensity:SetValue(80)
assert(math.abs(lchild("Atmosphere").Density - 0.8) < 1e-6, "fog density live")
Toggles.World_NoFog:SetValue(true)
assert(count("Atmosphere") == 0 or lchild("Atmosphere").Density == 0, "Delete Fog wins, our atmosphere removed")
Toggles.World_NoFog:SetValue(false)
Toggles.Amb_Fog:SetValue(false)

-- DoF
-- (в Lighting есть ещё DoF блюра меню - наш отличается FocusDistance = 20)
local function ourDof() for _, c in ipairs(L:GetChildren()) do if c.ClassName == "DepthOfFieldEffect" and c.FocusDistance == 20 then return c end end end
Toggles.Amb_DoF:SetValue(true)
local dof = ourDof()
assert(dof and dof.FarIntensity == 0.5 and dof.NearIntensity == 0, "dof far")
Toggles.Amb_DoFNear:SetValue(true)
assert(ourDof().NearIntensity == 0.5, "dof near")
Toggles.Amb_DoF:SetValue(false)
assert(ourDof() == nil, "dof off")

-- Weather: частицы над камерой
Toggles.Amb_Rain:SetValue(true)
local cam = workspace.CurrentCamera
local wpart
for _, c in ipairs(cam:GetChildren()) do if c.ClassName == "Part" and c:FindFirstChildOfClass("ParticleEmitter") then wpart = c end end
assert(wpart, "rain particles")
Toggles.Amb_Rain:SetValue(false)
wpart = nil
for _, c in ipairs(cam:GetChildren()) do if c.ClassName == "Part" and c:FindFirstChildOfClass("ParticleEmitter") then wpart = c end end
assert(wpart == nil, "rain off")

-- погода: частицы лицом к камере, размер и ветер настраиваются
local function emitters()
    local o = {}
    for _, c in ipairs(workspace.CurrentCamera:GetChildren()) do
        if c.ClassName == "Part" then for _, e in ipairs(c:GetChildren()) do if e.ClassName == "ParticleEmitter" then table.insert(o, e) end end end
    end
    return o
end
Toggles.Amb_Rain:SetValue(true)
local re = emitters()[1]
assert(re.Orientation == Enum.ParticleOrientation.FacingCameraWorldUp, "rain faces camera, upright")
local size1 = re.Size[1]
Options.Amb_WeatherSize:SetValue(200)
re = emitters()[1]
assert(re.Size[1] == size1 * 2, "size slider scales drops")
Options.Amb_WeatherWind:SetValue(50)
assert(emitters()[1].Acceleration.X > 0, "wind tilts rain")
Toggles.Amb_Snow:SetValue(true)
assert(#emitters() == 2, "rain + snow")
local sn
for _, e in ipairs(emitters()) do if e.Orientation == Enum.ParticleOrientation.FacingCamera then sn = e end end
assert(sn and sn.Lifetime[1] >= 8, "snow slow, facing camera")
Toggles.Amb_Rain:SetValue(false) Toggles.Amb_Snow:SetValue(false)
Options.Amb_WeatherSize:SetValue(100) Options.Amb_WeatherWind:SetValue(0)
assert(#emitters() == 0, "weather off")

-- «...» у Override Fog: панель со слайдерами одалживается в popup и возвращается
local popups = SG:FindFirstChild("Popups")
local fogRow = hasText(ov, "Override Fog").Parent
local dotsBtn
for _, d in ipairs(fogRow:GetDescendants()) do
    if d.ClassName == "TextButton" and #d:GetChildren() == 3 then dotsBtn = d end
end
assert(dotsBtn, "fog dots button")
FIRE(dotsBtn.MouseButton1Click) FLUSH_TWEENS()
local pop = popups:GetChildren()[2]
assert(pop and hasText(pop, "Density") and hasText(pop, "Glow Radius"), "fog settings popup")
Library:ClosePopup() FLUSH_TWEENS()
assert(#popups:GetChildren() == 0, "settings popup closed")
assert(Options.Amb_FogDensity.Value == 80, "settings values kept")

-- конфиги не трогают настройки окружения (они в ambience.json)
assert(SaveManager.Ignore.Amb_Night and SaveManager.Ignore.Amb_Skybox, "ambience ignored by configs")

-- [v75] свой скайбокс: прячет небо игры, ставит своё с 6 гранями; выкл - небо игры возвращается
do
    local gameSky = Instance.new("Sky") gameSky.Parent = L
    assert(table.find(Options.Amb_SkyboxName.Values, "Night") and table.find(Options.Amb_SkyboxName.Values, "Sunset"), "builtin skyboxes listed")
    Toggles.Amb_Skybox:SetValue(true)
    local ours = lchild("Sky")
    assert(gameSky.Parent == nil and ours and ours ~= gameSky, "game sky hidden, ours added")
    assert(string.find(tostring(ours.SkyboxBk), "Night_Bk", 1, true) and string.find(tostring(ours.SkyboxUp), "Night_Up", 1, true), "faces: " .. tostring(ours.SkyboxBk))
    assert(isfile(CONFIG.ScriptName .. "/skybox/_builtin/Night_Ft.png"), "face written")
    Options.Amb_SkyboxName:SetValue("Sunset")
    assert(string.find(tostring(lchild("Sky").SkyboxFt), "Sunset_Ft", 1, true), "switch preset")
    -- своя картинка: skybox/<имя>.png - на все грани
    writefile(CONFIG.ScriptName .. "/skybox/Mine.png", "x")
    Ambience.ClearSkyCache()
    assert(table.find(Ambience.SkyNames(), "Mine"), "own picture listed")
    Options.Amb_SkyboxName:SetValue("Mine")
    local s2 = lchild("Sky")
    assert(string.find(tostring(s2.SkyboxDn), "Mine.png", 1, true) and s2.SkyboxDn == s2.SkyboxUp, "own picture on all faces")
    Toggles.Amb_Skybox:SetValue(false)
    -- (в моке Lighting не потомок game - Stash не возвращает; в Roblox вернёт)
    assert(lchild("Sky") == nil or lchild("Sky") == gameSky, "our sky removed")
    if L:IsDescendantOf(game) then assert(gameSky.Parent == L, "game sky back") end
    gameSky.Parent = nil
    Options.Amb_SkyboxName:SetValue("Night")
end
-- [v75] цикл дня, цветокоррекция, bloom, лучи, частицы
do
    Toggles.Amb_Sky:SetValue(true)
    Options.Amb_SkyTime:SetValue(10)
    Options.Amb_SkyCycle:SetValue(60)
    for _ = 1, 48 do FIRE(game:GetService("RunService").Heartbeat, 1) end -- 48 с = 48 игровых часов = 2 суток
    assert(math.abs(L.ClockTime - 10) < 1e-3, "full cycles: " .. tostring(L.ClockTime))
    FIRE(game:GetService("RunService").Heartbeat, 6)
    assert(math.abs(L.ClockTime - 16) < 1e-3, "time runs")
    Options.Amb_SkyCycle:SetValue(0)
    Toggles.Amb_Sky:SetValue(false)
    Toggles.Amb_Grade:SetValue(true)
    Options.Amb_GradeSat:SetValue(-50)
    local g = lchild("ColorCorrectionEffect")
    assert(g and math.abs(g.Saturation + 0.5) < 1e-6, "grading")
    Toggles.Amb_Bloom:SetValue(true)
    Toggles.Amb_SunRays:SetValue(true)
    assert(lchild("BloomEffect") and lchild("SunRaysEffect"), "bloom + rays")
    Toggles.Amb_Grade:SetValue(false) Toggles.Amb_Bloom:SetValue(false) Toggles.Amb_SunRays:SetValue(false)
    assert(count("BloomEffect") == 0 and count("SunRaysEffect") == 0, "effects off")
    Options.Amb_Particles:SetValue("Fireflies")
    assert(#emitters() == 1 and emitters()[1].LightEmission == 1, "fireflies")
    Options.Amb_Particles:SetValue("None")
    assert(#emitters() == 0, "particles off")
end
print("AMB TESTS PASSED")
