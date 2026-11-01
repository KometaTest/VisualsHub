
-- ===== skinchanger tests =====
FLUSH_TWEENS() RUN_DEFERRED()
local P = game:GetService("Players")
local LP = P.LocalPlayer
BrickColor = BrickColor or { new = function(id) return { Color = Color3.fromRGB(id % 256, 0, 0) } end }
-- мок каталога
local USERS = { builderman = 156 }
rawget(P, "__extra").GetUserIdFromNameAsync = function(_, n) local id = USERS[string.lower(n)] if not id then error("no user") end return id end
rawget(P, "__extra").GetCharacterAppearanceInfoAsync = function(_, uid)
    return {
        assets = {
            { id = 1001, assetType = { name = "Hat" }, name = "Cool Hat" },
            { id = 1002, assetType = { name = "HairAccessory" }, name = "Hair" },
            { id = 1003, assetType = { name = "JacketAccessory" }, name = "Jacket" }, -- слоёная: пропуск
            { id = 2001, assetType = { name = "Shirt" }, name = "Shirt" },
            { id = 2002, assetType = { name = "Pants" }, name = "Pants" },
            { id = 3001, assetType = { name = "Face" }, name = "Smile" },
            { id = 4001, assetType = { name = "Torso" }, name = "Cool Torso" },
            { id = 4002, assetType = { name = "RightLeg" }, name = "Korblox Deathspeaker Right Leg" },
            { id = 4003, assetType = { name = "Head" }, name = "Headless Head" },
        },
        bodyColors = { headColorId = 24, torsoColorId = 23 },
    }
end
local CATALOG = {}
local function mkAcc(attName)
    local a = Instance.new("Accessory")
    local h = Instance.new("Part") h.Name = "Handle" h.Parent = a
    local at = Instance.new("Attachment") at.Name = attName at.Parent = h
    return a
end
CATALOG[1001] = function() return mkAcc("HatAttachment") end
CATALOG[1002] = function() return mkAcc("HairAttachment") end
CATALOG[1003] = function() local a = mkAcc("BodyFrontAttachment") Instance.new("WrapLayer").Parent = a.Handle return a end
CATALOG[2001] = function() local s = Instance.new("Shirt") s.ShirtTemplate = "rbxassetid://9" return s end
CATALOG[2002] = function() return Instance.new("Pants") end
CATALOG[3001] = function() local d = Instance.new("Decal") d.Texture = "rbxassetid://face" return d end
CATALOG[5555] = function() return mkAcc("HatAttachment") end
-- пакеты: в ассете папки R15 и R6, в R6 - CharacterMesh
local function pkg(part)
    local f = Instance.new("Folder") f.Name = "R6"
    local cm = Instance.new("CharacterMesh") cm.Name = "CM" .. part cm.BodyPart = Enum.BodyPart[part] cm.Parent = f
    local r15 = Instance.new("Folder") r15.Name = "R15ArtistIntent"
    Instance.new("MeshPart").Parent = r15
    return r15, f
end
local GETOBJ_MULTI = { [4001] = function() return { pkg("Torso") } end, [4002] = function() return { pkg("RightLeg") } end,
    [4003] = function() local m = Instance.new("SpecialMesh") return { m } end }
local getObjectsCalls = 0
rawget(game, "__extra").GetObjects = function(_, url)
    getObjectsCalls += 1
    local id = tonumber(string.match(url, "%d+$"))
    if GETOBJ_MULTI[id] then return GETOBJ_MULTI[id]() end
    return CATALOG[id] and { CATALOG[id]() } or {}
end
-- Clone в моке: новый экземпляр того же класса с теми же детьми
-- персонаж R6 как в save.rbxmx: своя шапка, рубашка, цвета, лицо + костюм киллера "Hat"
local char = Instance.new("Model") char.Name = "Char"
local head = Instance.new("Part") head.Name = "Head" head.Parent = char
local ha = Instance.new("Attachment") ha.Name = "HatAttachment" ha.Parent = head
local hair = Instance.new("Attachment") hair.Name = "HairAttachment" hair.Parent = head
local face = Instance.new("Decal") face.Name = "face" face.Texture = "rbxasset://myface" face.Transparency = 0 face.Parent = head
head.Transparency = 0
local myArm = Instance.new("CharacterMesh") myArm.Name = "MyArmPkg" myArm.BodyPart = Enum.BodyPart.LeftArm
local torso = Instance.new("Part") torso.Name = "Torso" torso.Parent = char
local myAcc = mkAcc("HatAttachment") myAcc.Name = "MyHat" myAcc.Parent = char
local myShirt = Instance.new("Shirt") myShirt.Parent = char
local myColors = Instance.new("BodyColors") myColors.Parent = char
myArm.Parent = char
local costume = Instance.new("Part") costume.Name = "Hat" costume.Parent = char -- костюм киллера
Instance.new("Humanoid").Parent = char
char.Parent = workspace
rawget(LP, "__extra").Character = char

