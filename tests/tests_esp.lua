
-- ===== ESP / chams / crosshair tests =====
FLUSH_TWEENS() RUN_DEFERRED()
local function buttonsIn(frame) local o = {} for _, c in ipairs(frame:GetChildren()) do if c.ClassName == "TextButton" then table.insert(o, c) end end return o end
local function click(btn) FIRE(btn.MouseButton1Click) end
local function featureById(id) for _, f in ipairs(Features) do if f.Id == id then return f end end end

-- старые индексы на месте, лишних нет
for _, p in ipairs({ "SurvChams_", "KillerChams_", "SpecChams_", "BotChams_" }) do
    assert(Toggles[p .. "Enabled"] and Options[p .. "VisMat"] and Options[p .. "VisColor"] and Options[p .. "WallMode"], p .. " model ui")
    assert(Options[p .. "FillColor"] and Options[p .. "FillTransparency"] and Toggles[p .. "Outline"] and Options[p .. "OutlineColor"] and Options[p .. "OutlineTransparency"], p .. " old idx kept")
    assert(Toggles[p .. "Fill"] == nil and Toggles[p .. "WallCheck"] == nil, p .. " Fill/WallCheck replaced by WallMode")
end
for _, p in ipairs({ "SurvESP_", "KillerESP_", "SpecESP_", "BotESP_" }) do
    for _, k in ipairs({ "Box", "Name", "Studs", "Health", "Skeleton", "Item", "Tracer", "Arrow" }) do
        assert(Toggles[p .. k] and Toggles[p .. k].Value == false, p .. k .. " chip toggle off by default")
    end
    for _, k in ipairs({ "BoxColor", "SkeletonColor", "TracerColor", "TextColor", "ArrowColor", "TextSize", "TracerThickness", "ArrowSize", "ArrowRadius" }) do
        assert(Options[p .. k], p .. k)
    end
    assert(ESPUI[p] == nil, p .. " no preview") -- [v51] Preview убран по просьбе; ESP Items (чипы) остались
end
assert(Toggles.KillerESP_KillerType and not Toggles.SurvESP_KillerType, "killer type only for killer")

