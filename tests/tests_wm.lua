
-- ===== watermark tests =====
FLUSH_TWEENS()
local SG = Library.ScreenGui
local RS = game:GetService("RunService")
local StatsS = game:GetService("Stats")
-- фейковый пинг через Stats.Network.ServerStatsItem["Data Ping"]
local net = Instance.new("Folder") net.Name = "Network" net.Parent = StatsS
local ssi = Instance.new("Folder") ssi.Name = "ServerStatsItem" ssi.Parent = net
local dp = Instance.new("Folder") dp.Name = "Data Ping" dp.Parent = ssi
local PING = 53
rawset(dp, "__extra", { GetValue = function() return PING end })
rawset(StatsS, "__extra", { GetTotalMemoryUsageMb = function() return 812.4 end })

local bar = SG:FindFirstChild("Watermark")
local WM = Library.WatermarkObj
assert(bar and WM and WM.Bar == bar, "watermark exists")
local inset = game:GetService("GuiService"):GetGuiInset()
-- [v52] полоса до самого края экрана (без обрыва справа)
assert(bar.AnchorPoint == Vector2.new(1, 0) and bar.Position.X.Offset == 0 and bar.Position.Y.Offset == 4 - inset.Y, "top-right, flush to the screen edge")
assert(bar.Size.Y.Offset == 24 and math.abs(bar.BackgroundTransparency - 0.35) < 1e-9, "24px, 65% opaque")
-- ФИКС взрыва: у плашки нет авто-размера и раскладки, ширина конечная
assert(bar.AutomaticSize == nil or bar.AutomaticSize == Enum.AutomaticSize.None, "no autosize")
assert(bar:FindFirstChildOfClass("UIListLayout") == nil, "no list layout in bar")
assert(bar:FindFirstChild("FX_shadow") == nil, "no shadow (skeet)") -- [v48]
for i = 1, 20 do FIRE(RS.Heartbeat, 1 / 60) end -- 60 fps
local function cell(k) return WM.Cells[k] end
-- [v50] как «gamesense»: «visuals» + «hub» акцентом
-- [v72] переименовано в gamesense: «game» + «sense» акцентом
assert(cell("Logo").Cell.Visible and cell("Logo").Label.Text == "game" and cell("Logo").Accent.Text == "sense", "logo = script name: " .. tostring(cell("Logo").Label.Text))
assert(cell("Logo").Accent.TextColor3 == Library.Scheme.AccentColor, "logo tail in accent")
assert(cell("Latency").Icon.Parent.Visible == false, "no icons (gamesense)")
assert(not cell("Avatar").Cell.Visible, "no avatar by default (gamesense)")
assert(cell("Username").Cell.Visible and cell("Username").Label.Text == game:GetService("Players").LocalPlayer.Name, "username")
-- [v52] значение и единица раздельно, единица мелкими капителями («25 PING» у gamesense)
assert(cell("Latency").Label.Text == "53" and cell("Latency").Unit.Text == "PING", "ping " .. cell("Latency").Label.Text)
assert(cell("Framerate").Label.Text == "60" and cell("Framerate").Unit.Text == "FPS", "fps " .. cell("Framerate").Label.Text)
assert(cell("Framerate").Unit.TextSize < cell("Framerate").Label.TextSize, "small-caps unit")
assert(string.match(cell("Time").Label.Text, "^%d%d:%d%d$"), "time " .. cell("Time").Label.Text)
assert(not cell("Speed").Cell.Visible and not cell("Memory").Cell.Visible and not cell("Server").Cell.Visible, "non-default items hidden")
assert(cell("Latency").Label.TextColor3 == Library.Scheme.AccentColor, "ping value in accent, like «25» on gamesense") -- [v52]
assert(cell("Latency").Icon.ImageColor3 == Library.Scheme.AccentColor, "accent icon")
-- плохой пинг -> Additional Color
PING = 220
for i = 1, 20 do FIRE(RS.Heartbeat, 1 / 60) end
assert(cell("Latency").Label.Text == "220" and cell("Latency").Label.TextColor3 == WM.AltColor, "warn color on high ping")
assert(cell("Var").Cell.Visible == false, "var off")
PING = 53