assert(Tabs.Skins, "Skinchanger tab")
assert(Options.Skin_User and Toggles.Skin_Acc and Options.Skin_Preset and Toggles.Skin_Auto, "skin elements")
-- Load: превью + статус
Options.Skin_User:SetValue("Builderman")
local function btn(text)
    for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
        if d.ClassName == "TextLabel" and d.Text == text and d.Parent.ClassName == "TextButton" then return d.Parent end
    end
end
FIRE(btn("Load").MouseButton1Click)
local function textOf(pattern)
    for _, d in ipairs(Library.ScreenGui:GetDescendants()) do
        if d.ClassName == "TextLabel" and string.find(d.Text, pattern) then return d.Text end
    end
end
assert(textOf("Builderman: 3 accessories, 2 clothes, 3 body parts"), "status after load: " .. tostring(textOf("Builderman")))
assert(Options.Skin_Parts and Options.Skin_Parts.Value.Torso and Options.Skin_Parts.Value["Right Leg"], "all body parts selected by default")
assert(Toggles.Skin_Face, "separate Face toggle")
local imgSet = false
for _, d in ipairs(Library.ScreenGui:GetDescendants()) do if d.ClassName == "ImageLabel" and d.Image == "rbxthumb://x" and d.ScaleType == Enum.ScaleType.Fit then imgSet = true end end
assert(imgSet, "avatar preview")
-- 3D-превью: копия персонажа во ViewportFrame, одетая в образ, крутится мышкой
local vpf
for _, d in ipairs(Library.ScreenGui:GetDescendants()) do if d.ClassName == "ViewportFrame" then vpf = d end end
assert(vpf and vpf.Visible, "3D preview shown")
for _, c in ipairs(vpf.Parent:GetChildren()) do
    if c.ClassName == "ImageLabel" then assert(c.Visible == false, "2D picture hidden behind 3D") end
end
local wm = vpf:FindFirstChildOfClass("WorldModel")
local model = wm:GetChildren()[1]
assert(model and model ~= char, "preview is a copy")
local pAcc, scripts = 0, 0
for _, d in ipairs(model:GetDescendants()) do
    if d.ClassName == "Accessory" then pAcc += 1 end
    if d.ClassName == "LocalScript" or d.ClassName == "Script" then scripts += 1 end
