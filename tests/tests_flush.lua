
-- ===== harness actions =====
RUN_DEFERRED()
local UIS_ = game:GetService("UserInputService")
local function findClass(root, class)
    for _, d in ipairs(root:GetDescendants()) do if d.ClassName == class then return d end end
end
local function buttonsIn(frame) local o = {} for _, c in ipairs(frame:GetChildren()) do if c.ClassName == "TextButton" then table.insert(o, c) end end return o end
local function click(btn) FIRE(btn.MouseButton1Click) end
local function press(input) FIRE(btn and nil or UIS_.InputBegan, input, false) end

FLUSH_TWEENS() assert(Window.Active == Tabs.Players, "first tab active")
FLUSH_TWEENS() assert(Tabs.Players.ActiveSub ~= nil and #Tabs.Players.SubTabs == 5, "subtabs") -- [v73] Survivor / Killer / Spectator / Bot / World (Effects убрана)
for _, t in pairs(Tabs) do if t.SubTabs then Window:SelectTab(t) end end -- [v73] Tabs.World - подвкладка
Window:SelectTab(Tabs.Players)
Tabs.Players:SelectSub(KillerPage)
FLUSH_TWEENS() assert(KillerPage.Scroll.Visible and not SurvPage.Scroll.Visible, "subtab visibility")
-- [v73] Visuals (Category): групбокс «Category» во всю ширину сверху, в нём только иконки; клик - подвкладка
FLUSH_TWEENS() assert(Tabs.Players.SubBar and Tabs.Players.SubBar.Visible and KillerPage.TypeRow == nil, "category bar")
local catTitle
for _, d in ipairs(Tabs.Players.SubBar:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Category" then catTitle = d end end
assert(catTitle, "category title")
assert(KillerPage.Groups[1].Name ~= "ESP type" and KillerPage.Scroll.Position.Y.Offset == 82, "page below the category box")
assert(BotPage.Nav and BotPage.Nav.Item.Parent == Tabs.Players.SubRow and BotPage.Nav.Item:FindFirstChildWhichIsA("ImageLabel", true), "icon button")
click(BotPage.Nav.Item)
FLUSH_TWEENS() assert(Tabs.Players.ActiveSub == BotPage and BotPage.Scroll.Visible, "switch click")
assert(Tabs.World.SwitchTab == Tabs.Players and Tabs.World.Nav, "world is a visuals subtab")
assert(Tabs.Survivor.SubTabs[1].Nav ~= nil and Tabs.Survivor.SubBar ~= nil, "other tabs use the same subbar")
Window:SelectTab(Tabs.Misc)
Tabs.Players:SelectSub(SurvPage)
Window:SelectTab(Tabs.Players)
FLUSH_TWEENS() assert(SurvPage.Scroll.Visible, "select sub while other tab active")
Tabs.Players:SelectSub(KillerPage)
click(Tabs.Misc.Nav.Item)
FLUSH_TWEENS() assert(Window.Active == Tabs.Misc, "nav click")
Window:SelectTab(Tabs.Players)

-- toggle by row click
FLUSH_TWEENS() assert(Toggles.Cone_Enabled.Value == false)
click(Toggles.Cone_Enabled.Row)
FLUSH_TWEENS() assert(Toggles.Cone_Enabled.Value == true, "row click toggles")
local fired = 0
Toggles.KillerChams_Enabled:OnChanged(function() fired += 1 end)
Toggles.KillerChams_Enabled:SetValue(true)
FLUSH_TWEENS() assert(fired == 1)

-- slider
Options.KillerChams_FillTransparency:SetValue(0.333)
FLUSH_TWEENS() assert(Options.KillerChams_FillTransparency.Value == 0.33, "rounding " .. Options.KillerChams_FillTransparency.Value)
Options.GenProgress_Height:SetValue(10)
FLUSH_TWEENS() assert(Options.GenProgress_Height.Value == 4, "clamp")

-- color picker: open popup via swatch, drag SV + hue, hex input
local swatch = buttonsIn(Options.KillerChams_WallMode.Right)[1]
FLUSH_TWEENS() assert(swatch, "swatch exists")
click(swatch)
local popups = Library.ScreenGui:FindFirstChild("Popups")
FLUSH_TWEENS() assert(#popups:GetChildren() == 2, "popup + blocker")
local frame = popups:GetChildren()[2]
local sv, hue = nil, nil
for _, c in ipairs(frame:GetChildren()) do
    if c.ClassName == "TextButton" then if not sv then sv = c else hue = c end end
end
FIRE(sv.InputBegan, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(150, 130, 0) })
FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(160, 140, 0) })
FIRE(UIS_.InputEnded, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(160, 140, 0) })
FIRE(hue.InputBegan, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(150, 400, 0) })
FIRE(UIS_.InputEnded, { UserInputType = Enum.UserInputType.MouseButton1 })
-- [v74] как у skeet: без заголовка и hex-поля, 135x120
assert(findClass(frame, "TextBox") == nil and frame.Size.X.Offset == 135 and frame.Size.Y.Offset == 120, "skeet color picker")
for _, d in ipairs(frame:GetDescendants()) do assert(d.ClassName ~= "TextLabel", "no title in color picker") end
click(popups:GetChildren()[1]) -- blocker closes
FLUSH_TWEENS() assert(#popups:GetChildren() == 0, "popup closed")
-- правый клик: Copy / Paste
Options.KillerChams_FillColor:SetValueRGB(Color3.fromHex("ff8800"))
FIRE(swatch.MouseButton2Click) FLUSH_TWEENS()
local copyBtn
for _, d in ipairs(popups:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Copy" then copyBtn = d.Parent end end
assert(copyBtn, "copy menu") click(copyBtn) FLUSH_TWEENS()
local sw2 = buttonsIn(Options.KillerChams_VisMat.Right)[1]
FIRE(sw2.MouseButton2Click) FLUSH_TWEENS()
local pasteBtn
for _, d in ipairs(popups:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "Paste" then pasteBtn = d.Parent end end
click(pasteBtn) FLUSH_TWEENS()
assert(Options.KillerChams_VisColor.Value:ToHex() == "ff8800", "paste color " .. Options.KillerChams_VisColor.Value:ToHex())

-- slider drag via hit button
-- (find a slider row: ESP text size) - BeginDrag path
-- key picker rebinding
local menuLabelRight = nil
local kp = Options.MenuKeybind
FLUSH_TWEENS() assert(kp.Value == "RightShift")
Library.ToggleKeybind = kp
-- open/close menu by key
local main = Library.ScreenGui:FindFirstChild("Main")
FLUSH_TWEENS() assert(main.Visible == true)
FIRE(UIS_.InputBegan, { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.RightShift }, false)
FLUSH_TWEENS() assert(main.Visible == false, "toggle hide")
FIRE(UIS_.InputBegan, { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.RightShift }, false)
FLUSH_TWEENS() assert(main.Visible == true, "toggle show")
kp:SetValue("Insert")
FIRE(UIS_.InputBegan, { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Insert }, false)
FLUSH_TWEENS() assert(main.Visible == false, "rebound key")
Library:Toggle(true)

-- search
Tabs.Players:SelectSub(Tabs.World) Window:SelectTab(Tabs.Players) -- [v73]
-- [v49] поля поиска в окне нет (у skeet его нет), фильтр - через Window:SetSearch
Window:SetSearch("pallet")
local page = Window:CurrentPage()
local vis = 0
for _, r in ipairs(page.Rows) do if r.Row.Visible then vis += 1 end end
FLUSH_TWEENS() assert(vis == 1, "search filtered rows: " .. vis)
Window:SetSearch("")
vis = 0
for _, r in ipairs(page.Rows) do if r.Row.Visible then vis += 1 end end
FLUSH_TWEENS() assert(vis == #page.Rows, "search cleared")

-- notify
Library:Notify({ Title = "Test", Description = "hello", Time = 1 })
Library:Notify("plain string", 2)

-- configs
local ok, err = SaveManager:Save("test")
FLUSH_TWEENS() assert(ok, tostring(err))
Toggles.KillerChams_Enabled:SetValue(false)
Options.KillerChams_FillColor:SetValueRGB(Color3.new(0, 0, 0))
FLUSH_TWEENS() assert(SaveManager:Load("test"))
FLUSH_TWEENS() assert(Toggles.KillerChams_Enabled.Value == true, "config restored toggle")
FLUSH_TWEENS() assert(Options.KillerChams_FillColor.Value:ToHex() == "ff8800", "config restored color")
local list = SaveManager:List()
FLUSH_TWEENS() assert(#list == 1 and list[1] == "test", "list")
Options.SaveManager_ConfigList:SetValue("test")
-- header config dropdown -> pick
Window.ConfigProvider.Save()
Window.ConfigProvider.Load("test")
local cfgBtn
for _, d in ipairs(main:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == "test" then cfgBtn = d.Parent end end
FLUSH_TWEENS() assert(cfgBtn, "presets list shows config name")
-- [v71] Presets как у skeet: строка списка -> имя в поле; Reset / Export / автозагрузка
Options.SaveManager_ConfigName:SetValue("")
click(cfgBtn)
FLUSH_TWEENS() assert(Options.SaveManager_ConfigList.Value == "test" and Options.SaveManager_ConfigName.Value == "test", "pick preset")
Toggles.KillerChams_Enabled:SetValue(true)
assert(SaveManager:Reset() and Toggles.KillerChams_Enabled.Value == false, "reset to defaults")
SaveManager.RefreshList("test")
assert(Options.SaveManager_Autoload and table.find(Options.SaveManager_Autoload.Values, "test"), "autoload list")
assert(Options.ThemeManager_DPI and Toggles.ThemeManager_Confirm and Toggles.ThemeManager_Streamer and Options.ThemeManager_AnimSpeed, "menu settings")
Options.ThemeManager_AnimSpeed:SetValue(200)
assert(Library.AnimSpeed == 2, "anim speed")
Options.ThemeManager_AnimSpeed:SetValue(100)

-- theme
Options.ThemeManager_Accent:SetValueRGB(Color3.fromRGB(255, 0, 0))
FLUSH_TWEENS() assert(Library.Scheme.AccentColor:ToHex() == "ff0000")
-- dropdown open
local dd = Options.SaveManager_ConfigList

-- tooltips
RUN_DEFERRED()

-- unload
local unloaded = false
Library:OnUnload(function() unloaded = true end)
Library:Unload()
FLUSH_TWEENS() assert(unloaded and Library.Unloaded)
print("ALL TESTS PASSED")
local up = UNKNOWN_PROPS()
local names = {}
for k, n in pairs(up) do table.insert(names, k .. "=" .. n) end
table.sort(names)
print("props not in KNOWN list:", table.concat(names, ", "))