-- dropdown с цветом слева (как у NL: Behind Walls [цвет] [...] [Flat v])
local D = Options.SurvChams_WallMode
assert(D.Right and #D.Addons == 2, "wallmode addons: color + settings")
assert(#buttonsIn(D.Right) >= 1, "swatch button in dropdown row")
assert(D.Value == "Flat" and Options.SurvChams_VisMat.Value == "Disabled" and Toggles.SurvChams_Outline.Value == true, "defaults")

-- стиль Highlight по режимам
local st = ChamsStyle("SurvChams_")
assert(st.FillTransparency == 0.5 and st.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop and st.OutlineTransparency == 0, "flat+glow")
D:SetValue("Outline")
st = ChamsStyle("SurvChams_")
assert(st.FillTransparency == 1 and st.OutlineTransparency == 0 and st.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop, "outline")
Toggles.SurvChams_Outline:SetValue(false)
st = ChamsStyle("SurvChams_")
assert(st.OutlineTransparency == 0 and st.OutlineColor:ToHex() == Options.SurvChams_FillColor.Value:ToHex(), "outline mode w/o glow uses fill color")
D:SetValue("Disabled")
st = ChamsStyle("SurvChams_")
assert(st.FillTransparency == 1 and st.OutlineTransparency == 1 and st.DepthMode == Enum.HighlightDepthMode.Occluded, "disabled")
D:SetValue("Flat") Toggles.SurvChams_Outline:SetValue(true)

-- [v58] ESP Items - обычные чекбоксы: клик по строке переключает Toggle [v73] «Bounding box» как у skeet
local chip
for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == "Bounding box" and d.Parent.ClassName == "TextButton" then chip = d.Parent break end
end
assert(chip, "checkbox row exists")
click(chip) FLUSH_TWEENS()
local boxT
for _, p in ipairs({ "SurvESP_", "KillerESP_", "SpecESP_", "BotESP_" }) do if Toggles[p .. "Box"].Value then boxT = Toggles[p .. "Box"] end end
assert(boxT, "checkbox on")
boxT:SetValue(false) FLUSH_TWEENS()

-- фейковая цель (в моке workspace не внутри game - для Stash:RestoreAll)
if workspace.Parent == nil then workspace.Parent = game end
local function fakeChar(name)
    local m = Instance.new("Model") m.Name = name
    local root = Instance.new("Part") root.Name = "HumanoidRootPart" root.Transparency = 1 root.Parent = m
    local torso = Instance.new("Part") torso.Name = "Torso" torso.Material = Enum.Material.Plastic torso.Color = Color3.new(0.5, 0.5, 0.5) torso.Parent = m
    local head = Instance.new("Part") head.Name = "Head" head.Material = Enum.Material.Plastic head.Color = Color3.new(1, 1, 0) head.Parent = m
    local mesh = Instance.new("SpecialMesh") mesh.TextureId = "rbxassetid://5" mesh.Parent = head
    local face = Instance.new("Decal") face.Transparency = 0 face.Parent = head
    local mp = Instance.new("MeshPart") mp.Name = "Hat" mp.TextureID = "rbxassetid://7" mp.Material = Enum.Material.Plastic mp.Color = Color3.new(0, 0, 1) mp.Parent = m
    local sa = Instance.new("SurfaceAppearance") sa.Parent = mp
    local hum = Instance.new("Humanoid") hum.Health = 50 hum.MaxHealth = 100 hum.Parent = m
    m.Parent = workspace
    return m, { Model = m, Name = name, Humanoid = hum, Root = root }, { torso = torso, head = head, mesh = mesh, face = face, mp = mp, sa = sa, root = root }
end
local m, e, parts = fakeChar("Enemy")
Targets.Survivors = { e }

-- Visible = Neon: материал/цвет/текстуры/лицо/PBR меняются и возвращаются
Toggles.SurvChams_Enabled:SetValue(true)
Options.SurvChams_VisColor:SetValueRGB(Color3.new(1, 0, 0))
Options.SurvChams_VisMat:SetValue("Neon")
assert(parts.torso.Material == Enum.Material.Neon and parts.torso.Color:ToHex() == "ff0000", "neon torso")
assert(parts.root.Material ~= Enum.Material.Neon, "root untouched")
assert(parts.mesh.TextureId == "" and parts.mp.TextureID == "" and parts.face.Transparency == 1 and parts.sa.Parent == nil, "textures cleared")
-- игра перекрашивает -> держим своё
parts.torso.Color = Color3.new(0, 1, 0)
assert(parts.torso.Color:ToHex() == "ff0000", "color held")
Options.SurvChams_VisMat:SetValue("Hologram")
assert(parts.head.Material == Enum.Material.ForceField, "hologram = forcefield")
Options.SurvChams_VisMat:SetValue("Disabled")
assert(parts.torso.Material == Enum.Material.Plastic and parts.head.Color:ToHex() == "ffff00", "restored")
assert(parts.torso.Color:ToHex() == "00ff00", "restored to the game's latest color")
assert(parts.mesh.TextureId == "rbxassetid://5" and parts.mp.TextureID == "rbxassetid://7" and parts.face.Transparency == 0 and parts.sa.Parent == parts.mp, "textures restored")
Options.SurvChams_VisMat:SetValue("Glass")
assert(parts.torso.Material == Enum.Material.Glass, "glass")
Targets.Survivors = {}
featureById("SurvChams_VisMat"):Update()
assert(parts.torso.Material == Enum.Material.Plastic, "restored when target leaves")
Targets.Survivors = { e }
featureById("SurvChams_VisMat"):Update()
Toggles.SurvChams_Enabled:SetValue(false)
assert(parts.torso.Material == Enum.Material.Plastic and parts.sa.Parent == parts.mp, "restored on disable")
Options.SurvChams_VisMat:SetValue("Disabled")

-- ESP draw: включение по любой кнопке, рисунки на цель
Toggles.SurvESP_Skeleton:SetValue(true)
local f = featureById("SurvESP_Draw")
assert(f.Active and f.Gui and f.Draw[m], "esp draw active with drawing for target")
Targets.Survivors = {}
f:Update()
assert(f.Draw[m] == nil, "drawing removed")
Toggles.SurvESP_Skeleton:SetValue(false)
assert(not f.Active, "esp draw off")

-- [v51] превью убрано: его кадр не создаётся
assert(ESPUI["SurvESP_Frame"] == nil, "no preview frame")
local itemsTitle = false
for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == "Preview" then assert(false, "Preview groupbox still there") end
    if d.ClassName == "TextLabel" and d.Text == "Killer models" then itemsTitle = true end
    if d.ClassName == "TextLabel" and d.Text == "ESP Items" then assert(false, "old groupbox: " .. d.Text) end
end
assert(itemsTitle, "[v73] two groupboxes per subtab: ... ESP / ... models")
for _, pg in ipairs({ SurvPage, KillerPage, SpecPage, BotPage, Tabs.World }) do assert(#pg.Groups == 2, "two groupboxes: " .. #pg.Groups) end

-- прицел: по умолчанию прежний круг; крест/T/точка
Toggles.Crosshair_Enabled:SetValue(true)
local ch = featureById("Crosshair_")
assert(ch.Active and ch.Circle.Visible and ch.Circle.Size == UDim2.fromOffset(10, 10), "default circle r=5")
assert(not ch.Arms[1].Frame.Visible and not ch.Dot.Visible, "no lines/dot by default")
assert(ch.CircleStroke.Thickness == 1.5, "default thickness = old 1.5")
Toggles.Crosshair_Cross:SetValue(true)
assert(ch.Arms[1].Frame.Visible and ch.Arms[4].Frame.Visible, "cross 4 lines")
Options.Crosshair_Gap:SetValue(4) Options.Crosshair_Size:SetValue(6)
assert(ch.Arms[1].Frame.Position == UDim2.fromOffset(7, 0) and ch.Arms[2].Frame.Position == UDim2.fromOffset(0, 7), "gap + len/2")
Toggles.Crosshair_TShape:SetValue(true)
assert(ch.Arms[1].Frame.Visible and not ch.Arms[4].Frame.Visible, "t-shape: no top line")
Toggles.Crosshair_Dot:SetValue(true) Toggles.Crosshair_Circle:SetValue(false)
assert(ch.Dot.Visible and not ch.Circle.Visible, "dot, no circle")
Toggles.Crosshair_Outline:SetValue(true)
assert(ch.Arms[1].Stroke.Transparency < 1, "outline on")
Toggles.Crosshair_Enabled:SetValue(false)
assert(ch.Circle == nil, "crosshair off")

-- «...» у прицела открывает настройки
local row = Toggles.Crosshair_Enabled.Right
local btns = buttonsIn(row)
assert(#btns >= 2, "crosshair has color + settings")
click(btns[#btns]) FLUSH_TWEENS()
local popups = Library.ScreenGui:FindFirstChild("Popups")
assert(#popups:GetChildren() >= 1, "settings popup opened")
click(popups:GetChildren()[1]) FLUSH_TWEENS() RUN_DEFERRED()

-- [v23] превью: пример Offscreen Arrow
assert(Options.SurvESP_ArrowSize.Value == 28, "bigger arrow by default")

-- [v23] бинды: ПКМ -> окно, клавиши Toggle / Hold, список, конфиг
local UIS_ = game:GetService("UserInputService")
local function key(k, down)
    FIRE(down and UIS_.InputBegan or UIS_.InputEnded, { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode[k] }, false)
end
FIRE(Toggles.Crosshair_Enabled.Row.MouseButton2Click) FLUSH_TWEENS()
local pops = Library.ScreenGui:FindFirstChild("Popups")
assert(#pops:GetChildren() == 2, "bind popup opened")
local modeHold
for _, d in ipairs(pops:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Hold" then modeHold = d.Parent end end
assert(modeHold, "mode buttons")
click(pops:GetChildren()[1]) FLUSH_TWEENS() RUN_DEFERRED()
Library:SetBind("Crosshair_Enabled", "F", "Toggle")
assert(Toggles.Crosshair_Enabled.Value == false)
key("F", true) key("F", false)
assert(Toggles.Crosshair_Enabled.Value == true, "toggle bind")
Library.KeybindList:Refresh()
assert(Library.KeybindList.Count == 1 and Library.KeybindList.Frame.Visible, "keybind list shows active bind")
assert(Library.HotkeyList == nil and Toggles.ThemeManager_KeybindList == nil, "hotkeys window removed") -- [v52]
key("F", true)
assert(Toggles.Crosshair_Enabled.Value == false, "toggle off")
Library:SetBind("SurvESP_Box", "LeftAlt", "Hold")
key("LeftAlt", true) assert(Toggles.SurvESP_Box.Value == true, "hold on")
key("LeftAlt", false) assert(Toggles.SurvESP_Box.Value == false, "hold release off")
Library:SetBind("SurvESP_Name", "G", "Always")
assert(Toggles.SurvESP_Name.Value == true, "always turns on")
-- в конфиг и обратно
assert(SaveManager:Save("bindtest"))
Library:ClearBinds()
assert(next(Library.Binds) == nil, "cleared")
assert(SaveManager:Load("bindtest"))
assert(Library.Binds.Crosshair_Enabled and Library.Binds.Crosshair_Enabled.Key == "F" and Library.Binds.SurvESP_Box.Mode == "Hold", "binds restored from config")
Library:SetBind("Crosshair_Enabled", "None")
assert(Library.Binds.Crosshair_Enabled == nil, "unbind")
Library:ClearBinds()
Toggles.SurvESP_Name:SetValue(false)

-- [v24] индикаторы биндов: плашка «Name [Key]» с иконкой бинда
Library:SetBind("AutoParry_Enabled", "R", "Toggle")
Toggles.AutoParry_Enabled:SetValue(true)
Library.KeybindList:Refresh() FLUSH_TWEENS()
local KLs = Library.KeybindList
assert(KLs.Count == 1, "indicator shown")
local pill = KLs.Items.AutoParry_Enabled
assert(pill and pill.Label.Text == "AP", "indicator text (gamesense: short name): " .. tostring(pill and pill.Label.Text)) -- [v72]
assert(pill.Label.TextTransparency == 0 and pill.Row.Position.X.Offset == 0, "slid in")
-- [v52] индикатор как у gamesense: тёмная полоса от края экрана (растворяется вправо), без цветной полоски
assert(Library.KeybindList.Frame.Position.X.Offset == 0 and pill.Box.ClassName == "Frame" and pill.Box:FindFirstChildOfClass("UIGradient"), "band from screen edge")
assert(pill.Bar.Visible == false and pill.Label.TextSize == 21 and pill.Row.Size.Y.Offset == 29, "no color strip, big text") -- [v73] плашка 29px
Toggles.AutoParry_Enabled:SetValue(false)
Library.KeybindList:Refresh() FLUSH_TWEENS()
assert(KLs.Count == 0 and KLs.Items.AutoParry_Enabled == nil, "indicator removed")
Library:ClearBinds()

-- [v24] авто-парри: угроза только от близкого киллера, который смотрит на нас и атакует
local ap = featureById("AutoParry_")
local kRoot = Instance.new("Part")
rawset(kRoot, "__extra", { CFrame = { LookVector = Vector3.new(1, 0, 0) } })
kRoot.Position = Vector3.new(0, 0, 0)
kRoot.AssemblyLinearVelocity = Vector3.new(25, 0, 0)
local kEntry = { Root = kRoot, Humanoid = nil }
Options.AutoParry_Distance:SetValue(9)
assert(ap:Threat(kEntry, Vector3.new(6, 0, 0)) == "lunge", "lunging at me")
assert(ap:Threat(kEntry, Vector3.new(15, 0, 0)) == nil, "too far")
assert(ap:Threat(kEntry, Vector3.new(-6, 0, 0)) == nil, "facing away")
kRoot.AssemblyLinearVelocity = Vector3.new(5, 0, 0)
assert(ap:Threat(kEntry, Vector3.new(6, 0, 0)) == nil, "walking, no attack anim")

-- [v25] обучение: урон по нам -> анимация ближнего киллера, начатая до удара, запоминается
local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
local oldTeam, oldChar = LPx.Team, LPx.Character
LPx.Team = { Name = "Survivors" }
local me = Instance.new("Model")
local myRoot = Instance.new("Part") myRoot.Name = "HumanoidRootPart" myRoot.Position = Vector3.new(6, 0, 0) myRoot.Parent = me
LPx.Character = me
local kModel = Instance.new("Model")
local kr = Instance.new("Part") kr.Name = "HumanoidRootPart" kr.Position = Vector3.new(0, 0, 0) kr.Parent = kModel
local fakeTrack = { Animation = { AnimationId = "rbxassetid://424242" }, TimePosition = 0, Priority = Enum.AnimationPriority.Action }
ap.Seen[fakeTrack] = { T = os.clock() - 0.4, Killer = kModel, Ambient = false }
ap.LastHealth = 100
ap:OnHealth(70)
local L = ESPUI.ParryLearned["424242"]
assert(L and L.hits == 1 and math.abs(L.delay - 0.4) < 0.05, "learned attack anim with hit delay")
assert(FILES[CONFIG.ScriptName .. "/parry_anims.json"], "learned saved to file")
ap.LastHealth = 70
ap:OnHealth(80) -- лечение - не учим
assert(L.hits == 1, "heal ignored")
table.clear(ESPUI.ParryLearned)
ap.Seen[fakeTrack] = nil
-- [v38] от одного удара - одна анимация (последняя начатая); известный удар - ничего не учим
local tOld = { Animation = { AnimationId = "rbxassetid://5001" }, TimePosition = 0, Priority = Enum.AnimationPriority.Action }
local tNew = { Animation = { AnimationId = "rbxassetid://5002" }, TimePosition = 0, Priority = Enum.AnimationPriority.Action }
ap.Seen[tOld] = { T = os.clock() - 1.3, Killer = kModel, Ambient = false }
ap.Seen[tNew] = { T = os.clock() - 0.35, Killer = kModel, Ambient = false }
ap.LastHealth = 100
ap:OnHealth(70)
assert(ESPUI.ParryLearned["5002"] and not ESPUI.ParryLearned["5001"], "only the latest anim learned")
table.clear(ESPUI.ParryLearned)
local tKnown = { Animation = { AnimationId = "rbxassetid://113691709436161" }, TimePosition = 0, Priority = Enum.AnimationPriority.Action }
ap.Seen[tKnown] = { T = os.clock() - 0.3, Killer = kModel, Ambient = false }
ap.LastHealth = 100
ap:OnHealth(70)
assert(next(ESPUI.ParryLearned) == nil, "known attack hit -> nothing learned")
ap.Seen[tOld], ap.Seen[tNew], ap.Seen[tKnown] = nil, nil, nil
assert(ESPUI.KnownAttacks["81963230963908"].Killer == "veil" and ESPUI.KnownKillers.cure and ESPUI.KnownKillers.slasher, "known attack ids")
LPx.Team, LPx.Character = oldTeam, oldChar

-- [v34] ID атак из скрипта Animations киллера (логика AutoDagger)
local animScript = Instance.new("ModuleScript")
animScript.Source = 'local attackAnim = "rbxassetid://111"\nlocal LungeHold = \'rbxassetid://222\'\nlocal spearAttack = "rbxassetid://333"\nlocal idle = "rbxassetid://444"'
local ids = ESPUI.ParseAttackIds(animScript)
assert(ids["111"] == "attackAnim" and ids["222"] == "LungeHold" and ids["333"] == nil and ids["444"] == nil, "attack ids parsed")
assert(Options.AutoParry_Distance.Value == 9 and Options.AutoParry_Angle.Value == 360, "parry defaults")
assert(Toggles.AutoParry_ShowRange.Value == true, "range ring on by default")
Toggles.AutoParry_Enabled:SetValue(true)
local viz = featureById("AutoParryViz_")
assert(viz.Active and #viz.Ring.Parts == 48 and #viz.Cone.Parts == 36, "ring 48 + cone 36 parts like AutoDagger")
local okDraw, errDraw = pcall(viz.Draw, viz)
assert(okDraw, "draw w/o character: " .. tostring(errDraw))
-- [v75] Threat: дуга к киллеру, внутреннее кольцо при сближении, вспышка при парри
do
    local LPz = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local prev = LPz.Character
    local me, _, mp = fakeChar("MeParry")
    mp.root.Position = Vector3.new(0, 3, 0) mp.root.CFrame = CFrame.new(0, 3, 0) mp.root.Size = Vector3.new(2, 2, 1)
    LPz.Character = me
    FIRE(game:GetService("Players").LocalPlayer.CharacterAdded, me)
    local km, ke, kp = fakeChar("ParryKiller")
    kp.root.Size = Vector3.new(2, 2, 1)
    local oldK = Targets.Killers
    Targets.Killers = { ke }
    local function at(x) kp.root.Position = Vector3.new(x, 3, 0) kp.root.CFrame = CFrame.new(x, 3, 0) end
    at(26) viz.LastDraw = os.clock() - 0.1 viz:Draw()
    local t0 = os.clock()
    while os.clock() - t0 < 0.05 do end
    at(14) viz.LastDraw = os.clock() - 0.1 viz:Draw()
    local lit, dim = 0, 0
    for _, p in ipairs(viz.Ring.Parts) do if p.Transparency < 0.5 then lit += 1 elseif p.Transparency < 1 then dim += 1 end end
    assert(lit > 0 and dim > 0, "threat: lit arc toward killer + dim rest " .. lit .. "/" .. dim)
    assert(viz.Prev[km] and viz.Prev[km].C > 0, "closing speed measured")
    me:SetAttribute("ParryLands", 1)
    assert(os.clock() - viz.FlashAt < 1, "flash on parry")
    Targets.Killers = oldK
    LPz.Character = prev
end
Toggles.AutoParry_Enabled:SetValue(false)
assert(not viz.Active, "viz off with auto parry")
-- [v37] снаряды: Remotes Cure/Butcher/Veil, путь колбы, цепь, точное копьё, режимы аима, таймеры парри
do
    local RS = game:GetService("ReplicatedStorage")
    local function folder(name, parent) local f = parent:FindFirstChild(name) or Instance.new("Folder") f.Name = name f.Parent = parent return f end
    local function remote(name, parent) local r = Instance.new("RemoteEvent") r.Name = name r.Parent = parent return r end
    local K = folder("Killers", folder("Remotes", RS))
    local flaskEv = remote("VisualizeFlask", folder("Cure", K))
    local B = folder("Butcher", K)
    local chainEv, clearEv = remote("ChainState", B), remote("ChainClear", B)
    local spearEv = remote("SpearState", folder("Veil", K))
    Projectiles.Bound, Projectiles.Got, Projectiles.TriedAt = false, nil, nil
    Projectiles.Bind()
    assert(Projectiles.Bound, "all projectile remotes bound")
    -- колба: 0 -> (70,0,0) -> (70,0,70): 140 стад, 2с
    FIRE(flaskEv.OnClientEvent, "launch", { Points = { Vector3.new(0, 0, 0), Vector3.new(70, 0, 0), Vector3.new(70, 0, 70) }, StartedAt = 0 })
    local f = Projectiles.Flasks[#Projectiles.Flasks]
    assert(f and f.Total == 140, "flask stored with length")
    local left = Projectiles.FlaskLeft(f, 0.5)
    assert(#left == 3 and (left[1].Pos - Vector3.new(35, 0, 0)).Magnitude < 1e-3, "flask now at 35 studs")
    left = Projectiles.FlaskLeft(f, 1.5)
    assert(#left == 2 and (left[1].Pos - Vector3.new(70, 0, 35)).Magnitude < 1e-3, "flask on 2nd segment")
    assert(Projectiles.FlaskLeft(f, 2.1) == nil, "flask landed")
    Projectiles.Prune(10)
    assert(#Projectiles.Flasks == 0, "landed flask pruned")
    -- цепь: летит прямо 140 ст/с, старт 4 стад
    local owner = Instance.new("Model")
    FIRE(chainEv.OnClientEvent, owner, {}, 0, nil, nil, nil, nil, "flying", { Origin = Vector3.new(0, 5, 0), Direction = Vector3.new(0, 0, -2), LaunchTime = 0 })
    local c = Projectiles.Chains[owner]
    assert(c and c.Reach == 50 and (c.Dir - Vector3.new(0, 0, -1)).Magnitude < 1e-6, "chain flight stored")
    local tip, stop = Projectiles.ChainNow(c, 0.1)
    assert((tip - Vector3.new(0, 5, -18)).Magnitude < 1e-3 and (stop - Vector3.new(0, 5, -50)).Magnitude < 1e-3, "chain tip / end")
    assert(Projectiles.ChainNow(c, 1) == nil, "chain done")
    FIRE(clearEv.OnClientEvent, owner)
    assert(Projectiles.Chains[owner] == nil, "chain clear")
    FIRE(chainEv.OnClientEvent, owner, {}, 0, nil, nil, nil, nil, "flying", { Origin = Vector3.new(0, 5, 0), Direction = Vector3.new(0, 0, -1), LaunchTime = 0 })
    FIRE(chainEv.OnClientEvent, owner, {}, 0, nil, nil, nil, nil, "hold", nil)
    assert(Projectiles.Chains[owner] == nil, "non-flying phase ends flight")
    -- копьё Veil: точный бросок с сервера
    local veilChar = Instance.new("Model")
    FIRE(spearEv.OnClientEvent, "launch", { Id = 7, Source = veilChar, Origin = Vector3.new(1, 2, 3), Direction = Vector3.new(0, 0, -1), Speed = 120, LaunchTime = 0, Piercing = true })
    local sp = Projectiles.Spears[veilChar]
    assert(sp and sp.Vel.Z == -120 and sp.Pierce == true, "exact spear stored")
    FIRE(spearEv.OnClientEvent, "stop", { Id = 7, Reason = "hit" })
    assert(Projectiles.Spears[veilChar] == nil, "spear stop clears")
    -- ESP колбы / цепи рисуется без ошибок
    local abil = featureById("AbilityESP_")
    if not abil.Active then Toggles.AbilityESP_Flask:SetValue(true) end
    assert(abil.Active, "ability esp active")
    FIRE(flaskEv.OnClientEvent, "launch", { Points = { Vector3.new(0, 0, -10), Vector3.new(0, 0, -150) }, StartedAt = 0 })
    FIRE(chainEv.OnClientEvent, owner, {}, 0, nil, nil, nil, nil, "flying", { Origin = Vector3.new(0, 5, -5), Direction = Vector3.new(0, 0, -1), LaunchTime = 0 })
    local before = #abil.Lines
    local okR, errR = pcall(abil.Render, abil)
    assert(okR, "ability render: " .. tostring(errR))
    assert(#abil.Lines > before, "flask/chain lines drawn")
    table.clear(Projectiles.Flasks) table.clear(Projectiles.Chains)
    -- UI
    for _, k in ipairs({ "AbilityESP_Flask", "AbilityESP_Chain", "DodgeCure_Flask", "DodgeButcher_Chain", "ChainAim_Enabled", "FlashAim_Enabled", "ParryESP_Enabled", "ChainAim_Predict" }) do
        assert(Toggles[k], k)
    end
    assert(Options.SpearAim_Mode.Value == "Default" and Options.ChainAim_Mode.Value == "Default", "aim modes default")
    for _, id in ipairs({ "ChainAim_", "FlashAim_", "ParryESP_" }) do assert(featureById(id), id .. " feature") end
    -- маркер Legit + наводка без mousemoverel не падают
    local st = {}
    local cam = workspace.CurrentCamera
    local okM, errM = pcall(Projectiles.Marker, st, cam, Vector3.new(0, 0, -1), Color3.new(1, 0, 0))
    assert(okM and st.MarkRing, "marker: " .. tostring(errM))
    Projectiles.Marker(st, cam, nil)
    assert(st.MarkRing.Visible == false, "marker hidden")
    Projectiles.ClearMarker(st)
    assert(Projectiles.HeldRaw("NotAKey") == false, "unknown key not held")
    -- фичи включаются / выключаются без ошибок
    for _, k in ipairs({ "ChainAim_Enabled", "FlashAim_Enabled", "ParryESP_Enabled" }) do
        Toggles[k]:SetValue(true)
        local fe = featureById(string.gsub(k, "Enabled", ""))
        assert(fe.Active, k .. " active")
        if fe.Step then local ok, e = pcall(fe.Step, fe) assert(ok, k .. " step: " .. tostring(e)) end
        if fe.Update then local ok, e = pcall(fe.Update, fe) assert(ok, k .. " update: " .. tostring(e)) end
        Toggles[k]:SetValue(false)
        assert(not fe.Active, k .. " off")
    end
end
-- [v39] Fake Dagger / Hand Chams / парри: задержка / фонарик
do
    for _, k in ipairs({ "FakeDagger_Enabled", "FakeDagger_Face", "AutoParry_Humanize", "AutoParry_PingComp",
        "Moonwalk_Stutter", "FlashAim_WallCheck" }) do assert(Toggles[k], k) end -- [v90] FlashAim_Auto убран
    for _, k in ipairs({ "FakeDagger_Key", "FakeDagger_Preset", "FakeDagger_Freeze", "FakeDagger_Speed", "FakeDagger_Cooldown", "AutoParry_Delay",
        "AutoParry_CircleStyle" }) do assert(Options[k], k) end -- [v90] FlashAim_Range убран
    assert(Options.FakeDagger_Key.Value == "Z" and Options.FakeDagger_Freeze.Value == 1.2 and Options.AutoParry_CircleStyle.Value == "Threat", "v39 defaults") -- [v75] Threat по умолчанию
    -- id анимации кинжала берётся из атрибута useanim / parriedanim
    local fd = featureById("FakeDagger_")
    local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local oldChar = LPx.Character
    local me = Instance.new("Model")
    local dg = Instance.new("Tool") dg.Name = "Parrying Dagger" dg:SetAttribute("useanim", "rbxassetid://777") dg:SetAttribute("parriedanim", "888") dg.Parent = me
    LPx.Character = me
    assert(fd:AnimId(me) == "777", "fake dagger: useanim")
    Options.FakeDagger_Preset:SetValue("Parry hit")
    assert(fd:AnimId(me) == "888", "fake dagger: parriedanim")
    Options.FakeDagger_Preset:SetValue("Auto")
    dg.Parent = nil
    assert(fd:AnimId(me) == "777", "fake dagger: remembered id")
    LPx.Character = oldChar
    -- видимость: луч без препятствий
    assert(Projectiles.CanSee(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), {}) == true, "can see (no hit)")
    local ap = featureById("AutoParry_")
    assert(type(ap:Ping()) == "number", "ping number")
end
-- [v40] Hitsounds: вшитые данные, base64-декод, загрузка через getcustomasset, события
do
    assert(HITSOUNDS_DATA and HITSOUNDS_ORDER and #HITSOUNDS_ORDER == 25, "25 hitsounds embedded")
    assert(table.find(HITSOUNDS_ORDER, "nl hitsound"), "nl hitsound added")
    for _, k in ipairs({ "Hitsound_Hit", "Hitsound_Down", "Hitsound_Parry", "Hitsound_PitchByDamage" }) do assert(Toggles[k], k) end
    for _, k in ipairs({ "Hitsound_HitSound", "Hitsound_DownSound", "Hitsound_ParrySound", "Hitsound_Volume", "Hitsound_Pitch" }) do assert(Options[k], k) end
    local HS = ESPUI.HS
    assert(HS, "HS exposed")
    -- декод base64 реального ogg -> writefile -> getcustomasset; первые 4 байта = "OggS"
    local name = HITSOUNDS_ORDER[1]
    local id = HS.Asset(name)
    assert(type(id) == "string" and id ~= "", "asset loaded via getcustomasset")
    local path = HS.SoundFolder .. "/" .. name:gsub("[^%w _%-]", "_") .. ".ogg"
    assert(FILES[path] and FILES[path]:sub(1, 4) == "OggS", "decoded ogg written (OggS magic)")
    assert(HS.Asset(name) == id, "asset cached")
    -- тестовая кнопка играет без ошибок
    local okT, errT = pcall(ESPUI.TestHitsound)
    assert(okT, "test hitsound: " .. tostring(errT))
    -- событие Hit: падение HP выжившего, когда ты киллер
    local hf = featureById("Hitsound_")
    Toggles.Hitsound_Hit:SetValue(true)
    assert(hf.Active, "hitsound feature active")
    local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local oldTeam = LPx.Team
    LPx.Team = { Name = CONFIG.Teams.Killer }
    local mk = Instance.new("Model")
    local mkRoot = Instance.new("Part") mkRoot.Name = "HumanoidRootPart" mkRoot.Parent = mk
    LPx.Character = mk
    local sv = Instance.new("Model")
    local svHum = Instance.new("Humanoid") svHum.Health = 100 svHum.MaxHealth = 100 svHum.Parent = sv
    local svRoot = Instance.new("Part") svRoot.Name = "HumanoidRootPart" svRoot.Parent = sv
    Targets.AllSurvivors = { { Model = sv, Humanoid = svHum, Player = nil, Root = svRoot } }
    local played = 0
    local realPlay = HS.Play
    HS.Play = function(...) played = played + 1 end
    hf:Update() -- базовое HP
    svHum.Health = 70
    hf:Update() -- должно сыграть Hit
    assert(played == 1, "hit sound on health drop")
    svHum.Health = 70
    hf:Update() -- без изменения - тишина
    assert(played == 1, "no sound without drop")
    HS.Play = realPlay
    Toggles.Hitsound_Hit:SetValue(false)
    LPx.Team = oldTeam
end
-- [v41] статус-визуалы: крюк/лечение/вырывание, стан киллера, terror ring, caps-категории
do
    for _, k in ipairs({ "SurvState_HookInfo", "SurvState_HealInfo", "SurvState_WiggleInfo", "KillerState_Stun", "TerrorRing_Enabled" }) do
        assert(Toggles[k], k)
    end
    for _, id in ipairs({ "KillerStun_", "TerrorRing_" }) do assert(featureById(id), id) end
    -- SurvState рисует прогресс-строки по атрибутам
    local ss = featureById("SurvState_")
    Toggles.SurvState_HookInfo:SetValue(true)
    Toggles.SurvState_HealInfo:SetValue(true)
    Toggles.SurvState_WiggleInfo:SetValue(true)
    local m = Instance.new("Model")
    local hum = Instance.new("Humanoid") hum.Health = 40 hum.MaxHealth = 100 hum.Parent = m
    local root = Instance.new("Part") root.Name = "HumanoidRootPart" root.Parent = m
    m:SetAttribute("IsHooked", true) m:SetAttribute("HookCount", 2) m:SetAttribute("HookedProgress", 0.5)
    m:SetAttribute("IsBeingHealed", true) m:SetAttribute("HealProgress", 64)
    m:SetAttribute("IsCarried", true) m:SetAttribute("RemainingCarryTime", 4)
    Targets.AllSurvivors = { { Model = m, Humanoid = hum, Player = nil } }
    ss:Update()
    local map = Tags.Map[Tags.AnchorOf and Tags.AnchorOf("State") or "Head"]
    -- найдём лейбл State
    local found
    for _, rec in pairs(map) do if rec.Slots and rec.Slots.State then found = rec.Slots.State.Text end end
    assert(found and found:find("Hook S2 50") and found:find("Heal 64") and found:find("Wiggle 75"), "hook/heal/wiggle lines: " .. tostring(found))
    Toggles.SurvState_HookInfo:SetValue(false) Toggles.SurvState_HealInfo:SetValue(false) Toggles.SurvState_WiggleInfo:SetValue(false)
    -- стан киллера
    local km = Instance.new("Model")
    local kr = Instance.new("Part") kr.Name = "HumanoidRootPart" kr.Position = Vector3.new(0, 0, 0) kr.Parent = km
    km:SetAttribute("IsStunned", true)
    Targets.Killers = { { Model = km, Player = nil, Root = kr } }
    Toggles.KillerState_Stun:SetValue(true)
    local ks = featureById("KillerStun_")
    ks:Update()
    local kmap = Tags.Map.Head
    local sfound
    for _, rec in pairs(kmap) do if rec.Slots and rec.Slots.Stun then sfound = rec.Slots.Stun.Text end end
    assert(sfound and sfound:find("STUNNED"), "stun label")
    Toggles.KillerState_Stun:SetValue(false)
    -- terror ring включается без ошибок
    Targets.Killers = { { Model = km, Player = nil, Root = kr } }
    km:SetAttribute("TerrorRadius", 24)
    Toggles.TerrorRing_Enabled:SetValue(true)
    local tr = featureById("TerrorRing_")
    assert(tr.Active and tr.Parts and #tr.Parts == 60, "terror ring parts")
    local okD, errD = pcall(tr.Draw, tr)
    assert(okD, "terror ring draw: " .. tostring(errD))
    Toggles.TerrorRing_Enabled:SetValue(false)
    -- [v48] skeet: категории - промежутки между группами вкладок, без подписей
    local gaps = 0
    for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
        if d.ClassName == "Frame" and string.find(d.Name, "^Category_") then gaps += 1 end
        assert(not (d.ClassName == "TextLabel" and d.Text == "VISUALS"), "no category captions")
    end
    assert(gaps == 0, "no category gaps (skeet: tabs 7 x 75 back to back): " .. gaps) -- [v54]
    assert(Tabs.Players.Nav.Item.Size.Y.Offset == 64, "tab 64px") -- [v74] шаг вкладок по скрину оригинала
end
-- [v42] лого/футер, SLOW-индикатор, попап-настройки (units/esp scale)
do
    assert(Toggles.SlowIndicator_Enabled and Options.SlowIndicator_Color and featureById("SlowIndicator_"), "slow indicator ui+feature")
    -- статус-API списка индикаторов
    local KL = Library.KeybindList
    if KL then
        KL:SetStatus("TestSlow", { Text = "SLOW", Color = Color3.new(1, 0, 0) })
        assert(KL.Status.TestSlow, "status row set")
        KL:SetStatus("TestSlow", nil)
        assert(KL.Status.TestSlow == nil, "status row cleared")
    end
    -- попап-поля
    assert(Library.ESPScale ~= nil and Library.Units ~= nil, "popup globals")
    Library.Units = "meters"
    -- FormatDist недоступен (локальная), проверяем косвенно через рендер distance в State? пропустим
    Library.Units = "studs"
    -- [v49] у skeet нет шапки / нижней строки: название только в ватермарке; масштаб и единицы - в Config
    local inMenu = false
    for _, d in ipairs(Library.ScreenGui:FindFirstChild("Main"):GetDescendants()) do
        if d.ClassName == "TextLabel" and d.Text == "Violence District" then inMenu = true end
    end
    assert(not inMenu, "no footer in the menu")
    assert(Options.ThemeManager_MenuScale and Options.ThemeManager_ESPScale and Options.ThemeManager_Units, "scale / units in Config")
    Options.ThemeManager_Units:SetValue("meters")
    assert(Library.Units == "meters", "units from Config")
    Options.ThemeManager_Units:SetValue("studs")
end
-- [v43] Menu Scale переживает анимацию открытия/закрытия; дубли генераторов/паллет; сломанная паллета; Dodger
do
    assert(Library.SetMenuScale and Library._UIScale, "menu scale api")
    local base = Library._UIScale.Scale / (Library.MenuScale or 1)
    Library:SetMenuScale(1.25)
    assert(math.abs(Library._UIScale.Scale - base * 1.25) < 1e-6, "menu scale applied")
    -- закрыть / открыть меню (zoom-анимация) - множитель остаётся
    pcall(function() Library:Toggle(false) end) FLUSH_TWEENS()
    pcall(function() Library:Toggle(true) end) FLUSH_TWEENS()
    assert(math.abs(Library.MenuScale - 1.25) < 1e-6, "menu scale kept after close/open")
    assert(math.abs(Library._UIScale.Scale - base * 1.25) < 0.02, "UIScale still scaled after open anim: " .. tostring(Library._UIScale.Scale))
    Library:SetMenuScale(1)

    -- вложенный генератор: одна подсветка
    local outer = Instance.new("Model") outer.Name = "Generator1"
    local inner = Instance.new("Model") inner.Name = "Generator" inner.Parent = outer
    local res = Collect.Outermost({ outer, inner })
    assert(#res == 1 and res[1] == outer, "nested generator deduped")
    -- сломанная паллета не подсвечивается
    local map = Instance.new("Model") map.Name = "Map" map.Parent = workspace
    local pl = Instance.new("Model") pl.Name = "Newpallet" pl.Parent = map
    local intact = Instance.new("Model") intact.Name = "Intact" intact.Parent = pl
    local pp = Instance.new("Part") pp.Name = "Pallet" pp.Parent = intact
    MapIndex.Sets.Pallets[pl] = true
    local got = Collect.Pallets()
    local has = false for _, x in ipairs(got) do if x == pp then has = true end end
    assert(has, "upright pallet collected")
    pl:SetAttribute("PalletState", "Broken")
    got = Collect.Pallets()
    has = false for _, x in ipairs(got) do if x == pp then has = true end end
    assert(not has, "broken pallet not collected")
    MapIndex.Sets.Pallets[pl] = nil
    map.Parent = nil
    -- флат-поза не падает на модели без суставов
    assert(pcall(ESPUI.FlatPose, Instance.new("Model")), "flat pose safe on empty model")
    -- Dodger: подвкладка есть, старых нет
    local hasDodger, hasOld = false, false
    for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
        if d.ClassName == "TextLabel" then
            if d.Text == "Dodger" then hasDodger = true end
            if d.Text == "Abysswalker" and d.Parent and d.Parent.ClassName == "TextButton" and d.TextSize == 13 then hasOld = true end
        end
    end
    assert(hasDodger, "Dodger subtab")
end
-- [v43] автододж: одна клавиша, клавиши игрока не трогаем, сторона - куда игрок идёт
do
    local dk = featureById("DodgeKnight_")
    workspace.CurrentCamera.CFrame = CFrame.new()
    table.clear(SENT_KEYS) table.clear(HELD_KEYS)
    dk:SetStrafe(Vector3.new(1, 0, 0.2)) -- в основном вправо
    local n = 0 for _ in pairs(dk.Keys) do n += 1 end
    assert(n == 1 and dk.Keys[Enum.KeyCode.D], "single key D pressed")
    dk:SetStrafe(nil)
    assert(next(dk.Keys) == nil, "released")
    -- игрок сам держит D: не жмём, не отпускаем
    HELD_KEYS[Enum.KeyCode.D] = true
    table.clear(SENT_KEYS)
    dk:SetStrafe(Vector3.new(1, 0, 0))
    dk:SetStrafe(nil)
    assert(#SENT_KEYS == 0, "player's own key untouched")
    -- сторона: игрок жмёт D (вправо) -> уходим вправо, даже если ближе край слева
    local root = Instance.new("Part") root.Position = Vector3.new(0, 0, 0)
    local side = dk:PickSide("k1", root, Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0), nil)
    -- линия вдоль -Z: right = (1,0,0)
    assert(side and side.X > 0.5, "player's direction wins: " .. tostring(side))
    HELD_KEYS[Enum.KeyCode.D] = nil
    -- без ввода: ближний край (игрок слева от оси) и выбор держится для той же угрозы
    local s2 = dk:PickSide("k2", root, Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0), nil)
    assert(s2 and s2.X < -0.5, "nearest edge")
    HELD_KEYS[Enum.KeyCode.D] = true
    local s3 = dk:PickSide("k2", root, Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0), nil)
    assert(s3.X < -0.5, "side sticky for same threat")
    HELD_KEYS[Enum.KeyCode.D] = nil
    table.clear(dk.Sides)
end
-- [v43] 3D-дуга копья: один Beam с изгибом по параболе, кольцо удара, скрытие
do
    local SV = Projectiles.SpearViz
    local folder = Instance.new("Model") folder.Parent = workspace
    local v = SV.Get(folder, "testVeil")
    assert(v.Core and v.Glow and v.Hit and v.Pierce, "viz parts")
    local vel = Vector3.new(60, 30, 0)
    local hit = SV.Draw(v, Vector3.new(0, 10, 0), vel, true, 0, Color3.new(1, 0, 0), true)
    assert(v.Core.Enabled and v.Glow.Enabled, "beams on")
    -- без стен копьё летит до конца пути (MaxLife, с шагом) -> CurveSize0 = |v| * T / 3
    local pts = VeilSpearPath(Vector3.new(0, 10, 0), vel, true)
    local T = pts[#pts].T
    assert(math.abs(v.Core.CurveSize0 - vel.Magnitude * T / 3) < 1e-3, "curve size 0 = |v|T/3: " .. tostring(v.Core.CurveSize0))
    assert(math.abs(v.Core.CurveSize1 - (vel + SPEAR.Gravity * T).Magnitude * T / 3) < 1e-3, "curve size 1 = |v(T)|T/3")
    assert(hit, "impact point returned")
    -- в полёте рисуется только остаток: t0 > 0
    SV.Draw(v, Vector3.new(0, 10, 0), vel, false, 1, Color3.new(1, 0, 0), false)
    assert(math.abs(v.Core.CurveSize0 - (vel + SPEAR.Gravity * 1).Magnitude * (T - 1) / 3) < 1e-3, "remaining arc from t0")
    assert(v.Ball.Transparency < 1, "spear ball shown in flight")
    -- пролетело - скрыто
    SV.Draw(v, Vector3.new(0, 10, 0), vel, false, T + 1, Color3.new(1, 0, 0), false)
    assert(not v.Core.Enabled, "hidden after flight")
    SV.Clear()
    assert(next(SV.Pool) == nil, "pool cleared")
    folder.Parent = nil
end
-- [v45] темы меню
do
    -- [v48] темы skeet: одна серая гамма, разный акцент
    assert(#Library.Themes == 3 and Options.ThemeManager_Theme, "3 themes + dropdown")
    local function hex(c) return string.lower(c:ToHex()) end
    -- [v49] цвета со скриншотов skeet
    assert(hex(Library.Scheme.AccentColor) == "93c539" and --[[ [v57] ]] hex(Library.Scheme.MainColor) == "131313" and hex(Library.Scheme.GroupColor) == "171717", "skeet default colors (bg tile 21/14/13 -> 19, group 23)") -- [v54]
    assert(Library:ApplyTheme("Ocean"), "apply theme 2")
    assert(hex(Library.Scheme.AccentColor) == "3e9fd0" and hex(Library.Scheme.GroupColor) == "171717", "theme 2: accent only")
    assert(Options.ThemeManager_Theme.Value == "Ocean", "dropdown follows")
    -- выбор в дропдауне
    Options.ThemeManager_Theme:SetValue("Sakura")
    assert(Library.ThemeName == "Sakura" and hex(Library.Scheme.AccentColor) == "d0628f", "theme 3 via dropdown")
    -- сохраняется в theme.json
    local saved
    for path, data in pairs(FILES) do if path:match("theme_skeet%.json$") then saved = game:GetService("HttpService"):JSONDecode(data) end end -- [v49]
    assert(saved and saved.theme == "Sakura", "theme saved")
    local oldFile = false
    for path in pairs(FILES) do if path:match("/theme%.json$") then oldFile = true end end
    assert(not oldFile, "skeet menu does not use NeverUI theme.json") -- [v49]
    -- групбокс: заголовок как есть (без капса), углы прямые
    local title = false
    for _, d in ipairs(Library.ScreenGui:FindFirstChild("Main"):GetDescendants()) do
        if d.ClassName == "TextLabel" and d.Text == "World ESP" then title = true end
        assert(d.ClassName ~= "UICorner", "no rounded corners in the menu")
    end
    assert(title and Library.Style.Round == 0, "section title + square style")
    -- свой акцент поверх темы не ломает остальные цвета темы
    Options.ThemeManager_Accent:SetValueRGB(Color3.fromRGB(255, 0, 0))
    assert(hex(Library.Scheme.AccentColor) == "ff0000" and hex(Library.Scheme.GroupColor) == "171717", "accent override only")
    Library:ApplyTheme("Default")
    assert(hex(Library.Scheme.AccentColor) == "93c539", "back to default") -- [v57]
end
-- [v45] аим копья: в упор - прямо в цель (не в потолок); скорость цели по смещению
do
    local sa = featureById("SpearAim_")
    local solve = sa.Solve
    -- цель в 2 стадах, чуть ниже камеры
    local d, t = solve(Vector3.new(0, 5, 0), Vector3.new(2, 3.5, 0), Vector3.zero, 54)
    assert(d and t == 0 and d.X > 0.7 and d.Y < 0, "point blank -> straight at target: " .. tostring(d))
    -- 4 стада по горизонтали (точка появления копья почти на цели) - тоже прямо
    d = solve(Vector3.new(0, 5, 0), Vector3.new(3.8, 3, 0), Vector3.zero, 54)
    assert(d and d.Y < 0.2, "near spawn offset -> no lob: " .. tostring(d))
    -- обычная дистанция: нормальный навес вперёд, без задирания
    d, t = solve(Vector3.new(0, 5, 0), Vector3.new(30, 3, 0), Vector3.zero, 120)
    assert(d and d.X > 0.8 and math.deg(math.asin(d.Y)) < 25 and t > 0, "normal throw: " .. tostring(d))
    -- скорость по смещению: стоит на месте, а AssemblyLinearVelocity = 16 (генератор) -> 0
    local root = Instance.new("Part") root.Position = Vector3.new(10, 0, 10)
    root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
    local st = {}
    st.PosTrack = { Root = root, Pos = root.Position, T = os.clock() - 0.1, V = Vector3.zero }
    local v = Projectiles.MoveVel(st, root)
    assert(v.Magnitude < 0.01, "standing still (gen) -> no lead: " .. tostring(v))
    -- реально бежит 16 ст/с
    st.PosTrack = { Root = root, Pos = root.Position - Vector3.new(1.6, 0, 0), T = os.clock() - 0.1, V = Vector3.zero }
    v = Projectiles.MoveVel(st, root)
    assert(v.X > 10, "running -> lead along movement: " .. tostring(v))
end

-- [v47] авто-парри по lungehold, звук парри по ParryLands, окно -> Bottom, колба Cure, NL-бар генератора
do
    local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local oldTeam, oldChar = LPx.Team, LPx.Character
    LPx.Team = { Name = "Survivors" }
    assert(ESPUI.KnownAttacks["135002183282873"].Name == "lungehold", "cure lungehold known")
    assert(ESPUI.IsHoldName("cure lungehold") and ESPUI.IsHoldName("LungeHold") and not ESPUI.IsHoldName("attack"), "hold names")
    local ap = featureById("AutoParry_")
    local me = Instance.new("Model")
    local myRoot = Instance.new("Part") myRoot.Name = "HumanoidRootPart" myRoot.Position = Vector3.new(6, 0, 0) myRoot.Parent = me
    local myHum = Instance.new("Humanoid") myHum.Health = 100 myHum.MaxHealth = 100 myHum.Parent = me
    LPx.Character = me
    local kModel = Instance.new("Model")
    local kr = Instance.new("Part") kr.Name = "HumanoidRootPart" kr.Position = Vector3.new(0, 0, 0) kr.Parent = kModel
    rawset(kr, "__extra", { CFrame = { LookVector = Vector3.new(1, 0, 0) } })
    local e = { Model = kModel, Root = kr }
    local track = { IsPlaying = true, Animation = { AnimationId = "rbxassetid://135002183282873" } }
    local fired = {}
    local realFire, realCan = ap.Fire, ap.CanParry
    ap.Fire = function(self, _, _, _, _, k, why) table.insert(fired, why) self.LastFire = os.clock() end
    ap.CanParry = function() return true end
    local oldKillers = Targets.Killers
    Targets.Killers = {}
    Options.AutoParry_Distance:SetValue(9)
    Toggles.AutoParry_PingComp:SetValue(false)
    Options.AutoParry_HoldWait:SetValue(150) -- [v69] из NL v48: по умолчанию 0 (сразу), тут проверяем ожидание
    -- только что зажал: ещё рано (окно 0.8с не накроет полный рывок)
    ap.Holds[track] = { T = os.clock(), E = e, Name = "cure lungehold" }
    ap:Step()
    assert(#fired == 0, "hold just started -> wait")
    -- прошло 0.2с, киллер в радиусе -> парри
    ap.Holds[track].T = os.clock() - 0.2
    ap:Step()
    assert(#fired == 1 and fired[1]:find("hold"), "parry during lungehold: " .. tostring(fired[1]))
    ap:Step()
    assert(#fired == 1, "one parry per hold")
    -- далеко -> нет
    local t2 = { IsPlaying = true, Animation = { AnimationId = "rbxassetid://135002183282873" } }
    myRoot.Position = Vector3.new(20, 0, 0)
    ap.Holds[t2] = { T = os.clock() - 0.3, E = e, Name = "cure lungehold" }
    ap:Step()
    assert(#fired == 1, "hold out of range -> no parry")
    t2.IsPlaying = false
    ap:Step()
    assert(ap.Holds[t2] == nil, "finished hold dropped")
    ap.Fire, ap.CanParry = realFire, realCan
    Targets.Killers = oldKillers
    table.clear(ap.Holds)

    -- звук парри: рост ParryLands
    local hf = featureById("Hitsound_")
    local HS = ESPUI.HS
    local played = 0
    local realPlay = HS.Play
    HS.Play = function() played = played + 1 end
    me:SetAttribute("ParryLands", 0)
    Toggles.Hitsound_Parry:SetValue(true)
    assert(hf.Active, "hitsound active for parry")
    me:SetAttribute("ParryLands", 1)
    assert(played == 1, "parry sound on ParryLands increase")
    me:SetAttribute("ParryLands", 1)
    assert(played == 1, "no repeat without change")
    Toggles.Hitsound_Parry:SetValue(false)
    HS.Play = realPlay

    -- окно: подсветка на Bottom (даже невидимом)
    local win = Instance.new("Model") win.Name = "Window" win.Parent = Instance.new("Folder")
    local bottom = Instance.new("Part") bottom.Name = "Bottom" bottom.Transparency = 1 bottom.Parent = win
    local vt = Instance.new("Part") vt.Name = "VaultTrigger" vt.Transparency = 1 vt.Parent = win
    local vp = Instance.new("Part") vp.Name = "VaultPoint" vp.Parent = vt
    MapIndex.Sets.Windows[win] = true
    local list = Collect.Windows()
    assert(table.find(list, bottom), "window adornee = Bottom")
    MapIndex.Sets.Windows[win] = nil

    -- колба Cure: целится -> FLASK, после броска - кулдаун
    local cf = featureById("CureFlask_")
    assert(cf and Toggles.KillerState_Flask, "cure flask feature")
    -- NL-бар генератора: строится и обновляется
    local gen = Instance.new("Model") gen.Name = "Generator" gen.Parent = Instance.new("Folder")
    local gp = Instance.new("Part") gp.Transparency = 0 gp.Size = Vector3.new(4, 4, 4) gp.Position = Vector3.new(0, 2, 0) gp.Parent = gen
    gen:SetAttribute("RepairProgress", 45)
    MapIndex.Sets.Generators[gen] = true
    local gf = featureById("GenProgress_")
    Toggles.GenProgress_Enabled:SetValue(true) -- [v69] список строится по переключателям (генераторы / ворота)
    local okG, errG = pcall(function() gf:Update() gf:Render() end)
    assert(okG, "gen bar: " .. tostring(errG))
    local bar = gf.Bars[gen]
    -- [v65] вид как слайдер skeet: без GENERATOR, процент у конца заливки, время до конца по скорости
    assert(bar and bar.Label.Text == "45%" and bar.Title == nil and bar.Fill.Size.X.Scale == 0.45, "skeet gen bar")
    assert(bar.Label.Position.X.Scale == 0.45 and bar.Eta.Visible == false, "label at fill end, no eta yet")
    bar.LastT = os.clock() - 1
    gen:SetAttribute("RepairProgress", 55) gf:Update()
    assert(bar.Eta.Visible and bar.Eta.Text == "~5s", "eta from rate: " .. tostring(bar.Eta.Text))
    gen:SetAttribute("RepairProgress", 100) gf:Update()
    assert(bar.Label.Text == "DONE" and bar.Eta.Visible == false, "done")
    -- [v69] статус под полосой: ProgressPaused -> Unavailable
    gen:SetAttribute("ProgressPaused", true) gf:Update()
    assert(bar.Status.Visible and bar.Status.Text == "Unavailable", "paused status")
    -- [v69] рычаг ворот выхода: прогресс из атрибута с "progress" в имени (доля -> проценты)
    local lever = Instance.new("Model") lever.Name = "ExitLever" lever.Parent = gen.Parent
    local lm = Instance.new("Part") lm.Name = "Main" lm.Transparency = 0 lm.Size = Vector3.new(1, 1, 1) lm.Position = Vector3.new(5, 1, 0) lm.Parent = lever
    lm:SetAttribute("GateProgress", 0.4)
    MapIndex.Sets.Levers[lever] = true
    Toggles.GateProgress_Enabled:SetValue(true) gf:Update()
    local lb = gf.Bars[lever]
    assert(lb and lb.Label.Text == "40%", "exit gate lever bar: " .. tostring(lb and lb.Label.Text))
    Toggles.GateProgress_Enabled:SetValue(false)
    MapIndex.Sets.Levers[lever] = nil
    Toggles.GenProgress_Enabled:SetValue(false)
    pcall(bar.Gui.Destroy, bar.Gui) gf.Bars[gen] = nil
    MapIndex.Sets.Generators[gen] = nil
    -- колба: Update с киллером без аниматора не падает
    local okF, errF = pcall(function() cf:Update() end)
    assert(okF, "cure flask update: " .. tostring(errF))
    LPx.Team, LPx.Character = oldTeam, oldChar
end
-- [v65] копьё Veil, вариант C: время до удара по телу (мок: CFrame в object space - тождественный)
do
    local char = Instance.new("Model")
    local t = Instance.new("Part") t.Name = "Torso" t.Size = Vector3.new(2, 2, 1) t.CFrame = CFrame.new() t.Parent = char
    local hitPts, missPts = {}, {}
    for i = 0, 20 do
        hitPts[#hitPts + 1] = { Pos = Vector3.new(0, 0, 20 - i * 2), T = i * 0.05 }
        missPts[#missPts + 1] = { Pos = Vector3.new(10, 0, 20 - i * 2), T = i * 0.05 }
    end
    local SV = Projectiles.SpearViz
    assert(math.abs((SV.HitTime(hitPts, char, 0.6, 0) or -1) - 0.45) < 1e-6, "spear hit time")
    assert(math.abs((SV.HitTime(hitPts, char, 0.6, 0.2) or -1) - 0.25) < 1e-6, "spear hit time after t0")
    assert(SV.HitTime(missPts, char, 0.6, 0) == nil, "spear miss")
    assert(Toggles.AbilityESP_VeilWarn and Options.AbilityESP_VeilWarnColor, "warn options")
end
-- [v66] ESP FX: все эффекты включаются, обновляются и выключаются без ошибок; стиль подсветки анимируется
do
    local fxF = featureById("FX_")
    assert(fxF and Toggles.FXKiller_Enabled and Toggles.FXSurv_Enabled and Toggles.FXKiller_Echo and not Toggles.FXSurv_Echo, "fx feature (per team, in models) [v73]")
    local km, ke, kparts = fakeChar("FxKiller")
    for _, prt in pairs({ kparts.root, kparts.torso, kparts.head }) do
        prt.Position = Vector3.new(0, 3, 0) prt.CFrame = CFrame.new(0, 3, 0) prt.Size = Vector3.new(2, 2, 1)
    end
    local oldK = Targets.Killers
    Targets.Killers = { ke }
    Options.FXKiller_ColorMode:SetValue("Rainbow")
    Options.FXKiller_Texture:SetValue("Galaxy")
    for _, t in ipairs({ "FXKiller_Pulse", "FXKiller_SkelGlow", "FXKiller_Trail", "FXKiller_Aura", "FXKiller_Ring", "FXKiller_Echo", "FXKiller_Backtrack" }) do Toggles[t]:SetValue(true) end
    Options.FXKiller_BacktrackStyle:SetValue("Ghost trail")
    Toggles.FXKiller_Enabled:SetValue(true)
    assert(fxF.Active, "fx active")
    local ok, err = pcall(function() fxF:Update() fxF:Render() fxF:Render() end)
    assert(ok, "fx run: " .. tostring(err))
    assert(fxF.Tex[km] and #fxF.Tex[km].List > 0, "moving texture on killer parts")
    assert(fxF.Follow[km] and fxF.Follow[km].Trail.Enabled and fxF.Follow[km].Emitter.Enabled, "trail + aura")
    assert(#fxF.Echoes >= 1 and fxF.Ghosts[km] and fxF.Ghosts[km][4], "echo + backtrack ghosts")
    local base = { FillColor = Color3.new(1, 0, 0), FillTransparency = 0.5, OutlineColor = Color3.new(1, 0, 0), OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop }
    local st = HighlightGroup.FX.Style("KillerChams_", km, base)
    assert(st ~= base and st.OutlineTransparency >= 0, "animated style")
    assert(HighlightGroup.FX.Style("SpecChams_", km, base) == base, "team filter")
    Options.FXKiller_ColorMode:SetValue("Health")
    assert(HighlightGroup.FX.ColorFor(km, "Killer"):ToHex() ~= nil, "health color")
    assert(HighlightGroup.FX.Style("SurvChams_", km, base) == base, "survivors have their own (off) effects")
    Toggles.FXKiller_Enabled:SetValue(false)
    assert(not fxF.Active and next(fxF.Tex) == nil, "fx off cleans")
    Targets.Killers = oldK
end
-- [v67] Self Chams: всё тело красится, одежда снимается; выключили - всё как было
do
    local sc = featureById("SelfChams_")
    local LPy = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local prevChar = LPy.Character
    local me2, _, mp = fakeChar("MeSelf")
    local shirt = Instance.new("Shirt") shirt.Parent = me2
    LPy.Character = me2
    Options.SelfChams_Material:SetValue("Neon")
    Options.SelfChams_Color:SetValueRGB(Color3.new(0, 1, 0))
    Toggles.SelfChams_Outline:SetValue(true)
    Toggles.SelfChams_Enabled:SetValue(true)
    assert(sc.Active and mp.torso.Material == Enum.Material.Neon and mp.torso.Color:ToHex() == "00ff00", "self chams body")
    assert(shirt.Parent == nil and mp.face.Transparency == 1 and mp.mp.TextureID == "", "clothes / face / textures off")
    assert(sc.HL and HighlightGroup.Reserved >= 1, "self outline reserves a highlight")
    local okR = pcall(function() sc:Render() end)
    assert(okR, "self render")
    Toggles.SelfChams_Enabled:SetValue(false)
    assert(mp.torso.Material == Enum.Material.Plastic and mp.torso.Color:ToHex() == "7f7f7f" or mp.torso.Color:ToHex() == "808080", "self restored color " .. mp.torso.Color:ToHex())
    assert(shirt.Parent == me2 and mp.face.Transparency == 0 and mp.mp.TextureID == "rbxassetid://7", "clothes / face / textures back")
    assert(sc.HL == nil, "outline removed")
    LPy.Character = prevChar
end
-- [v72] gamesense: короткие имена, метки [-] у важных функций, хит-логи, Lua-скрипты
do
    assert(Library:ShortName("Spear Auto-Aim") == "AS" and Library:ShortName("Moonwalk") == "MN", "short names")
    assert(Library:ShortName("Some Thing") == "ST", "short name fallback")
    local mark
    for _, d in ipairs(Toggles.SpearAim_Enabled.Right:GetDescendants()) do
        if d.ClassName == "TextLabel" and d.Text == "[-]" then mark = d end
    end
    assert(mark and mark.Parent.Visible, "bind mark [-] next to Spear Auto-Aim")
    Library:SetBind("SpearAim_Enabled", "M5", "Toggle")
    assert(mark.Text == "[M5]", "bind mark shows key: " .. tostring(mark.Text))
    Library:SetBind("SpearAim_Enabled", nil)
    assert(mark.Text == "[-]" and mark.Parent.Visible, "unbound -> [-] stays")

    -- хит-логи
    local HL = Library.HitLogObj
    assert(HL, "hit log created")
    local hf = featureById("HitLog_")
    Toggles.HitLog_Enabled:SetValue(true)
    assert(hf.Active, "hitlog active")
    local LPx = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local oldTeam, oldChar = LPx.Team, LPx.Character
    local oldAll, oldK = Targets.AllSurvivors, Targets.Killers
    LPx.Team = { Name = CONFIG.Teams.Killer }
    local mk = Instance.new("Model")
    local mkRoot = Instance.new("Part") mkRoot.Name = "HumanoidRootPart" mkRoot.Parent = mk
    LPx.Character = mk
    local sv = Instance.new("Model")
    local svHum = Instance.new("Humanoid") svHum.Health = 100 svHum.MaxHealth = 100 svHum.Parent = sv
    local svRoot = Instance.new("Part") svRoot.Name = "HumanoidRootPart" svRoot.Parent = sv
    Targets.AllSurvivors = { { Model = sv, Humanoid = svHum, Player = nil, Root = svRoot, Name = "Bob" } }
    Targets.Killers = {}
    HL:Clear()
    local n0 = #HL.Lines
    hf:Update()
    svHum.Health = 75
    hf:Update()
    assert(#HL.Lines == n0 + 1, "hit logged")
    local txt = HL.Lines[#HL.Lines].Text.Text
    assert(string.find(txt, "Hit ", 1, true) and string.find(txt, "Bob", 1, true) and string.find(txt, "25", 1, true)
        and string.find(txt, "75", 1, true), "hit text: " .. txt)
    sv:SetAttribute("Knocked", true)
    hf:Update()
    assert(string.find(HL.Lines[#HL.Lines].Text.Text, "Downed", 1, true), "down logged")
    Options.HitLog_Events:SetValue({ Hit = true })
    sv:SetAttribute("IsHooked", true)
    local n1 = #HL.Lines
    hf:Update()
    assert(#HL.Lines == n1, "hook filtered out by events")
    Library.StreamerMode = true
    svHum.Health = 50
    hf:Update()
    assert(not string.find(HL.Lines[#HL.Lines].Text.Text, "Bob", 1, true), "streamer hides name")
    Library.StreamerMode = false
    Options.HitLog_Events:SetValue({ Hit = true, Down = true, ["Got hit"] = true, Hook = true, Parry = true, Stun = true })
    -- выживший: урон по себе
    LPx.Team = { Name = CONFIG.Teams.Survivors }
    local myHum = Instance.new("Humanoid") myHum.Health = 100 myHum.MaxHealth = 100 myHum.Parent = mk
    hf:Update()
    myHum.Health = 60
    hf:Update()
    assert(string.find(HL.Lines[#HL.Lines].Text.Text, "Got hit", 1, true), "got hit logged")
    Toggles.HitLog_Enabled:SetValue(false)
    HL:Clear()
    LPx.Team, LPx.Character = oldTeam, oldChar
    Targets.AllSurvivors, Targets.Killers = oldAll, oldK

    -- Lua
    local LM = ESPUI.Lua
    assert(LM and Options.LuaMgr_List and Toggles.LuaMgr_Unsafe and Toggles.LuaMgr_Startup, "lua manager ui")
    local DIR = CONFIG.ScriptName .. "/scripts"
    assert(table.find(LM.List(), "example"), "example script written")
    writefile(DIR .. "/t1.lua", [[
        local g = hub.ui.group("T1")
        local cb = g:checkbox("Show", false)
        g:slider("Size", 13, 8, 24)
        g:color("Col", Color3.new(1, 0, 0))
        g:dropdown("Mode", { "A", "B" }, "A")
        g:button("Btn", function() end)
        g:label("hi")
        RAN = (RAN or 0) + 1
        HAS_GAME = game ~= nil
        hub.on("render", function()
            hub.draw.text(Vector2.new(10, 10), "hello", Color3.new(1, 1, 1), 13)
            hub.draw.line(Vector2.new(0, 0), Vector2.new(10, 10))
            hub.draw.box(Vector2.new(5, 5), Vector2.new(10, 10))
            hub.draw.circle(Vector2.new(5, 5), 4)
        end)
        hub.on("hit", function(kind) LAST_HIT = kind end)
        hub.on("unload", function() UNLOADED = true end)
    ]])
    Options.LuaMgr_Search:SetValue("t1")
    assert(#Options.LuaMgr_List.Values == 1 and Options.LuaMgr_List.Values[1] == "t1", "search filters list")
    Options.LuaMgr_List:SetValue("t1")
    local ok, err = LM.Load("t1")
    assert(ok, "load t1: " .. tostring(err))
    assert(LM.Loaded.t1 and Toggles.Lua_t1_Show and Options.Lua_t1_Size and Options.Lua_t1_Col and Options.Lua_t1_Mode, "script ui created")
    local S = LM.Loaded.t1
    local env = getfenv and nil
    FIRE(game:GetService("RunService").RenderStepped, 1 / 60)
    local okE = pcall(function() ESPUI.LuaEmit("hit", "parry", {}) end)
    assert(okE, "emit hit")
    -- песочница: game недоступен, глобалы скрипта не протекают наружу
    assert(rawget(_G, "RAN") == nil and rawget(_G, "HAS_GAME") == nil, "sandbox globals stay inside")
    Toggles.Lua_t1_Show:SetValue(true)
    Options.Lua_t1_Size:SetValue(20)
    assert(LM.Unload("t1") and not LM.Loaded.t1 and Toggles.Lua_t1_Show == nil, "unload removes ui")
    assert(SaveManager.Pending.Lua_t1_Show and SaveManager.Pending.Lua_t1_Show.value == true, "value kept while unloaded")
    RUN_DEFERRED()
    assert(LM.Load("t1") and Toggles.Lua_t1_Show.Value == true and Options.Lua_t1_Size.Value == 20, "values restored on reload")
    -- конфиг сохраняет UI скрипта
    local found = false
    for _, o in ipairs(SaveManager:_Collect()) do if o.idx == "Lua_t1_Show" then found = true end end
    assert(found, "script option in config")
    -- ошибка при запуске / в render
    writefile(DIR .. "/bad.lua", "error('boom')")
    local okB, errB = LM.Load("bad")
    assert(not okB and string.find(tostring(errB), "boom", 1, true) and not LM.Loaded.bad, "error on load")
    writefile(DIR .. "/bad2.lua", "hub.on('render', function() error('frame') end)")
    assert(LM.Load("bad2"), "bad2 loads")
    FIRE(game:GetService("RunService").RenderStepped, 1 / 60)
    RUN_DEFERRED()
    assert(not LM.Loaded.bad2 and string.find(LM.Errors.bad2 or "", "frame", 1, true), "runtime error unloads script")
    -- автозапуск
    Options.LuaMgr_List:SetValue("t1")
    Toggles.LuaMgr_Startup:SetValue(true)
    assert(table.find(LM.Startup, "t1"), "startup list")
    LM.UnloadAll()
    LM.RunStartup()
    assert(LM.Loaded.t1, "startup loads")
    Toggles.LuaMgr_Enabled:SetValue(false)
    assert(not LM.Loaded.t1 and #LM.Order == 0, "disable unloads all")
    Toggles.LuaMgr_Enabled:SetValue(true)
    Toggles.LuaMgr_Startup:SetValue(false)
    Options.LuaMgr_Search:SetValue("")
end
-- [v75] HUD: хитмаркер, цифры урона, компас, радар, погоня, статистика
do
    local LPh = rawget(game:GetService("Players").LocalPlayer, "__extra")
    local prevChar, prevTeam = LPh.Character, LPh.Team
    local me, _, mp = fakeChar("MeHud")
    mp.root.Position = Vector3.new(0, 3, 0) mp.root.CFrame = CFrame.new(0, 3, 0)
    LPh.Character = me
    LPh.Team = { Name = CONFIG.Teams.Survivors }
    local km, ke, kp = fakeChar("HudKiller")
    kp.root.Position = Vector3.new(10, 3, 0) kp.root.CFrame = CFrame.new(10, 3, 0)
    local oldK, oldS = Targets.Killers, Targets.AllSurvivors
    Targets.Killers, Targets.AllSurvivors = { ke }, {}
    -- хитмаркер / урон / статистика получают события, даже когда хит-логи выключены
    Toggles.HitLog_Enabled:SetValue(false)
    Toggles.Hud_Hitmarker:SetValue(true)
    Toggles.Hud_DamageNum:SetValue(true)
    Toggles.Hud_Stats:SetValue(true)
    assert(featureById("HitLog_").Active, "event source runs for HUD")
    local hm, dn, st = featureById("HudHit_"), featureById("HudDmg_"), featureById("HudStats_")
    ESPUI.ResetStats()
    local nLog = #Library.HitLogObj.Lines
    ESPUI.HitLogPush("hit", { "Hit ", { "x" } }, { damage = 25, health = 75 }, km)
    assert(#Library.HitLogObj.Lines == nLog, "no log line while hit logs are off")
    assert(os.clock() - hm.At < 1, "hit marker fired")
    hm:Draw()
    assert(hm.Lines[1].BackgroundTransparency < 1, "hit marker visible")
    assert(#dn.Items == 1 and dn.Items[1].Label.Text == "-25", "damage number")
    dn:Draw()
    ESPUI.HitLogPush("parry", { "Parried" }, {}, nil)
    assert(ESPUI.Hud.Stats.Hits == 1 and ESPUI.Hud.Stats.Parries == 1, "stats counted")
    st.DrawAt = 0 st:Draw()
    assert(st.Panel.Frame.Visible and st.Labels[1].Text == "1", "stats panel")
    -- компас
    Toggles.Hud_Compass:SetValue(true)
    local cp = featureById("HudCompass_")
    cp:Draw()
    assert(cp.Used == 7 and cp.Pool[1].Visible, "compass arc for the killer")
    Targets.Killers = {}
    cp:Draw()
    assert(cp.Used == 0 and not cp.Pool[1].Visible, "compass hides")
    Targets.Killers = { ke }
    -- радар
    Toggles.Hud_Radar:SetValue(true)
    local rd = featureById("HudRadar_")
    assert(rd.Panel and rd.Panel.Frame.Visible, "radar panel")
    rd.DrawAt = 0 rd:Draw()
    local vis = 0
    for _, d in ipairs(rd.Dots) do if d.Visible then vis += 1 end end
    assert(vis >= 1, "killer on radar")
    -- [v76] крюк (Map/Hook с HookPoint) на радаре
    local hook = Instance.new("Model") hook.Name = "Hook"
    local hp = Instance.new("Part") hp.Name = "HookPoint" hp.Position = Vector3.new(0, 3, 20) hp.Parent = hook
    MapIndex.Sets.Hooks[hook] = true
    hook.Parent = workspace
    rd.ObjAt, rd.DrawAt = 0, 0 rd:Draw()
    local hasHook = false
    for _, o in ipairs(rd.Objs) do if o.Kind == "Hook" and o.Inst == hp then hasHook = true end end
    assert(hasHook, "hook on radar")
    MapIndex.Sets.Hooks[hook] = nil hook.Parent = nil
    Options.Hud_RadarSize:SetValue(220)
    assert(rd.Panel.Frame.Size.X.Offset == 220, "radar size")
    -- погоня: киллер рядом и видит -> через 0.75 с «CHASE» в индикаторах
    Toggles.Hud_Chase:SetValue(true)
    local ch = featureById("HudChase_")
    for _ = 1, 3 do ch.TickAt = os.clock() - 0.5 ch:Tick() end
    assert(ch.On and ESPUI.Hud.Stats.Chases == 1, "chase started")
    assert(Library.KeybindList.Status.Chase and string.find(Library.KeybindList.Status.Chase.Text, "CHASE", 1, true), "chase indicator")
    Targets.Killers = {}
    ch.Start = os.clock() - 10 -- погоня шла 10 с (в тесте время «прыгает» через TickAt)
    for _ = 1, 8 do ch.TickAt = os.clock() - 0.5 ch:Tick() end
    assert(not ch.On and ESPUI.Hud.Stats.ChaseTime > 0, "chase ended, time counted")
    assert(Library.KeybindList.Status.Chase == nil, "indicator removed")
    for _, t in ipairs({ "Hud_Hitmarker", "Hud_DamageNum", "Hud_Stats", "Hud_Compass", "Hud_Radar", "Hud_Chase" }) do Toggles[t]:SetValue(false) end
    assert(not rd.Panel.Frame.Visible and not st.Panel.Frame.Visible, "panels hidden")
    assert(#ESPUI.HitSubs == 0, "subscribers removed")
    Targets.Killers, Targets.AllSurvivors = oldK, oldS
    LPh.Character, LPh.Team = prevChar, prevTeam
end
print("ESP TESTS PASSED")