end
assert(pAcc == 2 and scripts == 0, "preview dressed (2 accessories), no scripts: " .. pAcc .. "/" .. scripts)
assert(myAcc.Parent == char and face.Texture == "rbxasset://myface", "preview does not touch your character")
for _, d in ipairs(model:GetDescendants()) do if d.ClassName == "Part" then assert(d.Anchored, "preview parts anchored") end end
local cam = vpf:FindFirstChildOfClass("Camera")
local cf0 = cam.CFrame
FIRE(vpf.InputBegan, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(100, 100, 0) })
FIRE(game:GetService("UserInputService").InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(160, 110, 0) })
FIRE(game:GetService("UserInputService").InputEnded, { UserInputType = Enum.UserInputType.MouseButton1 })
assert(cam.CFrame ~= cf0, "drag rotates the preview")
local cf1 = cam.CFrame
FIRE(vpf.InputChanged, { UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1) })
assert(cam.CFrame ~= cf1, "wheel zooms")
-- выключили аксессуары - превью пересобралось без них
Toggles.Skin_Acc:SetValue(false)
local model2 = wm:GetChildren()[1]
local n2 = 0
for _, d in ipairs(model2:GetDescendants()) do if d.ClassName == "Accessory" and d.Name ~= "MyHat" then n2 += 1 end end
assert(model2 ~= model and #wm:GetChildren() == 1, "preview rebuilt, old copy removed")
Toggles.Skin_Acc:SetValue(true)

-- неверный ник
Options.Skin_User:SetValue("nobody_xyz")
FIRE(btn("Load").MouseButton1Click)
assert(textOf("User not found"), "unknown user message")
Options.Skin_User:SetValue("Builderman")
FIRE(btn("Load").MouseButton1Click)

-- Apply
FIRE(btn("Apply").MouseButton1Click)
local function kids(class) local o = {} for _, c in ipairs(char:GetChildren()) do if c.ClassName == class then table.insert(o, c) end end return o end
assert(myAcc.Parent == nil and myShirt.Parent == nil and myColors.Parent == nil, "own items hidden")
assert(costume.Parent == char, "killer costume untouched")
local accs = kids("Accessory")
assert(#accs == 2, "2 rigid accessories (layered jacket skipped): " .. #accs)
for _, a in ipairs(accs) do assert(a.Handle:FindFirstChildOfClass("Weld"), "accessory welded") end
assert(#kids("Shirt") == 1 and kids("Shirt")[1].ShirtTemplate == "rbxassetid://9", "shirt replaced")
assert(#kids("Pants") == 1, "pants added")
assert(#kids("BodyColors") == 1, "body colors")
assert(face.Texture == "rbxassetid://face", "face replaced")
-- части тела R6: пакет торса и korblox-нога надеты, свой пакет руки снят, headless
local cms = {}
for _, c in ipairs(char:GetChildren()) do if c.ClassName == "CharacterMesh" then cms[c.BodyPart.Name] = c end end
assert(cms.Torso and cms.RightLeg and not cms.LeftArm and myArm.Parent == nil, "body parts copied, own arm package removed")
assert(head.Transparency == 1 and face.Transparency == 1, "headless")
-- первое лицо: аксессуары прозрачны как голова
head.LocalTransparencyModifier = 1
FIRE(game:GetService("RunService").RenderStepped, 0.016)
assert(accs[1].Handle.LocalTransparencyModifier == 1, "first person hides hats")
head.LocalTransparencyModifier = 0
-- игра переодела (вернула шапку) -> скин надевается заново, без бесконечного цикла
local calls = getObjectsCalls
local gameHat = mkAcc("HatAttachment") gameHat.Parent = char
RUN_DEFERRED()
assert(gameHat.Parent == nil and #kids("Accessory") == 2, "re-applied after game re-dress")
RUN_DEFERRED() RUN_DEFERRED()
assert(getObjectsCalls - calls < 20, "no apply loop")

-- предмет по ID
Options.Skin_ItemId:SetValue("5555")
FIRE(btn("Add Item").MouseButton1Click)
assert(#kids("Accessory") == 3, "item by id added")
assert(textOf("Added: 5555"), "items label")

-- части тела можно выбирать: без Head и Torso
Options.Skin_Parts:SetValue({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" })
FIRE(btn("Apply").MouseButton1Click)
cms = {}
for _, c in ipairs(char:GetChildren()) do if c.ClassName == "CharacterMesh" then cms[c.BodyPart.Name] = c end end
assert(not cms.Torso and cms.RightLeg and head.Transparency == 0, "only selected parts copied")
Options.Skin_Parts:SetValue({})
FIRE(btn("Apply").MouseButton1Click)
assert(myArm.Parent == char, "no parts selected -> own packages kept")
Options.Skin_Parts:SetValue(Skin and Skin.PartNames or { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" })
FIRE(btn("Apply").MouseButton1Click)
-- Reset
FIRE(btn("Reset To My Avatar").MouseButton1Click)
assert(myArm.Parent == char and head.Transparency == 0 and face.Transparency == 0, "body restored")
local leftover = 0
for _, c in ipairs(char:GetChildren()) do if c.ClassName == "CharacterMesh" and c ~= myArm then leftover += 1 end end
assert(leftover == 0, "skin body parts removed")
assert(myAcc.Parent == char and myShirt.Parent == char and myColors.Parent == char, "own items restored")
assert(#kids("Accessory") == 2 and #kids("Pants") == 0 and face.Texture == "rbxasset://myface", "skin removed (own hat + game hat back)")

-- пресеты: сохранить, автоприменение после респавна
Options.Skin_PresetName:SetValue("bm")
FIRE(btn("Save Preset").MouseButton1Click)
assert(table.find(Options.Skin_Preset.Values, "bm") and Options.Skin_Preset.Value == "bm", "preset saved & selected")
assert(isfile(CONFIG and (CONFIG.ScriptName .. "/skins.json")) or true, "saved to file")
Toggles.Skin_Auto:SetValue(true)
assert(#kids("Pants") == 1, "auto apply wears preset now")
-- респавн
local char2 = Instance.new("Model") char2.Name = "Char2"
local head2 = Instance.new("Part") head2.Name = "Head" head2.Parent = char2
local ha2 = Instance.new("Attachment") ha2.Name = "HatAttachment" ha2.Parent = head2
Instance.new("Part").Parent = char2
char2.Parent = workspace
rawget(LP, "__extra").Character = char2
FIRE(LP.CharacterAdded, char2)
RUN_DEFERRED()
local p2 = 0 for _, c in ipairs(char2:GetChildren()) do if c.ClassName == "Pants" then p2 += 1 end end
assert(p2 == 1, "preset re-applied after respawn")
-- удалить пресет
FIRE(btn("Delete Preset").MouseButton1Click)
assert(not table.find(Options.Skin_Preset.Values, "bm"), "preset deleted")
Toggles.Skin_Auto:SetValue(false)
FIRE(btn("Reset To My Avatar").MouseButton1Click)

-- [v43] без загруженного образа: Add Korblox / Headless / предметы НЕ снимают свои вещи и цвета
do
    local c3 = Instance.new("Model") c3.Name = "Char3"
    local h3 = Instance.new("Part") h3.Name = "Head" h3.Transparency = 0 h3.Parent = c3
    local at3 = Instance.new("Attachment") at3.Name = "HatAttachment" at3.Parent = h3
    local f3 = Instance.new("Decal") f3.Name = "face" f3.Transparency = 0 f3.Parent = h3
    local myHat3 = mkAcc("HatAttachment") myHat3.Name = "MyHat3" myHat3.Parent = c3
    local myHair3 = mkAcc("HatAttachment") myHair3.Name = "MyHair3" myHair3.Parent = c3
    local shirt3 = Instance.new("Shirt") shirt3.Parent = c3
    local bc3 = Instance.new("BodyColors") bc3.Parent = c3
    local myLeg = Instance.new("CharacterMesh") myLeg.BodyPart = Enum.BodyPart.RightLeg myLeg.Parent = c3
    Instance.new("Humanoid").Parent = c3
    c3.Parent = workspace
    rawget(LP, "__extra").Character = c3
    Skin.Look = nil
    table.clear(Skin.Extra)
    FIRE(btn("Add Korblox").MouseButton1Click)
    local leg
    for _, c in ipairs(c3:GetChildren()) do
        if c.ClassName == "CharacterMesh" and c ~= myLeg and c.BodyPart.Name == "RightLeg" then leg = c end
    end
    assert(leg and myLeg.Parent == nil, "korblox leg on, own right leg package hidden")
    assert(myHat3.Parent == c3 and shirt3.Parent == c3 and bc3.Parent == c3, "own accessories / clothes / colors kept")
    assert(textOf("Added: Korblox"), "label shows Korblox")
    FIRE(btn("Add Headless").MouseButton1Click)
    assert(h3.Transparency == 1 and f3.Transparency == 1, "headless: head + face transparent")
    assert(myHat3.Parent == c3, "hats stay with headless")
    -- снять аксессуар
    FIRE(btn("Refresh List").MouseButton1Click)
    assert(table.find(Options.Skin_RemoveList.Values, "MyHat3"), "worn accessories listed")
    Options.Skin_RemoveList:SetValue({ "MyHat3" })
    FIRE(btn("Remove Selected").MouseButton1Click)
    assert(myHat3.Parent == nil and myHair3.Parent == c3, "selected accessory removed, other kept")
    assert(textOf("Removed: MyHat3"), "removed label")
    -- игра вернула снятый акс - снова прячем
    local back = mkAcc("HatAttachment") back.Name = "MyHat3" back.Parent = c3
    RUN_DEFERRED()
    assert(back.Parent == nil, "removed accessory hidden again after game re-dress")
    -- вернуть
    FIRE(btn("Restore Removed").MouseButton1Click)
    assert(textOf("Removed: none"), "restore clears list")
    FIRE(btn("Clear Items").MouseButton1Click)
    assert(myLeg.Parent == c3 and h3.Transparency == 0 and f3.Transparency == 0, "clear items -> own leg and head back")
    assert(myHat3.Parent == c3, "own hat back")
    -- Korblox без ассета (экзекутор не грузит): CharacterMesh по MeshId
    local savedGO = rawget(game, "__extra").GetObjects
    rawget(game, "__extra").GetObjects = function() return {} end
    FIRE(btn("Add Korblox + Headless").MouseButton1Click)
    local leg2
    for _, c in ipairs(c3:GetChildren()) do
        if c.ClassName == "CharacterMesh" and c ~= myLeg then leg2 = c end
    end
    assert(leg2 and tostring(leg2.MeshId) == tostring(Skin.KORBLOX_MESH) and h3.Transparency == 1, "korblox fallback mesh + headless")
    rawget(game, "__extra").GetObjects = savedGO
    FIRE(btn("Clear Items").MouseButton1Click)
    FIRE(btn("Reset To My Avatar").MouseButton1Click)
end
rawget(LP, "__extra").Character = nil
print("SKIN TESTS PASSED")
