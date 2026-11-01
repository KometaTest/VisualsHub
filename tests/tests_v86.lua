-- ===== [v86] перки игроков во время матча: ESPUI.PerkData / PerkIcon, панель Perks, строка в ESP =====
FLUSH_TWEENS() RUN_DEFERRED()
local function featureById(id) for _, f in ipairs(Features) do if f.Id == id then return f end end end
local RS = game:GetService("ReplicatedStorage")
local HS = game:GetService("HttpService")
local LP = game:GetService("Players").LocalPlayer
assert(Toggles.Hud_Perks and Toggles.SurvESP_Perks and Toggles.KillerESP_Perks, "perks toggles")

-- нет MatchResults -> nil
assert(ESPUI.PerkData(LP) == nil, "no data without MatchResults")

-- MatchResults/<UserId> как пишет игра (ResultsView.readRoster)
local mr = Instance.new("Folder") mr.Name = "MatchResults" mr.Parent = RS
local me = Instance.new("Folder") me.Name = tostring(LP.UserId) me.Parent = mr
me:SetAttribute("UserId", LP.UserId) me:SetAttribute("Username", LP.Name)
me:SetAttribute("Perks", HS:JSONEncode({ { name = "Sprint Burst", level = 3 }, { name = "Bond", level = 1 }, { name = "", level = 1 } }))
me:SetAttribute("Item", "Medkit") me:SetAttribute("IsKiller", false)
local pd = ESPUI.PerkData(LP)
assert(pd and #pd.Perks == 2 and pd.Names[1] == "Sprint Burst" and pd.Perks[1].Level == 3, "perks decoded")
assert(pd.Item == "Medkit" and pd.IsKiller == false, "item / side")
me:SetAttribute("Perks", "garbage")
assert(#ESPUI.PerkData(LP).Perks == 0, "bad JSON -> empty, no error")
me:SetAttribute("Perks", HS:JSONEncode({ { name = "Sprint Burst", level = 3 }, { name = "Hex Ruin", level = 2 } }))

-- иконки: Perks/<имя>/<уровень> (Decal) и перки киллера в Killers/*/Perks
local perks = Instance.new("Folder") perks.Name = "Perks" perks.Parent = RS
local sb = Instance.new("Folder") sb.Name = "Sprint Burst" sb.Parent = perks
local d3 = Instance.new("Decal") d3.Name = "3" d3.Texture = "rbxassetid://333" d3.Parent = sb
local ks = Instance.new("Folder") ks.Name = "Killers" ks.Parent = RS
local k1 = Instance.new("Folder") k1.Name = "Veil" k1.Parent = ks
local kp = Instance.new("Folder") kp.Name = "Perks" kp.Parent = k1
local ruin = Instance.new("Folder") ruin.Name = "Hex Ruin" ruin.Parent = kp
local il = Instance.new("ImageLabel") il.Name = "1" il.Image = "rbxassetid://111" il.Parent = ruin
assert(ESPUI.PerkIcon("Sprint Burst", 3) == "rbxassetid://333", "survivor perk icon")
assert(ESPUI.PerkIcon("Hex Ruin", 2) == "rbxassetid://111", "killer perk icon, falls back to level 1")
assert(ESPUI.PerkIcon("Nope", 1) == nil, "unknown perk")

-- панель
Toggles.Hud_Perks:SetValue(true)
local f = featureById("HudPerks_")
f.At = nil f:Update()
assert(Library.HudPanels.perks and Library.HudPanels.perks.Frame.Visible, "panel shown")
local r = f.Rows[1]
assert(r and r.Frame.Visible and r.Name.Text == LP.Name and r.Item.Text == "Medkit", "row filled")
assert(r.Icons[1].Image == "rbxassetid://333" and r.Names[2].Text == "Hex Ruin" and r.Icons[3].Visible == false, "icons / names")
Library.StreamerMode = true f.At = nil f:Update()
assert(r.Name.Text == "Player 1", "streamer mode hides names")
Library.StreamerMode = false
me:Destroy() f.At = nil f:Update()
assert(not r.Frame.Visible, "row hidden when data gone")
Toggles.Hud_Perks:SetValue(false)
assert(not Library.HudPanels.perks.Frame.Visible, "panel hidden")
mr:Destroy() perks:Destroy() ks:Destroy()
print("tests_v86 ok")

-- ===== [v87] перки на карточках выживших (SurvivorHUD: Survivor<N> + ViewportFrame, атрибут UserId) =====
assert(Toggles.Hud_CardPerks and Options.Hud_CardPerksPos and Options.Hud_CardPerksSize and Toggles.Hud_CardPerksBg, "card perks UI")
local mr2 = Instance.new("Folder") mr2.Name = "MatchResults" mr2.Parent = RS
local e2 = Instance.new("Folder") e2.Name = "777" e2.Parent = mr2
e2:SetAttribute("Perks", HS:JSONEncode({ { name = "Bond", level = 1 }, { name = "Kindred", level = 2 } }))
local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:FindFirstChild("PlayerGui")
local sg = Instance.new("ScreenGui") sg.Name = "HUD" sg.IgnoreGuiInset = false sg.Parent = pg
local holder = Instance.new("Frame") holder.Name = "bottom left" holder.Parent = sg
local card = Instance.new("Frame") card.Name = "Survivor2" card.Parent = holder
Instance.new("ViewportFrame").Parent = card
card.AbsolutePosition = Vector2.new(100, 600) card.AbsoluteSize = Vector2.new(60, 120)
card:SetAttribute("UserId", 777)
local empty = Instance.new("Frame") empty.Name = "Survivor3" empty.Parent = holder -- без UserId -> без иконок
Instance.new("ViewportFrame").Parent = empty

Toggles.Hud_CardPerks:SetValue(true)
local cf = featureById("CardPerks_")
cf.ScanAt, cf.DataAt = -math.huge, nil cf:Update() cf:Render()
local o = cf.Over[card]
assert(o and cf.Over[empty] == nil, "overlay only for the card with data")
assert(o.Frame.Visible and o.Icons[1].Bg.Visible and not o.Icons[3].Bg.Visible, "2 perks shown")
-- Above: 2 иконки по 20px (ширина 60 / 3), зазор 2, по центру карточки, над ней
assert(o.Frame.Size.X.Offset == 42 and o.Frame.Size.Y.Offset == 20, "size " .. o.Frame.Size.X.Offset)
assert(o.Frame.Position.X.Offset == 109 and o.Frame.Position.Y.Offset == 578, "above: " .. o.Frame.Position.X.Offset .. "," .. o.Frame.Position.Y.Offset)
Options.Hud_CardPerksPos:SetValue("Below") cf:Render()
assert(o.Frame.Position.Y.Offset == 722, "below")
-- игровой GUI с IgnoreGuiInset -> минус топбар (36 в моке)
sg.IgnoreGuiInset = true cf:Render()
assert(o.Frame.Position.Y.Offset == 722 - 36, "inset")
-- карточку спрятали -> иконки тоже
card.Visible = false cf:Render()
assert(not o.Frame.Visible, "hidden with the card")
card.Visible = true
-- игрок ушёл из карточки (UserId снят) -> оверлей убран
card:SetAttribute("UserId", nil) cf.DataAt = nil cf:Update()
assert(cf.Over[card] == nil, "overlay removed")
Toggles.Hud_CardPerks:SetValue(false)
Options.Hud_CardPerksPos:SetValue("Above")
sg:Destroy() mr2:Destroy()
print("tests_v87 ok")

-- ===== [v88] матч идёт (MatchResults пуст): перки, замеченные по атрибутам персонажа =====
local LPx = rawget(LP, "__extra")
local oldTeam, oldChar = LPx.Team, LPx.Character
LPx.Team = { Name = "Survivors" }
local ch = Instance.new("Model") ch.Name = LP.Name
LPx.Character = ch
local sd = ESPUI.PerkData(LP)
assert(sd and sd.Source == "seen" and #sd.Perks == 0, "in round, nothing seen yet")
LP:SetAttribute("EquippedItem", "Flashlight")
ch:SetAttribute("builtdifferent", true)
sd = ESPUI.PerkData(LP)
assert(#sd.Perks == 1 and sd.Names[1] == "Built different" and sd.Item == "Flashlight", "builtdifferent seen")
ch:SetAttribute("builtdifferent", nil) ch:SetAttribute("snakestep", 1.2)
sd = ESPUI.PerkData(LP.UserId)
assert(#sd.Perks == 2 and sd.Names[2] == "Snake Step", "remembered + snake step, by UserId")
-- панель: строка есть, заголовок «seen in match»
Toggles.Hud_Perks:SetValue(true)
local pf = featureById("HudPerks_")
pf.At = nil pf:Update()
assert(pf.Rows[1].Frame.Visible and pf.Rows[1].Names[2].Text == "Snake Step", "panel seen row")
assert(Library.HudPanels.perks.Title.Text == "perks · seen in match", "panel title: " .. Library.HudPanels.perks.Title.Text)
-- новый персонаж (новый раунд) -> замеченное сброшено
local ch2 = Instance.new("Model") ch2.Name = LP.Name
LPx.Character = ch2
pf.At = nil pf:Update()
assert(pf.Rows[1].Names[1].Text == "none seen yet", "reset on new character")
-- итоги появились -> источник last
local mr3 = Instance.new("Folder") mr3.Name = "MatchResults" mr3.Parent = RS
local e3 = Instance.new("Folder") e3.Name = tostring(LP.UserId) e3.Parent = mr3
e3:SetAttribute("Perks", HS:JSONEncode({ { name = "Bond", level = 1 } }))
pf.At = nil pf:Update()
assert(Library.HudPanels.perks.Title.Text == "perks · last match" and ESPUI.PerkData(LP).Source == "last", "results source")
Toggles.Hud_Perks:SetValue(false)
mr3:Destroy()
-- не в раунде (лобби / зритель) -> nil
LPx.Team = { Name = "Spectator" }
assert(ESPUI.PerkData(LP) == nil, "not in round")
LPx.Team, LPx.Character = oldTeam, oldChar
print("tests_v88 ok")
-- [v89] Flowstate / Visual Learner / Enhanced Senses
do
    local LPx2 = rawget(LP, "__extra")
    local t0, c0 = LPx2.Team, LPx2.Character
    LPx2.Team = { Name = "Killer" }
    local kc = Instance.new("Model") LPx2.Character = kc
    kc:SetAttribute("enhanced_senses_aura_bonus", 10) kc:SetAttribute("Flowstate", true)
    local d = ESPUI.PerkData(LP)
    local has = {} for _, n in ipairs(d.Names) do has[n] = true end
    assert(has["Enhanced Senses"] and has["Flowstate"] and d.IsKiller and d.Item == nil, "v89 attrs")
    LPx2.Team, LPx2.Character = t0, c0
end
print("tests_v89 ok")

-- [v92] Grey characters: красит и возвращает, свой персонаж не трогает при надетом скине
do
    local LPx3 = rawget(LP, "__extra")
    local c0 = LPx3.Character
    local ch = Instance.new("Model") ch.Name = LP.Name
    local arm = Instance.new("Part") arm.Name = "Left Arm" arm.Color = Color3.new(1, 0, 0) arm.Material = Enum.Material.Plastic arm.Parent = ch
    local shirt = Instance.new("Shirt") shirt.ShirtTemplate = "rbxassetid://5" shirt.Parent = ch
    LPx3.Character = ch
    Toggles.Hud_AnonGrey:SetValue(true)
    Toggles.Hud_Anon:SetValue(true)
    local g = featureById("AnonGrey_")
    g.ScanAt = -math.huge g:Update()
    assert(arm.Material == Enum.Material.SmoothPlastic and shirt.ShirtTemplate == "", "greyed")
    Toggles.Hud_AnonGrey:SetValue(false) g:Update()
    assert(arm.Material == Enum.Material.Plastic and shirt.ShirtTemplate == "rbxassetid://5", "restored")
    Toggles.Hud_Anon:SetValue(false)
    LPx3.Character = c0
end
print("tests_v92 ok")