-- правый клик -> панель настроек (две панели), Items -> список
local popups = SG:FindFirstChild("Popups")
FIRE(bar.MouseButton2Click)
FLUSH_TWEENS()
local cont = popups:GetChildren()[2]
assert(cont and cont.BackgroundTransparency == 1, "bare container")
local panels = {}
for _, c in ipairs(cont:GetChildren()) do if c.ClassName == "TextButton" then table.insert(panels, c) end end
assert(#panels == 1, "only settings panel at first")
local set = panels[1]
local function rowByText(parent, t)
    for _, d in ipairs(parent:GetDescendants()) do if d.ClassName == "TextLabel" and d.Text == t then return d.Parent end end
end
assert(rowByText(set, "Watermark") and rowByText(set, "Additional Color") and rowByText(set, "Display Avatar"), "settings rows")
FIRE(rowByText(set, "Items").MouseButton1Click)
local list
for _, c in ipairs(cont:GetChildren()) do if c.ClassName == "TextButton" and c ~= set then list = c end end
assert(list, "items list opened")
local n = 0
for _, c in ipairs(list:GetChildren()) do if c.ClassName == "TextButton" then n += 1 end end
assert(n == 11, "11 items (with Avatar): " .. n)
-- включить Speed и Memory, выключить Time
FIRE(rowByText(list, "Speed").MouseButton1Click)
FIRE(rowByText(list, "Memory Load").MouseButton1Click)
FIRE(rowByText(list, "Time").MouseButton1Click)
FLUSH_TWEENS() RUN_DEFERRED()
assert(cell("Speed").Cell.Visible and cell("Memory").Cell.Visible and not cell("Time").Cell.Visible, "items toggled live")
assert(cell("Memory").Label.Text == "812" and cell("Memory").Unit.Text == "MB" and cell("Speed").Label.Text == "0" and cell("Speed").Unit.Text == "SPEED", "mem/speed text")
-- аватар
local avC = WM.Cells.Avatar
assert(not avC.Cell.Visible, "avatar off by default") -- [v50]
FIRE(rowByText(set, "Display Avatar").MouseButton1Click)
FLUSH_TWEENS() RUN_DEFERRED()
assert(avC.Cell.Visible and WM.Items.Avatar, "avatar shown via Display Avatar")
FIRE(rowByText(set, "Display Avatar").MouseButton1Click)
FLUSH_TWEENS() RUN_DEFERRED()
assert(not avC.Cell.Visible and not WM.Items.Avatar, "avatar hidden via Display Avatar")
-- в списке Items галочка аватара тоже снялась (синхронно)
local avListRow = rowByText(list, "Avatar")
local chkVisible = false
for _, d in ipairs(avListRow:GetDescendants()) do if d.ClassName == "ImageLabel" and d.Visible and d.Parent.Size.X.Offset == 12 and d.Parent.Position.X.Offset == 11 then chkVisible = true end end
assert(not chkVisible, "list checkmark synced")
-- цвет
assert(rowByText(set, "Additional Color"):GetDescendants() and true)
Library:ClosePopup() FLUSH_TWEENS()
assert(#popups:GetChildren() == 0, "settings closed")
-- сохранение/загрузка
local saved = WM:Serialize()
assert(#saved.items == 6 and saved.avatar == false, "serialize")
WM:Load({ enabled = true, avatar = true, items = { "Logo", "Time" }, color = "ff0000" })
FLUSH_TWEENS() RUN_DEFERRED()
assert(cell("Time").Cell.Visible and not cell("Speed").Cell.Visible and WM.AltColor:ToHex() == "ff0000", "load")
WM:Load(saved)
-- выключатель в Theme
Toggles.ThemeManager_Watermark:SetValue(false)
assert(bar.Visible == false, "watermark off")
Toggles.ThemeManager_Watermark:SetValue(true)
assert(bar.Visible == true, "watermark on")
-- ширина = сумма пунктов (мок: текст 7px/символ; [v50] без иконок, слева 22 под растворение, между пунктами 14) + отступы
FLUSH_TWEENS()
local function visKeys() local o = {} for _, k in ipairs(WM.Order) do if WM.Items[k] then table.insert(o, k) end end return o end
local function expectedW()
    local x = 22
    for _, k in ipairs(visKeys()) do
        local C = WM.Cells[k]
        x += (C.Fixed or C.W or (#C.Label.Text * 7 + (C.Accent and #C.Accent.Text * 7 or 0))) + 14
    end
    local vk = visKeys()
    return x + ((vk[#vk] == "Avatar") and 4 or 34) - 14 -- [v52] справа поле 12; [v59] 34 под растворение
end
WM:Refresh() FLUSH_TWEENS()
assert(bar.Size.X.Offset == expectedW(), "bar width " .. bar.Size.X.Offset .. " vs " .. expectedW())
-- пункты стоят по порядку слева направо
-- ФИКС дёрганья: 65 -> 68 MS и 1 -> 2 VAR ширину не меняют; 220 -> 53 сужает только через 2 с
do
    local lat = WM.Cells.Latency
    PING = 65 WM:Refresh() local w1 = lat.W
    PING = 68 WM:Refresh() assert(lat.W == w1, "65->68 same width")
    PING = 9 WM:Refresh() assert(lat.W == w1, "shrink is delayed")
    lat.ShrinkAt = os.clock() - 1 WM:Refresh()
    assert(lat.W < w1, "shrinks after delay")
    PING = 53 WM:Refresh() FLUSH_TWEENS()
end
-- аватар - обычный пункт: по умолчанию последний, центрирован по вертикали
WM.Items.Avatar = true WM:Refresh() FLUSH_TWEENS()
local avImg = WM.Cells.Avatar.Avatar
assert(avImg.AnchorPoint == Vector2.new(0, 0.5) and avImg.Position.Y.Scale == 0.5, "avatar centered in its cell")
do local vk = visKeys() assert(vk[#vk] == "Avatar", "avatar last by default") end
-- аватар таскается: в начало
FIRE(WM.Cells.Avatar.Hit.InputBegan, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(100, 10, 0) })
FIRE(game:GetService("UserInputService").InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(-500, 10, 0) })
FIRE(game:GetService("UserInputService").InputEnded, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(-500, 10, 0) })
FLUSH_TWEENS()
assert(visKeys()[1] == "Avatar", "avatar dragged to front: " .. table.concat(visKeys(), ","))
-- обратно в конец
FIRE(WM.Cells.Avatar.Hit.InputBegan, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(100, 10, 0) })
FIRE(game:GetService("UserInputService").InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(3000, 10, 0) })
FIRE(game:GetService("UserInputService").InputEnded, { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(3000, 10, 0) })
FLUSH_TWEENS()
do local vk = visKeys() assert(vk[#vk] == "Avatar", "avatar back to end") end
-- старое сохранение с флагом avatar=false убирает аватар
WM:Load({ avatar = false, items = { "Logo", "Time" } })
assert(not WM.Items.Avatar, "legacy avatar flag")
WM:Load({ items = { "Logo", "Framerate", "Latency", "Username", "Time", "Avatar" } })
local prev = -1
for _, k in ipairs(visKeys()) do
    local x = WM.Cells[k].Cell.Position.X.Offset
    assert(x > prev, "cells ordered") prev = x
end

-- перетаскивание: Time в начало
local UIS_ = game:GetService("UserInputService")
local MB1 = Enum.UserInputType.MouseButton1
local timeC = WM.Cells.Username
local before = table.concat(visKeys(), ",")
-- просто клик (без движения) порядок не меняет
FIRE(timeC.Hit.InputBegan, { UserInputType = MB1, Position = Vector3.new(100, 10, 0) })
FIRE(UIS_.InputEnded, { UserInputType = MB1, Position = Vector3.new(100, 10, 0) })
assert(table.concat(visKeys(), ",") == before, "click does not reorder")
FIRE(timeC.Hit.InputBegan, { UserInputType = MB1, Position = Vector3.new(100, 10, 0) })
FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(131, 10, 0) })
assert(math.abs(timeC.Label.TextTransparency - 0.45) < 1e-9 and timeC.Cell.ZIndex == 5, "ghost while dragging")
FLUSH_TWEENS()
-- «призрак» центром правее центра Logo -> щель сразу после Logo, следующий пункт сдвинут на ширину призрака + 14
-- [v50] логотип = «visuals» + «hub», без бейджа; пункты без иконок; слева 22, между пунктами 14
local logoW = (#WM.Cells.Logo.Label.Text + #WM.Cells.Logo.Accent.Text) * 7
local ghostW = timeC.W or #timeC.Label.Text * 7
local second = visKeys()[2]
assert(WM.Cells.Logo.Cell.Position.X.Offset == 22, "logo stays")
assert(WM.Cells[second].Cell.Position.X.Offset == 22 + logoW + 14 + ghostW + 14, "gap opened after logo: " .. WM.Cells[second].Cell.Position.X.Offset)
FIRE(UIS_.InputEnded, { UserInputType = MB1, Position = Vector3.new(131, 10, 0) })
FLUSH_TWEENS()
assert(visKeys()[2] == "Username", "Username moved after Logo: " .. table.concat(visKeys(), ","))
assert(timeC.Label.TextTransparency == 0 and timeC.Cell.ZIndex == 1 and timeC.Cell.Position.X.Offset == 22 + logoW + 14, "dropped into slot")
-- перетаскивание вправо до конца
local logoC = WM.Cells.Logo
FIRE(logoC.Hit.InputBegan, { UserInputType = MB1, Position = Vector3.new(100, 10, 0) })
FIRE(UIS_.InputChanged, { UserInputType = Enum.UserInputType.MouseMovement, Position = Vector3.new(2000, 10, 0) })
FIRE(UIS_.InputEnded, { UserInputType = MB1, Position = Vector3.new(2000, 10, 0) })
FLUSH_TWEENS()
local vk = visKeys()
assert(vk[#vk] == "Logo", "Logo moved to end: " .. table.concat(vk, ","))
-- порядок сохраняется и загружается
local ser = WM:Serialize()
assert(ser.order and #ser.order == 11, "order saved")
WM:Load({ order = { "Time", "Bogus", "Logo" } })
assert(WM.Order[1] == "Time" and WM.Order[2] == "Logo" and #WM.Order == 11, "order load merges")
WM:Load(ser)
-- плавное появление пункта
WM.Items.Server = true
WM:Refresh()
assert(WM.Cells.Server.Cell.Visible, "new item visible")
FLUSH_TWEENS()
assert(WM.Cells.Server.Label.TextTransparency == 0, "faded in")
WM.Items.Server = nil
WM:Refresh() FLUSH_TWEENS()
RUN_DEFERRED()
assert(WM.Cells.Server.Label.TextTransparency == 1, "faded out")

-- [v48] у skeet теней нет нигде (в том числе у подсказки)
local anyShadow = false
for _, c in ipairs(SG:GetDescendants()) do if c.Name == "FX_shadow" then anyShadow = true end end
assert(not anyShadow, "no shadows anywhere")
print("WM TESTS PASSED")
