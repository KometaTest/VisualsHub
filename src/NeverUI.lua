------------------------------------------------------------
-- NeverUI — UI-библиотека в стиле Neverlose.
-- API совместим с тем подмножеством Obsidian, которое использует скрипт:
--   Library.Toggles / Library.Options, :OnChanged, .Value, :SetValue
--   Window:AddTab, Tab:AddLeftGroupbox/AddRightGroupbox, Groupbox:AddCheckbox/AddSlider/
--   AddLabel/AddButton/AddDivider/AddInput/AddDropdown, :AddColorPicker, :AddKeyPicker
--   Library:Notify, Library.Scheme, Library:Unload/OnUnload, ThemeManager, SaveManager
-- Новое: Window:AddCategory (заголовок группы в сайдбаре), Tab:AddSubTab (подвкладки в шапке).
------------------------------------------------------------
local Library, ThemeManager, SaveManager = (function()
    local Players      = game:GetService("Players")
    local UIS          = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local HttpService  = game:GetService("HttpService")
    local RunService   = game:GetService("RunService")
    local GuiService   = game:GetService("GuiService")
    local LP = Players.LocalPlayer

    local FONT = "rbxasset://fonts/families/BuilderSans.json"
    local W_REG, W_MED, W_SEMI, W_BOLD = Enum.FontWeight.Regular, Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold
    local function F(w) return Font.new(FONT, w or W_MED) end

    local MB1, MB2 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2
    local TOUCH, MOVE, KB = Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement, Enum.UserInputType.Keyboard
    local AX, AY, AXY = Enum.AutomaticSize.X, Enum.AutomaticSize.Y, Enum.AutomaticSize.XY

    local Library = {
        Toggles = {}, Options = {},
        Unloaded = false, ForceCheckbox = true, ToggleKeybind = nil,
        Animations = true, -- false = всё мгновенно, как раньше
        -- ЭФФЕКТЫ (замер с видео): окно ~93% непрозрачности поверх размытого фона,
        -- мягкая тень вокруг окна/popup, свечение включённого переключателя
        Transparency = 0.07, Blur = true, Glow = true,
        -- палитра снята пипеткой с твоих скриншотов
        Scheme = {
            MainColor       = Color3.fromRGB(13, 14, 22),    -- окно / шапка        #0d0e16
            BackgroundColor = Color3.fromRGB(11, 14, 24),    -- сайдбар             #0b0e18
            GroupColor      = Color3.fromRGB(19, 20, 28),    -- панели секций       #13141c
            OutlineColor    = Color3.fromRGB(28, 29, 36),    -- рамки               #1c1d24
            SeparatorColor  = Color3.fromRGB(27, 28, 36),    -- разделители строк   #1b1c24
            ItemColor       = Color3.fromRGB(35, 37, 47),    -- выбранный пункт     #23252f
            InputColor      = Color3.fromRGB(26, 26, 39),    -- поля, dropdown      #1a1a27
            InputBorder     = Color3.fromRGB(34, 35, 44),    -- рамка полей         #22232c
            TrackColor      = Color3.fromRGB(29, 30, 40),    -- пустой слайдер      #1d1e28
            OffTrack        = Color3.fromRGB(5, 8, 15),      -- выкл. переключатель #05080f
            OffKnob         = Color3.fromRGB(125, 135, 145), --                     #7d8791
            FontColor       = Color3.fromRGB(240, 240, 242), -- подписи             #f2f2f2
            ValueColor      = Color3.fromRGB(213, 213, 218), -- текст в полях       #d5d5da
            SubColor        = Color3.fromRGB(131, 132, 139), -- неактивные пункты   #83848b
            DimColor        = Color3.fromRGB(86, 88, 96),    -- заголовки секций    #565860
            AccentColor     = Color3.fromRGB(150, 164, 255), -- акцент              #96a4ff
            Font            = F(W_MED),
        },
        _Themed = {}, _Refresh = {}, _Conns = {}, _UnloadCb = {},
    }
    local Scheme = Library.Scheme
    local DEFAULT_SCHEME = table.clone(Scheme)

    -- [v45] ТЕМЫ: полные палитры (сняты пипеткой со скринов NL). 1 - текущая, 2 - новый NL (почти чёрный,
    -- синий акцент), 3 - старый NL (синяя навигация, тёмно-синие панели, голубой акцент).
    local function HEX(h)
        h = h:gsub("#", "")
        return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
    end
    Library.Themes = {
        { Name = "Default", Scheme = table.clone(DEFAULT_SCHEME), Style = { Round = 12 } },
        { Name = "Neverlose", Scheme = {
            MainColor = HEX("0A0A0E"), BackgroundColor = HEX("0B0C0E"), GroupColor = HEX("0B0D15"),
            OutlineColor = HEX("1B1D22"), SeparatorColor = HEX("12141B"), ItemColor = HEX("141722"),
            InputColor = HEX("0D1019"), InputBorder = HEX("191C26"), TrackColor = HEX("0D1021"),
            OffTrack = HEX("0A0E16"), OffKnob = HEX("7D8791"), FontColor = HEX("F4F6F8"), ValueColor = HEX("A5B0B6"),
            SubColor = HEX("8A949E"), DimColor = HEX("434B56"), AccentColor = HEX("567DFE"),
        }, Style = { Round = 6, UpperTitles = true, DimOff = true } },
        { Name = "Neverlose Classic", Scheme = {
            MainColor = HEX("161922"), BackgroundColor = HEX("1C2636"), GroupColor = HEX("0E1E2E"),
            OutlineColor = HEX("1A2B3D"), SeparatorColor = HEX("132334"), ItemColor = HEX("0C3D5B"),
            InputColor = HEX("0D1B2B"), InputBorder = HEX("1B3149"), TrackColor = HEX("14283B"),
            OffTrack = HEX("0C121E"), OffKnob = HEX("7E8B9B"), FontColor = HEX("E0E9F2"), ValueColor = HEX("B9C6D2"),
            SubColor = HEX("A5B5C5"), DimColor = HEX("4A535A"), AccentColor = HEX("00B4FE"),
        }, Style = { Round = 6, UpperTitles = true, DimOff = true, ClassicSwitch = true, SideOwn = true } },
    }
    Library.ThemeName = "Default"
    -- [v45] стиль темы (не только цвета): Round - скругление панелей, UpperTitles - заголовки секций капсом,
    -- DimOff - подпись выключенной функции серее, ClassicSwitch - тумблер старого NL (тёмная дорожка,
    -- кружок акцентом), SideOwn - сайдбар своим цветом и при прозрачности окна
    Library.Style = { Round = 12 }
    function Library:GetTheme(name)
        for _, t in ipairs(Library.Themes) do if t.Name == name then return t end end
    end
    function Library:ApplyTheme(name)
        local t = Library:GetTheme(name)
        if not t then return false end
        for k, v in pairs(t.Scheme) do
            if k ~= "Font" then Scheme[k] = v end
        end
        Library.ThemeName = name
        Library.Style = table.clone(t.Style or { Round = 12 })
        -- пикеры темы показывают новые цвета, но их обработчики палитру не пересчитывают
        Library._ApplyingTheme = true
        local Opt = Library.Options -- (локальные Options объявлены ниже по файлу)
        pcall(function() Opt.ThemeManager_Accent:SetValueRGB(Scheme.AccentColor) end)
        pcall(function() Opt.ThemeManager_Main:SetValueRGB(Scheme.MainColor) end)
        pcall(function()
            if Opt.ThemeManager_Theme and Opt.ThemeManager_Theme.Value ~= name then Opt.ThemeManager_Theme:SetValue(name) end
        end)
        Library._ApplyingTheme = false
        Library:UpdateColors()
        if Library._ThemeSave then Library._ThemeSave() end
        return true
    end
    local Toggles, Options = Library.Toggles, Library.Options

    local WHITE     = Color3.new(1, 1, 1)

    --------------------------------------------------------
    -- helpers
    --------------------------------------------------------
    local function Create(class, props)
        local inst = Instance.new(class)
        for k, v in pairs(props) do
            if k ~= "Parent" then inst[k] = v end
        end
        if props.Parent then inst.Parent = props.Parent end
        return inst
    end

    local function Theme(inst, map)
        table.insert(Library._Themed, { inst, map })
        for prop, key in pairs(map) do inst[prop] = Scheme[key] end
        return inst
    end

    local function Safe(fn, ...)
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, ...)
        if not ok then warn("[NeverUI] callback error: " .. tostring(err)) end
    end

    local function Fire(obj)
        Safe(obj.Callback, obj.Value)
        for _, fn in ipairs(obj.Changed) do Safe(fn, obj.Value) end
    end

    local function Tween(inst, t, props)
        local tw = TweenService:Create(inst, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props)
        tw:Play()
        return tw
    end

    local function Connect(signal, fn)
        local c = signal:Connect(fn)
        table.insert(Library._Conns, c)
        return c
    end

    --------------------------------------------------------
    -- АНИМАЦИИ. Тайминги сняты покадрово с твоего видео (30 fps):
    --   открытие меню   0.20s Quad Out, прозрачность + масштаб 0.97 -> 1
    --   смена вкладки   старая гаснет 0.10s, пауза ~0.05s, новая проявляется 0.12s, без сдвига
    --   подсветка пункта / hover  кроссфейд ~0.13s
    --   popup (dropdown, пикер)   ~0.12s появление, ~0.10s исчезновение
    -- Не измерено (на видео склейки): закрытие меню - сделано симметрично 0.15s;
    --   раскрытие подпунктов - 0.15s по высоте, в стиль остальных.
    --------------------------------------------------------
    local QUAD = Enum.EasingStyle.Quad
    local T_OPEN, T_CLOSE, ZOOM_FROM = 0.20, 0.15, 0.97
    local T_PAGE_OUT, T_PAGE_GAP, T_PAGE_IN = 0.10, 0.05, 0.12
    local T_NAV, T_EXPAND, T_POP_IN, T_POP_OUT = 0.13, 0.15, 0.12, 0.10

    -- твин Quad Out; onDone подключается ДО Play, поэтому срабатывает всегда
    local function Anim(inst, t, props, delay, onDone)
        local tw = TweenService:Create(inst, TweenInfo.new(t, QUAD, Enum.EasingDirection.Out, 0, false, delay or 0), props)
        if onDone then
            tw.Completed:Connect(function(state)
                if state == nil or state == Enum.PlaybackState.Completed then onDone() end
            end)
        end
        tw:Play()
        return tw
    end

    -- Плавная прозрачность целого блока. В Roblox это умеет только CanvasGroup, но он
    -- рендерит содержимое в текстуру (текст может чуть мылиться), поэтому блок кладётся
    -- в CanvasGroup только на время анимации и сразу возвращается обратно.
    -- pad - запас по краям, чтобы обводка (UIStroke) не обрезалась.
    local Fading = setmetatable({}, { __mode = "k" })
    local function Fade(obj, pad, fromT, toT, dur, delay, onDone)
        local prev = Fading[obj]
        local startT = fromT
        if prev then
            if startT == nil then startT = prev.Group.GroupTransparency end
            prev.Restore()
        end
        if startT == nil then startT = 0 end
        if not Library.Animations or Library.Unloaded or not obj.Parent then
            if onDone then Safe(onDone) end
            return nil
        end
        local parent = obj.Parent
        local A = obj.AnchorPoint or Vector2.new(0, 0)
        local saved = { AnchorPoint = A, Position = obj.Position or UDim2.new(), Size = obj.Size or UDim2.fromScale(1, 1) }
        local g = Create("CanvasGroup", {
            Name = "Fade", BackgroundTransparency = 1, BorderSizePixel = 0, GroupTransparency = startT,
            AnchorPoint = A, ZIndex = obj.ZIndex, LayoutOrder = obj.LayoutOrder,
            Position = saved.Position + UDim2.fromOffset(pad * (2 * A.X - 1), pad * (2 * A.Y - 1)),
            Size = saved.Size + UDim2.fromOffset(pad * 2, pad * 2),
            Parent = parent,
        })
        obj.AnchorPoint = Vector2.new(0, 0)
        obj.Position = UDim2.fromOffset(pad, pad)
        obj.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
        obj.Parent = g

        local C, done = { Group = g }, false
        function C.Restore()
            if done then return end
            done = true
            if Fading[obj] == C then Fading[obj] = nil end
            if not rawequal(obj.Parent, nil) then
                pcall(function()
                    obj.Parent = parent
                    obj.AnchorPoint, obj.Position, obj.Size = saved.AnchorPoint, saved.Position, saved.Size
                end)
            end
            g:Destroy()
        end
        Fading[obj] = C
        Anim(g, dur, { GroupTransparency = toT }, delay, function()
            if Fading[obj] ~= C then return end
            C.Restore()
            if onDone then Safe(onDone) end
        end)
        return C
    end
    Library._Fade = Fade

    local function Corner(p, r)
        return Create("UICorner", { CornerRadius = UDim.new(0, r or 6), Parent = p })
    end

    local function Stroke(p, key, transparency, thickness)
        local s = Create("UIStroke", {
            Thickness = thickness or 1,
            Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = p,
        })
        return Theme(s, { Color = key or "OutlineColor" })
    end

    local function Pad(p, l, r, t, b)
        return Create("UIPadding", {
            PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
            PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
            Parent = p,
        })
    end

    local function List(p, dir, pad, halign, valign)
        return Create("UIListLayout", {
            FillDirection = dir or Enum.FillDirection.Vertical,
            Padding = UDim.new(0, pad or 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
            VerticalAlignment = valign or Enum.VerticalAlignment.Top,
            Parent = p,
        })
    end

    -- ColorKey = ключ Scheme для цвета текста; false = цвет ставит владелец сам
    local function Text(props)
        local key = props.ColorKey
        props.ColorKey = nil
        props.BackgroundTransparency = 1
        props.FontFace = props.FontFace or F(W_MED)
        props.TextSize = props.TextSize or 13
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
        local t = Create("TextLabel", props)
        if key ~= false then Theme(t, { TextColor3 = key or "FontColor" }) end
        return t
    end

    local function Button(props)
        props.Text = ""
        props.AutoButtonColor = false
        props.BorderSizePixel = 0
        if props.BackgroundTransparency == nil then props.BackgroundTransparency = 1 end
        return Create("TextButton", props)
    end

    local function Round(v, decimals)
        local m = 10 ^ (decimals or 0)
        return math.floor(v * m + 0.5) / m
    end

    local function IsClick(input)
        return input.UserInputType == MB1 or input.UserInputType == TOUCH
    end

    local function V2(p) return Vector2.new(p.X, p.Y) end

    function Library:AddRefresh(fn)
        table.insert(self._Refresh, fn)
        Safe(fn)
    end

    function Library:UpdateColors()
        local themed = self._Themed
        for i = #themed, 1, -1 do
            local inst, map = themed[i][1], themed[i][2]
            if inst.Parent == nil then
                table.remove(themed, i)
            else
                for prop, key in pairs(map) do inst[prop] = Scheme[key] end
            end
        end
        for _, fn in ipairs(self._Refresh) do Safe(fn) end
    end

    --------------------------------------------------------
    -- ScreenGui + слои
    --------------------------------------------------------
    local ScreenGui = Create("ScreenGui", {
        Name = HttpService:GenerateGUID(false),
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = false, -- координаты GUI == InputObject.Position
        DisplayOrder = 10000,
    })
    pcall(function() if protectgui then protectgui(ScreenGui) end end)
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end end)
    local parented = false
    if gethui then parented = pcall(function() ScreenGui.Parent = gethui() end) end
    if not parented then parented = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
    if not parented then ScreenGui.Parent = LP:WaitForChild("PlayerGui") end
    Library.ScreenGui = ScreenGui

    local FxImage, Shadow -- ЭФФЕКТЫ: объявлены здесь, определены ниже (после загрузки иконок)
    local Acrylic          -- ЭФФЕКТЫ: блюр фона за окном, определён ниже
    local UpdateBlur = function() end

    local PopupLayer = Create("Frame", {
        Name = "Popups", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 50, Parent = ScreenGui,
    })

    local function MousePos()
        return UIS:GetMouseLocation() - GuiService:GetGuiInset()
    end

    --------------------------------------------------------
    -- общий drag (слайдеры, color picker, окно)
    --------------------------------------------------------
    local ActiveDrag = nil
    local function BeginDrag(input, move, finish)
        ActiveDrag = { Move = move, End = finish }
        move(V2(input.Position))
    end
    Connect(UIS.InputChanged, function(input)
        if ActiveDrag and (input.UserInputType == MOVE or input.UserInputType == TOUCH) then
            ActiveDrag.Move(V2(input.Position))
        end
    end)
    Connect(UIS.InputEnded, function(input)
        if ActiveDrag and IsClick(input) then
            local d = ActiveDrag
            ActiveDrag = nil
            Safe(d.End)
        end
    end)

    --------------------------------------------------------
    -- tooltip
    --------------------------------------------------------
    local Tip = Create("Frame", {
        Visible = false, Size = UDim2.fromOffset(0, 0), AutomaticSize = AXY,
        BorderSizePixel = 0, ZIndex = 60, Parent = ScreenGui,
    })
    Theme(Tip, { BackgroundColor3 = "GroupColor" })
    Corner(Tip, 6)
    Stroke(Tip)
    local TipText = Text({
        Text = "", TextSize = 12, ColorKey = "SubColor", TextWrapped = true,
        Size = UDim2.fromOffset(0, 0), AutomaticSize = AXY, Parent = Tip,
    })
    Create("UISizeConstraint", { MaxSize = Vector2.new(260, math.huge), Parent = TipText })
    Pad(Tip, 8, 8, 6, 6)
    local TipOwner, TipToken = nil, 0

    local function HideTip()
        TipOwner = nil
        TipToken += 1
        Tip.Visible = false
    end

    local function AttachTooltip(gui, text)
        if type(text) ~= "string" or text == "" then return end
        gui.MouseEnter:Connect(function()
            TipOwner = gui
            TipToken += 1
            local token = TipToken
            task.delay(0.35, function()
                if TipToken == token and TipOwner == gui and gui.Parent and not Library.Unloaded then
                    TipText.Text = text
                    Tip.Visible = true
                end
            end)
        end)
        gui.MouseLeave:Connect(function()
            if TipOwner == gui then HideTip() end
        end)
    end

    --------------------------------------------------------
    -- popup (dropdown / color picker): один открытый за раз
    --------------------------------------------------------
    local Popup = nil
    local POP_PAD = 12 -- тень popup: 16 * (10/16) = 10px + запас
    function Library:ClosePopup()
        local p = Popup
        Popup = nil
        if not p then return end
        if ActiveDrag and ActiveDrag.Popup == p then ActiveDrag = nil end
        Safe(p.Cleanup)
        p.Blocker:Destroy()
        -- АНИМАЦИЯ: popup гаснет ~0.10s, клики сквозь него уже идут (блокер убран сразу)
        local frame = p.Frame
        pcall(function() frame.Interactable = false end)
        Fade(frame, POP_PAD, nil, 1, T_POP_OUT, 0, function()
            if p.Late then Safe(p.Late) end -- AMBIENCE: вернуть «одолженную» панель настроек до удаления
            frame:Destroy()
        end)
    end

    -- alignLeft: popup выравнивается по левому краю якоря, иначе по правому
    -- bare: прозрачный контейнер без фона/рамки (ВАТЕРМАРКА: внутри две свои панели)
    local function OpenPopup(anchor, w, h, build, alignLeft, bare, placeFn)
        Library:ClosePopup()
        HideTip()
        local blocker = Button({ Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = PopupLayer })
        local frame = Button({ BackgroundTransparency = bare and 1 or Library.Transparency, Size = UDim2.fromOffset(w, h), ZIndex = 2, Parent = PopupLayer })
        if not bare then
            Theme(frame, { BackgroundColor3 = "GroupColor" })
            Corner(frame, 10)
            Stroke(frame)
            Shadow(frame, 10) -- ЭФФЕКТ: мягкая тень, как у popup на видео
        end

        local ap, as, vp = anchor.AbsolutePosition, anchor.AbsoluteSize, ScreenGui.AbsoluteSize
        local x, y
        if placeFn then
            x, y = placeFn(ap, as, vp, w, h)
        else
            x = alignLeft and ap.X or (ap.X + as.X - w)
            x = math.clamp(x, 6, math.max(6, vp.X - w - 6))
            y = ap.Y + as.Y + 6
            if y + h > vp.Y - 6 then y = math.max(6, ap.Y - h - 6) end
        end
        frame.Position = UDim2.fromOffset(x, y)

        local p = { Blocker = blocker, Frame = frame }
        Popup = p
        local function close()
            if Popup == p then Library:ClosePopup() end
        end
        blocker.MouseButton1Click:Connect(close)
        if bare then frame.MouseButton1Click:Connect(close) end -- пустое место контейнера = мимо
        p.Cleanup = build(frame, close, p)
        Fade(frame, POP_PAD, 1, 0, T_POP_IN) -- АНИМАЦИЯ: появление ~0.12s (запас под тень)
        return frame
    end

    -- список значений (dropdown / выбор конфига)
    local function OpenList(anchor, values, current, onPick, alignLeft)
        local n = #values
        local w = math.max(anchor.AbsoluteSize.X, 150)
        local h = math.clamp(n * 28 + 8, 36, 236)
        OpenPopup(anchor, w, h, function(frame, close)
            local scroll = Create("ScrollingFrame", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
                ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = frame,
            })
            Theme(scroll, { ScrollBarImageColor3 = "OutlineColor" })
            Pad(scroll, 4, 4, 4, 4)
            List(scroll, nil, 2)
            if n == 0 then
                Text({ Text = "Empty", TextSize = 12, ColorKey = "SubColor", Size = UDim2.new(1, 0, 0, 28),
                    TextXAlignment = Enum.TextXAlignment.Center, Parent = scroll })
            end
            for i, v in ipairs(values) do
                local b = Button({ Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Parent = scroll })
                Theme(b, { BackgroundColor3 = "ItemColor" })
                Corner(b, 6)
                Text({
                    Text = tostring(v), TextSize = 13, FontFace = F(W_REG), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd, ColorKey = (v == current) and "AccentColor" or "ValueColor",
                    Parent = b,
                })
                b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
                b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
                b.MouseButton1Click:Connect(function()
                    close()
                    Safe(onPick, v)
                end)
            end
        end, alignLeft)
    end

    --------------------------------------------------------
    -- notifications
    --------------------------------------------------------
    -- УВЕДОМЛЕНИЯ как карточка NL (видео 1, 0:43): тёмная скруглённая плашка с тонкой рамкой
    -- и свечением акцента (снизу ярче), слева тёмный квадрат-бейдж с инициалами, жирный
    -- заголовок, серое описание, справа сверху серый счётчик.
    -- ФИКС размеров (перемер по видео): пропорции NL ~4.6:1, бейдж ~0.56 высоты, отступ слева
    -- ~0.22 высоты, текст по центру по вертикали. В единицах меню: 260x54, бейдж 30,
    -- заголовок 13, описание 12 (было 280x64 и текст прижат к верху - выглядело высоким).
    -- Стопка справа сверху, под ватермаркой.
    local NOTE_W, NOTE_H = 260, 54
    local noteInset = 0
    pcall(function() noteInset = GuiService:GetGuiInset().Y end)
    local NotifyHolder = Create("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6 + 24 + 10 - noteInset),
        Size = UDim2.fromOffset(NOTE_W, 0), AutomaticSize = AY, BackgroundTransparency = 1, ZIndex = 70, Parent = ScreenGui,
    })
    List(NotifyHolder, nil, 8, Enum.HorizontalAlignment.Right)
    local NotifyCount = 0

    function Library:Notify(info, time)
        if self.Unloaded then return end
        if type(info) ~= "table" then info = { Title = "", Description = tostring(info), Time = time } end
        local duration = tonumber(info.Time) or tonumber(time) or 5
        NotifyCount += 1
        local title = tostring(info.Title or "")
        local desc = tostring(info.Description or info.Content or "")
        if title == "" then title, desc = desc, "" end
        local h = (#desc > 40) and (NOTE_H + 13) or NOTE_H -- длинное описание - в две строки

        -- рамка фиксированного размера (без AutomaticSize: внутри тень и свечение)
        local wrap = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), BackgroundTransparency = 1, LayoutOrder = NotifyCount, Parent = NotifyHolder })
        -- slider едет, card проявляется (Fade двигает саму карточку внутри CanvasGroup)
        local slider = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), Position = UDim2.fromOffset(24, 0), BackgroundTransparency = 1, Parent = wrap })
        local card = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), BorderSizePixel = 0,
            BackgroundTransparency = Library.Transparency, Parent = slider })
        Theme(card, { BackgroundColor3 = "GroupColor" })
        Corner(card, 16)
        local st = Stroke(card, "AccentColor")
        st.Transparency = 0.5
        Shadow(card, 16)
        local glow = FxImage(card, "glow", 16, "AccentColor")
        if glow then
            glow.ImageTransparency = 0.55
            glow.Position = glow.Position + UDim2.fromOffset(0, 2) -- снизу свечение заметнее, как на видео
        end

        local badge = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(30, 30),
            BackgroundColor3 = Color3.fromRGB(10, 16, 28), BorderSizePixel = 0, Parent = card })
        Corner(badge, 8)
        Text({ Text = tostring(Library.LogoText or "UI"), TextSize = 12, FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1), Parent = badge })
        local tx = 12 + 30 + 13
        -- текстовый блок (заголовок 16 + 2 + описание) по центру карточки
        local top = desc ~= "" and math.floor((h - (16 + 2 + (h > NOTE_H and 30 or 15))) / 2) or math.floor((h - 16) / 2)
        Text({ Text = title, TextSize = 13, FontFace = F(W_SEMI), Position = UDim2.fromOffset(tx, top), Size = UDim2.new(1, -tx - 40, 0, 16),
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
        if desc ~= "" then
            Text({ Text = desc, TextSize = 12, ColorKey = "SubColor", TextWrapped = h > NOTE_H, TextYAlignment = Enum.TextYAlignment.Top,
                TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(tx, top + 18), Size = UDim2.new(1, -tx - 12, 0, h > NOTE_H and 30 or 15), Parent = card })
        end
        -- справа сверху серый счётчик (у NL «2 of 10»): здесь оставшиеся секунды
        local counter = Text({ Text = "", TextSize = 11, ColorKey = "DimColor", TextXAlignment = Enum.TextXAlignment.Right,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, top), Size = UDim2.fromOffset(30, 16), Parent = card })

        -- появление: въезд на 24px + проявление 0.2s; уход: обратно + сжатие места в стопке
        if Library.Animations then
            Anim(slider, T_OPEN, { Position = UDim2.fromOffset(0, 0) })
            Fade(card, 18, 1, 0, T_OPEN)
        else
            slider.Position = UDim2.fromOffset(0, 0)
        end
        task.spawn(function()
            local left = math.ceil(duration)
            while left > 0 and wrap.Parent do
                counter.Text = left .. "s"
                task.wait(math.min(1, left))
                left -= 1
            end
            if not wrap.Parent then return end
            if Library.Animations then
                Anim(slider, T_CLOSE, { Position = UDim2.fromOffset(24, 0) })
                Fade(card, 18, nil, 1, T_CLOSE, 0, function()
                    card.Visible = false
                    Anim(wrap, 0.15, { Size = UDim2.fromOffset(NOTE_W, 0) }, 0, function() wrap:Destroy() end)
                end)
            else
                wrap:Destroy()
            end
        end)
    end

    --------------------------------------------------------
    -- иконки (Font Awesome Free / Material Symbols из твоей DLL, PNG 48x48, белые - красятся ImageColor3)
    -- При первом запуске пишутся в <IconFolder>/<имя>.png и грузятся через getcustomasset.
    -- Свой PNG с тем же именем в этой папке имеет приоритет (файл не перезаписывается).
    --------------------------------------------------------
    local ICON_DATA = {
        -- ЭФФЕКТЫ: 9-slice текстуры тени (r16, растушёвка 16) и свечения (r10, растушёвка 6),
        -- профили подогнаны под замеры с видео/скриншотов
        fx_shadow = "iVBORw0KGgoAAAANSUhEUgAAAEIAAABCCAYAAADjVADoAAAFJElEQVR42u2bO2/bMBDH/6SYOLb7ADIEWbp2LPodOnQo0A9boEOHfocgS9GM7VJkKNCHo9iRxA4+AocDKZESZSuFCBwkC7ZJ/nQPkkcqay3mAugZwQxiBuEr5oB1qZ6/s48dhBoAxbZ81z4WECrxc+g/bACAGgOIOQCA0BUdHbMdz7MCMSMBUC33qkMzOADr+azE8yxATEYIvk5rAcAnEkKbNAKA9Xw+OAifynMAWtzLZyrwRnmHGyGa3ftMpjcMkwGCD4CTgkSLq4QBD4Sa7vm19sCR5tMLhskEwdd5w65GPNPCbCDU33W8YtdKPKvpt+77gzTDZILgOmeYnHjEMFBFAETNpALw4JGKifv9IBgmE4RCdP4UwIKuXDgQLcyDawMHsBOypav7bcXa2BuGyQDBacApA7AAcMZkwcA4GEUARC0gbEnuSVx9W4959YZhMkA4EQCWJCt2v6TffAfwA8AtgA2AUtS1BLAGcAHgEsAL6ljJxKdR0ukmw1ARCzMchHSIJwLAimTNZAfgGsANve2UUgB4CeAVwd4wuSMpmdY8eKKLjRlwmQERwjBNcBCekDylZ1cEoekZpmsAXwB8JRivhVl1DcZUrFak+AgJgZvEigF4Rg7sA4CfmeYxDUH9BuANgOcevyDHFTZWG7oWZlTANLhvkNrwjBzax4wQePlJ/31PdT1hvmghQrSOmPAlrVApj3+QZrEmbagAfCLbHavcUR0V1blmIE47Bm3JGqFaHCXXhjPmHJcAPo8MgcP4zF7CioXp0DilVStiNcL9IY8Wp1S5a8zVSObQZiZX7CWcsXFK0TGnSfYRXWMHB8KFyEOXa6pbgpB+QnWZiE6IGqGIsRwYIodGk2vhI0KmkawRKqAV2mMaC3p+c8SV+Btqw8JjGjqgDSpH1DBCK773GDHmLDW1gWuDyRU1EFhWK4RWnNDc4djlh5jMyWl+bx+hWiKHdJq3EwBxG3CSOjadkGIaclDlrpsJgNh4lgR1jCb0iRohKOUEQJQtnVc5ksAqYsF2KkV1QFBzNjyDRli0Z6CmtN2ma/ptc2iED4Kb/y8nAGEZWI+ITgXqRNKNJ+myngCItSch1KRoro7cnCHTcDzncDEBEBcs31GLttqY/RU6weZk8sUtuV9OAMQlaw9vo431aSmmwZMvFcs7vKBBzLFKQW3YiSyYLzeaZBq2xT9wbXDJlwb7JfdjlZfUhi2DUQsTsV0RJCVqyHScA1Fiv9R+jDGJprpLAaJq2T6AoT5COskd9qvJJU2BXx0BhEv8lNSWXcBpZvMRjXCWEsQG++TL+QEhnFOdGw8I7iybHOHTtpiGS8zesca8wX5FeeyyorpKlv67Z2m/qiXlZ3NFDWce3EdsAPyh9YC3I8NYUR2G6twIH1EFBlWDfIRPK2qhFSW9kb8AfmO/mvxuJDM5p/8+o7r+ikSwzz8gZrhtEucaDducIbcM8e8+BfAew5PAMjq8pk7/IggORFvEiIoa87aAniCmsFHkjt1vPdpQ95mFqsgTPFPaOnQvAOzErrteU/EUHyE3WjSByMK3A7qxxhibyR6EFtRD1iNM4gpQKozdAbYXNkMh9Nln2QYjNDkbc8NpM3RlasjO2xAM37ykoIYfYgtybwgpznIqm9JthAb06pAaeO7zWMcU5GLy4GNOKsMB2EMfXEFgxDjsjWY8CTz2Uaauo02YypkuG9kx1fOY4ygAxtCIsY47Ao/0uGOowapnZ+z/dhLYzmfDMR+Sn0E8tvIPfID4fFPuCs0AAAAASUVORK5CYII=",
        sub_abyss = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAB8UlEQVR42u2av2sUQRTHPxcRvHBRSCEolsFGRFAU7G0tFLRREM5gLfg/CNZWYiMoFv4LklaJEX+AYBGsBDWSRPSCF7jDj4UTsFF33Le7d7APhoVldt/3s2+YefNmOyrTbDNMubUALcCEA8xU7aOKl/eAK8ASMEhtKd3rhXtTo9oJ9Y76zT/bd/WRekbtRPjtlFwHDgGXgEVgIfPZ98BD4C7wrs4I7FEvqI/VH8bYc/WaOperJ6fzvHpbHVidDZKP+eghNAs8AY7VNDu+Bk4Dw6hZqF+jeJKvfuQ0erKBNepUJEC3AYBum0q0AC1AC9ACTAzAuAFt40iALw0AbEYCbDYAsBEJsNYAwFokwEoDAM+KdCq6H9gNfK0xqRsC+4BRVARGwHKNX/9pEfG568CDGgHuF+2YU5XoAR+AuYrFbwEH0jU0Als1ReFeUfG5EQDYD6wCeysSPwAOA5+qyoU+A7cq/Po3c8T/TwR29qorwJFg8W9S8WC76mx0CJxL60Lk0LmYK75MOr0KXAUiDtjkV+X6bRPV6cvqqEQpcaz2y2iIKKufTWXzXNtWz5f1H3U2cFRdzhD/Qj0e4TvygGOXekPd+IvwdfV66sukAey0WXVRffWb8JdprHej/ZU9ofmXHUyzzMeqHHTaXw1agBZguu0nCNo978Xqrc4AAAAASUVORK5CYII=", -- Dodge: подвкладка (иконка из твоей DLL)
        sub_veil = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADMElEQVR42u2aS0hVURSG/3vNEAoqqRxIhZlEETkIGkQRUdEglIrCgYGG9hgUgYOCaGA4yHQUBREF9sQew7KSJiVNpCcRBD2ssCjJiOiJlV+DdnA4XM9j333VAy3Y3Lu55//3/vc5e6291rkpQEm2tBJuo1FAsaTXkhqSKmCzEbFLUn7SBKQkbTTfiyRVJE3AUkmlnn590gTU+PqrJM0YDgFzJG2TNN4SP0ZSpaT1Gea3X9L0IZFAtq0A6OWvtcfEzgaagbcE22/gCrAOyPdyuBCw1TdQWQRMGdCFnb0DGlwJyAOe+gY4EgG3heys15WADRnIvwFTQ3BpoAroAH7GmHgP0AgUuxJwZ4iB9sXgKDR3ZCiub8AFYAWQ8uOzmfyKgJX6AIyz4HyQgasyCJONG90d8FuhpFoLztO+fp+kq4EIy9UvBwYjPK95MXmLfHuiOQxjewf2mHNLkJVIWhuTt0/SdU//RCjCYvVLgV8RvUa3BX+VwXZFuT4OcT5QDTyK6bPPAwtijJMG6oFZrgSMB3YCr7IMPreAikyuMJsWtqEajUt0aU/MghTkSkAZcBD4Tm7tnVmgSa4EzAMuR3CPru0T0GoZ+JTylFVehiUPObajJqewrkr0j3A29sYK5bkdk03k+zjMj1AXsNrlJnblNoNsELgELMqlG00bv93tcOIDwClg7nDEAW9bbFbM1kN9Nq55mssgZpMPlJvkOs6jsjemr08BdcDMXAgQMAX4GlFAhwV/pcF2Rrne5jj9XlJbxGtbLPg3mc+Vviqd04SmJEIyftvy7g54OJpyldC8kHQx5JpWC95qX0W6zlTtlIvK3PwAr9QDjLHgvJ+Bq8L1Jva2a0MI2B6DY0JIWeW7p6ziXMCyLEoqy4GzMY/tD4EdwESXtVF/pG6KgKnNMqI/c1EXyuQqf0g6HAFzV9Jjy/G+SDrnsryeBu6ZlWmJiV0IHAL6I0T0G0CNOWw6La/LHBWWWBSy/rWxwBpzZvJbu4k7oRnZaLA2X0lyUNJMSa+S8o7spK/fGTT50SjgpqTnnv7xpL2lRNIZT530UhLf1B8zfzU4IOln6Jvx//9WGWH7A/zNh5Xt5/N9AAAAAElFTkSuQmCC", -- Dodge: подвкладка (иконка из твоей DLL)
        misc = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADZ0lEQVR42u2aSWxNURjHf69F1JBSrTliQWKOBEGkFYSYShA2hhpiSISFCBuJhRX2TSliiBUigiIxxAaJmKcgMcVYib4aW0P/Fo7kuc57797bd4++xD85m++d79zz3fMN//PdF5NENiOHLEfWG9AsAy9gClAM5AM1wHngFNDgxAJJYcdUSfdlx21J4xuxtu8RVnGlpB9Kja+SyqI2IBYiCw0HLviMn+/AUOBGVB7kNaAvMB7IS6GzEOjjkZ0DrgNDgBLPb1eAAxna7xfgJPDAFgPTJNUrONZ7jnWjosUXSRNtLnTXnEAQvAK6ezJOjpF3jDD33AYGeutAlxALvbGkywZjQJToZitkJ0Is1A/o6ZH1MvIocdQWAwWS9kuqDeiTNyUVS2ojaYykexH6f1zSbkn5jakDWwM+dFNTqwOtgWtAbx9zbwEjgM9Nicx9AkYCF9PMuwSMjXLzjeVCLSQtknQtgVb8kHRZ0lxJzVxwoViGLjStgALgnc83PgpYBgw2Vf8ZcAyoNCfs5ATCjPaSqlIE/FvDCCJno2FGB0Oz0+G7pHmuXcgP9gALfM79YIrh8yBsNAYsBkpNqswkcoExHtkTYIuhHTMsxj0EnnpkH4HDwF5bDGyQO7yV1MnjDpsD6K+zxcBLhwZUWPy5awD9F7/1crK0Q9JgU6p0uNkZQKFHtiKAfkWyIF4KTHYUxI+ArcBrYDpQZvaQLoiPmIwm2504SuwD5vmcWw8M+uPu2wQ6c2v8bMj49yqfc51TiUJJZ1NklxpJs12RuRZAkSFf8YC6o4Elxk3yTMWtMonkfdRkrljScUl1CW/ukaS15lrp9FSDTM6VVJ6mwDyV1M+lAUFcaBewyMe8GtOhe9yUqt8kn5sHaA+U/4vy3c7k6lpTJBJHlUcvDsw3mx1g+pWJmGhZIxMjbjyhrS2I9wYgU/M9vthS0gOHZHCnjcyVhuqM/UJdyM5eY7jUXy70JsACnSyyzg4NeGVzoVnmq4ofHJTUPEG3RNI3R+5TL6k0WRrtbwKwyGPxUGCcR3YHOG262jM9HwxrgO0RvPlq4DhwP9kXmmTINxvu5vNByyMyIHQdqAXmmMZVOmwDdjiLhoClu4+kM0l8s1rSatdcKCwbHQZMAHqYVuJV4FDkjVwfXyn5/1+J/wYEw0+7BuIF5Nl1HAAAAABJRU5ErkJggg==", -- вкладка Misc (иконка из твоей DLL)
        keyboard = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADi0lEQVR42u2Yv29URxDHP/PuMMgIn41oKCJCAR1CKBESQQKbFBEFFQUdAkuWqPIPBCGkpInSpLQAJQpFUlJBQUfNDwWniGwBFSmQsMGIn+befVMwC+v1/fLdk/wk3khP92535u3Mzsx3ZxYqqqiiiir6nMm6TUqyUihppnUJSKpJysqyy5JMUq0vD0jKzKzl742IZyO8oQ8OsGfBkNQb1k55Sd8C3wOHgPpGOwCYBy6b2e8hrNeEVQgZSTMqL12SlK0JpzAgadIZm/6Uid757w+xzhb9aQE3gO+A3Of+BB4CmbtyI6gBnAHGXIclYC+wvAoqJY1LWows/qNEKDSdeGEybHw9Seg4qefdM2ZmzSTcQiI1k4XqHcYHlal7NCwkoPMxB7ohzBYzyyV9Iem08y4CV4CVD2voJLDP+a+b2W1ffCcwPaTMZaDpOoy0QSbSEJqQtBSF0E8+/mOSTEd9fLuk19H4reibFwqQORLNTfnYiv8eaxdCnWiT795bYCuwOXLjO0/wlEYKlOlK/RjwxD8e3LjkXlsBXgLjPv60aJlhDQhJNQvcc95lM7vjR/qyo8Eu5/s7kp0F5oaUuSupZmY5/VScbXLgYowSbfhtPcXYIDLRATt4DphZU9KEx+8bM3sViio3btz5niYKFCHT09BuJXOw/pTj8L/AP5L2+PgocNPnFiT9EilysiCZ1jAGBHd/Bezwo3w3sNsrwa3AQWDCn28i2SJkvuynkVlP0xLQodVmjC7QWITMQCgUPnAN2O8htQjc99L7OfAr8LXzXY1kr/mODiMzFzdXA6PQOouueopa0dymdm2hy2SdWtuhUcjrkDy0d0CrU2ymBVky976bTGKEFRFCIYlb8WESeWzMi6/GgD2z/MmBv8zsUdrzRjBq/RoQ72zTw6Gm1YBcl9QEzgE/F1TyH5Z0wteKT96aL5130jPtB+IYbbh707DIo91peX0zaOPfdNnMvZx3WGs0UfxTP+CnYwa8AB4AB5zxrKR5bynjmAzt5TOXaQxx7ZL5d+9LmnLF8qTBGgMu+poZ8MpvKT4hZZTtZ5LWrRflBTTrrT753sat7qqmPkGBWWDG39/32L0iL7vyHmBjwG3guHtfq9DQq7+AMOclPS7RlcqypN8kbU+r2nZXi6Fq3Ob5UCvBxcSCmf3X6Xqx4wlYJvILZ+v7et2Zy3JDrZ41UUUVVVRRRZ8l/Q/+lIQZwCqPZAAAAABJRU5ErkJggg==", -- БИНДЫ: окно Keybinds
        kb_key = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABRklEQVR42u2ZsUoDQRRFzyyKjaTTxk8Qixh/xdJCEfwELQTRfwnkK8RSCyu/wEajncRCg3hs4hIkK5gEnNF3YVh2Hgvvwtw9zExSKVkVhSsMhIEwEAbyMdAGekAfMNNxD3SB9bprFXVHHVqOXtRtlaS2gStgsbDV8wp0KuCwwOYBloCjpD4Aq4VmuJ/UdyB9KdwCZ8Bg9N4CToG1TOp1hGkIyd4o3ONjP6N6rSYODCbMPWVU//skXp4w18qoXmuhwcDx6Pk89vFJRvVaycL3lMVnoGkJlcIBggPBgeBAcCA4kAUHZlUWHJh1/DoHZlVwYFYOzCMHU3HACZv6n/6n59H8NBwwqY/ASqnHKhVwUXAEzpPaAS6/YUKuGgJbFXANHABvhTW/C9yMg2JT7an9jE+l79SuuvHZd4p74jAQBsJAGPjXBj4A3eATXHZQ15YAAAAASUVORK5CYII=", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_shield = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADEklEQVR42tWaTUgVURTHf++lWUQ7I31pEARCQVhiWAlBRAQRURBRhLSxFrlrEbqwoFWb2oRQtNEkok3Rx6KFtqmMLEhdaIWLMiuEPl+aPs1/i64yvd7HvJk7zzd/mMXcgXPOf+acc885dyKSCACbgSZgLxAH7gNtwIB1TZJsXYslHZT0SOnxXFKDpCJbem0IKZN0WtKI3OODpLOSViwkgRpJHZIS8o5JSTclbckXgRLjJj2yjzn3Ks7FpojLII4Bx4GTQCnB4hPQDlwC3vsN4nrziaeVf0wZ3TtzdaESSSckDahw8EzSUUmLshGokzSkwsULSevTxUAt0AUsp7AxBmwHhoB5AhHgJbCBcOAxUA8QNQu7QmQ8wDbjMfMEqgNQ0m7SbwVwIwD51U4CRQHk8kbgIzAKHDO+axOlTgJxy8JfA9OO+6m5oLOIH04CPy0Ln3W55gdfg/wC+cA/X2A0hARGnASGQmb8LPDGSeAL8DlEBN4CE04CAK9CRGDeY5wEBkJEoD8VgYchItCdjoBCYHzCFHP/ERiz6EZRl2te8AQYTye025KStUn1VTFQZUl2V6a3cseSkpiZxJUB5cBVYKUl2bedN8lTiajJsRUF6v99yaV/NMUO11nAAdyRvJBqLrQaGA6gR/CLCaDSVA0ZM8M7C7GQAJqBVcYdzwAzPmVeSzY+02Brk6RZH+OP5hQyW30OudbkOhu95UNheQp5MR/y2tLZmWlzaTGuYAsRH43LuVx2zDkMAhc9Kj2SYq3Bo6xWMxzAy3B3maRhj3P/U8aVYiYmpjzI6c12muNmvF5riqfiPKfNcaAmW5/ipsDqNWkw32hy1WS5PAmJSOrM4xT6gu0TGoAlphLcGvCbvwvsB357rdvTYRLYAzwN0PgHwCG3xntpMr4Bu4GeAIy/B+wDfvntnLLhO7DD1Ca2cAU4wN8ZKvk6qY9IapE04/OcuHGhT+rrJA16ML5P0sZC+NUASUslnTdvNBviZmcuKpR/JZxXpaTLadwqYZ6V29SZyz6QC6qAw8A6kxL7geum37aKP/dZNh7ffIQuAAAAAElFTkSuQmCC", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_run = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADhklEQVR42s2ZTYiWVRTHf+/MNDZOklFEJQhqJVRCLqaoLCycFoG0iqRFDAhuhJIKJ5iEIuhrWS2aTRCFgbVyEYohfrSJiCJCcREMyjCavVKOZFM6vzZ3QF6e5z5fd5znwMPLe++55/7/z733POeci0pLngH1FfVX9S/1Z3WX2h8b1xbwN6gHzZb9MRJ9tENeA57O6dsKvJQ3sKO2gcAp4N5I/wng/jYTuAzcWNC/PKujLVtouqD/dF5HWwjsLej/vO1nYAg4Coxk9H0HbAHm2rwCl4HNwAdAN7SdA94HRvPAA7W+A4Pqu+q09eRf9aS6Rx3OmWOoLJ46BN4xnRytAjbVh2ws4dZ5AtjVxEAbzsDY9SawNzGBNUCn7uCBGmMmwu8LwJ0JCMwAXs8VmAvB113hzfU+/cDXFex9UeOlPwjcXteNpvRS36srKti+Sf0xjP1H3ZYa/FgF8PvVlRXt7+ixcSalF9oMTJbQuwLsBp4F/qw4x6re/wOJwK8FvgIGS0Sd20J8U0d6CVxMsQK3AgeA2wr0DgIbG4DvAJt62qaaEugH9gH3RHSuAnuAZ4DzDeZ6Hljf03a86aGdKDioM+qTCZzDY+pshv2RJkaXq90I+MPqHQ2BrwyR738Z9r9pWlaJucwPi+o5Jfz9hHohx35XXd2UwJEc40fUTk2bQ+qr6u+RlzOrPtq0sLVWnc+ZYLRmkrSzRJJ0Qn0gRWXuzZwJTqt9FcuJ29WpAuDnw8oMpsjIOupvORO9XdJGn/qceqoA+EX1PfXmlCnlUzmTzat3lyC/Vf2pAPilAPyWxciJP4vkt7FxW9QfCoDPqZNV3G8d9zabM/lYzphNEY91baViUl1V9YVWJbA9suS9cf0j6rcFwK+q+0psvWQEjuUA+fQanQ0BVEzmg876pmFGFeU1Ed//uHpfADVfAP6QujFVElVFeWfE1X0ZtkNMDqgjqVPYKgnNspz2FSFJyZNjwBvA8UWpKlVguy4k0lUS9tHFvl+rktD8ARwuofdLyHcfBg4tel2vpO8fj4S2C3JSfbFhGJ30EC8A7xYAnwrljoGluKLNahxWX1bPFgA/E/SWLeUdcxbwmRKh7XjTun5KAv3hiv9cAfCu+nrkVmXJCHxSIiZ/KxaTL+XTUS8BwxkO6m/g456Lt9ZJH3A2o3z+EbAOGG8z+IXvwEPhqzkdttPqNm6VvOd/RktiG9BFXEEAAAAASUVORK5CYII=", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_target = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADrUlEQVR42u2az2tUVxTHPy9mglCr8UcLSdAi1h//gJiJCF0UFdpVIbNIXNSF2o2KbropGlwrutMuBZFguunSmIWWJrioVUpRE3Gh+QH2F7Eoitp83ZzA8Dh35s28+9ShHriLuffcc8959/y+k0iilaGNFoeWF6C9QNolYDcg4DLwspUE6ACuAmX7PQF8VoQQRanQzirmAfpsrmVsoNuZ63nXVSgBNtuXrzjrFeAFcB2YNNvID5LyjhWS9kv6XdlhStK3ktbkPT/P5nZJhyU9VvPwxARpf9MCbJR0S/HgpqQNzfCSNJFKlIEfgY8i2+M/wFfAtYYMr0EBdgCjwNLA+gNgBFgGfJNaOwc8MWNeF9j/HPgcGC/CiDdK+iugAtOSBqp0ud/B6a+ynQHb48EfjahTIwYb0vmLkj5M4XdKmkkJuCKFs1zScIDmDUlLYgpwJHDQKUlJYE+XpOM2ugI4iaTTAdqHYgmwStK/gS+fRIgjSeAmHttN5hbgqEN81lGJPGN5wCYO5RUgkTTpEB6IyPziGHTOuV3vluu50S3AHcdVfgq8KiAvu++42E3AvWaz0bIzN5KR+T5gyEY5A/4r4Adnfnuj2ehiJdUVyCqX2fwoMB+gewL4zjJUgGM2NxTA77R64QNnbY8VSHNuZZfSqQ5JExnzlxlJ3Y5e9klacPAXJPU6+D3mFLLAuKRS9f62OpVULegB9gWqsSRQL+x25vcFCqCQWu58m12J+E2o1HWW7JqywHQgwpYDKvSfpG0Ofncq7agFP6dVyPOtJUlfWpU15hA5K6lSJ5ANpYRYkHSsTlVXkXTOOe+K8fJFmvksgWyvQ/BkxsDUa4IcD3x5b5xyzvs6TyDbDNx9Q4GsZIFsbcxANuUI8EkgPuSFisP87VrMZy1ovFR6LkumGCGZOxgjG10Z6DwMR0ynLzn052Ol01j7xIPTNYToNiMeCkTsRebPBGgfjF1S3gwcNGwqkL612VTa0em4zksBmr/ELimxQvvPGnnRYFVRX6lR1JcMNxS8HklaX1RfaDswVqOt8rCqrXIgtfY98BTod7zNIjyztspEUX0hgF5rbH0c2Y3+bY2tn4pur1+3jPXXiMzfALY2ynze7nSb5SjzOXqi8+bhlryN7nR1ENov6bcGGJ+0rvTqvOc3YwO1YJMVHYNmjNUwBlwwA733rj7yTdnocAQYAc63yhvZnDM320qPfJdTvnzcuhjRIbYNpPP7XVYHjxb10F2kAO//K/G/EOA1dIriMf3neY8AAAAASUVORK5CYII=", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_eye = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADsUlEQVR42u2ZS2hcVRjHfzMZplRjOzUmKsWCC219RETciZQEFYSKKMZuShFdlGipj4UtFKyCGlxUEEHFjVaQSsUXLlrdtOjahdpafFSppmpiq0K19pH05+ZUhuudmXPunUQL84dZHOZ8j/+93z3ne1RUzmZUOcvRI9AjUBK1LurqA64GrgJWABcAiwCBo8AvwH5gL/AFcPr/QKAGrAJWAzcDA5Fy08AuYDvwYSkyapHfuepG9ZDl8a26Xl1QxJdUgYp6nzpl93FQHZtLAsvU3c493lOHuk1glXrE+cMh9cZuEdigzjj/OKGuKUtgc6LRn9Tn1TvUy9Ul6vnqihDfL6rTCfpOq+uKEngkwdC0Oq7WI97oAvWBBCKz6tpUAuOBfQzeVwcLHIEXqrsibcy0OqHyFI8mxPxLal/BuwS1pm6LtPWXem0nAherP0cqfEutdnBwRP1T3ac+q17WgsTOSJtfq4tbEaiqeyIVTaqNiCc8mhMKE8Hp5n2DCZfjm60IjCd8tGsjQ+SiNm8vG3rrEuzfmSUwpP6acOXXShJQ3ZLZWw/HcAy+V/vVf+qBCWBJZP63A5iJ3Dva5r9NwLKm9cmgOwaXAJvPZKOXqqcSXt+tkU+/rn7WQddjGZnbEvw4qg5UgUcT64LPI/bUgVeA4Q77RjLrTxP86AcerKiTwNIEwYXA8ab1dcAJ4EAIw5EQHsMRun7M2F4IHEvwZX8tlIJl8DFwTtF6qmxFWAU+SBTKlo0HSzjwQ2Y9mCj/bhV4GphNEBrOeQNFsbuD7nY4BmytAl8BrycIrsysXy3o/AzwcsKxm8ULwFTzhfN75PF1ICcH2l6gYHkqJyeaTEhlzsumEusTjK/OGF+sfpIg/07ObX5PgvxYXi7Up36U0ArpzzjQUHd0kDulPpPjfCPh6b/dLp1emlApbQttlqyOG8J/34V9J9W9IZ1enrO/GjLM2AfX6FTQ3BLKuBhMtCCR0md6LtLWcfX62JLy4YR4fC0nnGJ+ixI+/tlWHYp2BrYktgfviqjQzoTM3U0hFoP7i7ZVtiYejV+qj6sr1YEmPUOhOntS/SZR56YyfaGK+kSJ5tRsQncjrxOxoVutxTXqH/PYlTsS2pldbe5ekXhZFcWe0Eiek/Z6n/qQ+tscOD6l3pt6LBc9vxvh25i2O53ojWFokuxLpeSguw7cDowBNyU0Bg6H0dIbwM6EJsG/UJZAdsh3DXAlsDxnyHc4DPn2hUFfV4Z83STQmxP3CPQI/Af4G6RZJc4X9HPQAAAAAElFTkSuQmCC", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_bolt = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACr0lEQVR42s2ZPWgUURDHf7e3IEkUCysVIyhWkhSxExTUYGG0EMFGUZCgEL+wshRBsLKJ0dgERCUigqTwC0UU0wWLEBsFP1AThMBZKBqN8cYir9K93PuYfbt/2Ob23ey8nZ3fzsxWRISCtAQ4A+wGZoDL5nCTiBRxrBSRcflfp1xtVQqIQAdwD1iVce4NsM7FWBLZ+W3AaAPnAVJXgzE3cAC4DyxdYM3DsubASRGpS3N1uNpOc77rKTAAHLFY+wR46XOBvLQYuAXssFx/0ecieVFoOXAX6LJc/wFYC/wpQwTWm2Rtd/jPgI/zeURgK3CnCWn+1Q+z2ZrPBRNlTD5wdB7ghq/zmhi1xWSWOkOunUbEZJaeAhOhDsTCpBo6NZLYFZNZ+gis8aVPSAR8MJmlS6HO+0TAB5NZmjEVaS10A0kETOqj0wOjIZhUR6cLRkMxmaVnoei0zYE287xvV66VfpocsNEUcA24ANRdH6EhKY/OuTb1VeA7sIhy6DOwwoVCVXOURRVXjM4CIyXawG0fjLaJyBURqRX8/D8WkZZYg60XwAZFe1eBw8DvGA3NZkXnBTgLHFrIee2e+LiSnVmgF7gesyduB94q3JBvwF6XCZ1WBPoUbE0BO4Hx2FOJFuATsCzAxgTQA0wWMZXYH+j8I2CTj/NaGzgW8N8hc+e/xmhosrQF6AzAZC8wV9RUwhedvwzfh/PuB5pptUGnS9H3hfmPes9RnN/76qij8+/NDOmVapnqGYFWM9expc8YsAuY1i5Tk4BBrq3zIybZ1Z0P2UCf5bp+YA/zI/R85DHK6Lao4edE5ESMD4ipZ/LS5IPFvlgdnWsSV81bs7XB+WmTrGOxek3XCNQbzmfgtcHku5jNcuJRAgxm/D4KbIztvO97IAFOAwfNuOMmcN6UCNH1F23BBHYNUwWzAAAAAElFTkSuQmCC", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_cross = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEHklEQVR42tWaXYhVVRTHf3McNTLUkSYUQgmsHiyocfpQwUqpIKFmetHEFy0qozR8CirQF3uJKHrtyQdJI8Qe+rBm/IDsA5uHSoKehnCmcqorZjlazq+XPXIZ7t7nnHvv3Ln9YXNhn732WevuvdZZ+79Xh0oTsABYBawE7gSWAQuBLmACOBfaMPANMAR8AVxo9MUdDRgwD+gDNgIPAXNLyo8DHwEHgcPAxbq0UMu2eepO9Webh7PqbnV+WX3KDO5Qt6ljTh/G1K3TYcAS9bCtw8fqjUV0K+IDa4FDwCJaizHgUeDL1KAsZ5KNwJGCyv8KHAC2J8Y8B7wXlMtDNzAAPFavE29RJ3KWeiIs9wY1q5KNYfL5LLVPHSiwnf5VHy/rA+vUSzkTf632ROTzDKhuq9Vvc971dxhXyICb1XOJyS6FMJolVq+MAaiz1VfVKzkRammeAZl6IjHJH+oDBaJDWQMmW5/6V0J+IITzqAEvJoR/V1cUDLv1GoC6KseIZ2IGXK/+GREaV9eW+MCM1pjjTAn5/sR2qqgLJsdWh9FdwHWRYPUCcKJEDN9fo29fCflDwO7Is4XAzqlhdJF6PmLx4NR9V6DNVV8PKzGi7lXnlJxjtvpdwhfnV2+h7ZGBl9Vb6kj4mtVWJ3xhW/UW2hRZroPAj8wcTgJHE1kCqIsTDnPPDP771Q5dC/+o3RmwJpITnQa+YubxAfBbjf5OYE0G9EYEB2gPXAGORZ6tzICeyMOjtA8GI/29qKdLHjaG1ZdycqGybY76Wgi5ZfB97KtZBDuaaMDeOnUY6VAvAtfUsaxDgUZpBkaBJXXIjWf8v2EGVOoU3t9EReqdq9IZGLMyy/cT8A7wZhMNeDn8bi6pSwX1SMRB+trgKzzZno3RL1lwxlq4v432+rpI/6kskK1lhFqNLPFnDmUh46vFbt2eSDNaiQ2BI5qKCeBkBowEI2rh+TYwYEek/xjwS1aV99fCJuCmGVS+F1ifOKtcPZHdkGACPmwwtzmj7lE7S84xSz0V0em82jWVlXgjkXM80YTcZk/JOXYl9Nlbi1ZZHCi8GLV3d4O0ykgJ+fsS1OYFtTtGbL2SyvzUZS0gtlYE7ieGXSlmrjOQtjGMqr3TaMCanBugz4NvJMnd28IymVjCzU02oCOkCylG/Jy6vCi9/kg49acwqN7aBAOWq5/lvOuy+mDZO7KnC5yIxtV96l11GLBafTcol3eJsqXeS76tBV5w9XyqvhWy2Bj61bfVHwrOOZ4Xwotc8q0H3g+38a1EBegHjjdyyTfJD90BfNpC5T8J7zzezJv6DvWpab7oPqs+WYYNb6TUYLQdSg0aKfa4tqrY4+E6ij0uhmKPA4H/HG91tcrUcpt7A03ZAywNpTZd4bBUCW04HGGHwg18w+U2/wGtezQY/9boowAAAABJRU5ErkJggg==", -- БИНДЫ: иконка индикатора (из NL dll)
        kb_list = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAB+0lEQVR42u2asUscQRjFf3Mcp40SSwWRgL2F/4KlRRBsLKKgNoZ0WoiNp3hCYnOp0iQQCxvRQKzF3kIQLGwsInfX2KiNjfhsVliWu1nZXW9ncT4YFubbGfbdfO97b+/OSKLIUaLg4QHkHWXAAFPAaJv8JfAPcJcokn7IHt8l4epA0l0MgFvLBhVJ25Ka6m40JFUllY1e10dNh/kasJpjAW2kBdACBnME0Cp6F1JaAHs5A9hF0n0KEvdI2pHU6jKJm5JqkipI+hlzc931NlqSNC3pKvLgV5KmJBmXAZSAJ2AfuI7U1zVw6LQKezPnAXgAlBOsccp+JwFQB75a8jvAigslNABMtBmzMXsuWnIVYBtoBqeUdDSAKlAOi8JJhlLfSXhqGVuKardJPJfxfgvv3k7nbb93bV3oHFhuM38I9FnW3Vlya8F1JuWbXAv4A6zbSHzSgYhO2e8kOrAEHANjER15BM6Av64r8Yv93vdeyAPwALyd9nbahL4aPQImQ7kbYB54iKw5APpjlPiDxU5Xgc/AUIrnbgK/gM2wqm0U0U6HT2AkqOHeLE7W8skNZVhBjXAX+g98CZT2zUo26/2ibfR3wIOLothpY/l94yMwHBAvKxL3AFtvZadfO+oxxPrWTTttEvzVwACfgPE2dvo0aMfKQwe8F/IA3iOAZ2whPi1cIvd7AAAAAElFTkSuQmCC", -- БИНДЫ: иконка окна Hotkeys (из NL dll)
        kb_ind = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACzElEQVR4Xu2ZSasTQRSFvzjPs4I4oLhyoaKgO3+9e0VduBLFYeGsz3mMfI9b8NJdlfRL+nUn0AdCmiade84dKpVTo/F4zCpj2yqTFysvYMecFRjB+qtN2Mub7uemAhJhP78T2AXr121V8B/wB/gF/I7rRoKaCJCkpA8AR4DjwGFgX9xftBISlfQ34BPwDvgIfIn7iitiloDtwF7gFHABuAScB06GIIW1JUDCb4BnwGPgKfAa+A78LSmYJkDyZv0scBW4AVwGzgCHgD3RQm0IMMs/gDXgJfAIuAs8AF5ENbIiSgIkZebPATeB28C1IH8wWsfWWpR8gm2kCFvpdLxsVZNkDKvxNTfkJQEOqW1yJcjfCjH2/ay2mxdWPC0QJm93fJGVkbzifla/PEfGzNo6F4HrkXkr4b22Vp1Zc2ksY0r4LfAq2ksRE0OdI6SoozGwqef3d0Q+QV7GdN7k4OIhp1rCcwIs47FYbRxge97ydg1jGlsOrnxyktsEqgIcGD/kOu8M+F57qEPkuEwsHCUBDqt96CB10fclGFsOcsn+cObIeS9tGdpcKueB2U47gezWpZTdRLytdX4RpH1Ylmuf7dEKBgF9Y6hA3xgq0DeGCvSNoQJ9Y6hA3xgq0DdKFfCffyNvsgMkHlmLMScgGa3Jwti0Y9wiNhpemr81EVUBG41WvUp9mazyjmBsOchF89ekTiS0JECXWKPVdx/qC8aucpkqQPjQ+3CJNVY/T3OHtxCaucaWg461nGrJzM2AvfYhLG5dYt1ivckuW8lYxkxOtXa7nOQ2gZw36sP23BPgHnAivBm9yq00dxMkab8/B+4HB7nIqZbEktPsUY8z8DAsbuEw6VVutb1u25h5yd8JDnKRUw0lAQ6KJyNmwWstbo9++jrgkEt2OR/NOOhe+iOmWQLEUh/yNREglvaYtamAKlbuoLuKZdnoDf8Hesd/3wLRYjB5HpYAAAAASUVORK5CYII=", -- [v32] плашка индикатора: скругление 9
        kb_soft = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACNElEQVR4Xu2ZQUvcQBiGn61aFbGHop70ICJ4q9dK/3+vehNEPOhBVDwoora0K4/MlI2ZTVZoMgbmhbCEJZvnnfebZPm+0Xg8Zsj6NGR4NXgD8+9IYASvRx+yrmeq7TYDApvSAvA5fM51aEToP8Bv4Ff4/NtkpsmA4EKvAmvAOvAFWOyw9IR9Bu6Aa+AGuA9m/K6maQaEXwI2gF1gD9gGvgLLHSfwCNwCZ8AxcAJcAU9QN5EyYNm48sLvAwfAN2AzpGE5dbUXLCHLx1W/ALaAFeAQuAzpVPZGyoCrb9m48t+BH8BOKJ8u4aOiCctWDs8fwqE598g/pQwI6cWWjSsvvKXTtuH/p3xQxPu5H0zDw2QqBt6+B2L5uGGteSN04/qDfct7em8ZZJHJ0q6Ub+pFZgJe6KobYR9lk5Kg3lsGWWTyvKJUAjr3UelTKBd8VDQhi0y1d1Aqgfjy8ruunjbvUSPP4P8LFQO5VRLIrZJAbpUEcqskkFslgdwqCeRWSSC3SgK5VRLIrVQCtvLsBDe2tXtUI89bA7E/b4vbbrC9yJkGDR0p9kllkcm2YoUnlYDQ9iNtcduLzGVislMti0yyNHbmvMjJiMMF+/Pn4cJKQ7UneU+hZZBFJtla2+u6dDLicMGZgD1JFXuTXXfr4soLfwocBRaZagmkWuZuXkvHyYjDBYE9zzHgEP5nYJGhNmYaTRl0D2bENM2AGsSQr8mA+vBj1jYDkxrkoHtSM0/P+1T5M5dbL2Z+n6gAUAR5AAAAAElFTkSuQmCC", -- БИНДЫ: нарисованная подложка (PNG, 9-slice)
        kb_pill = "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAYAAABOzvzpAAADoUlEQVR4Xu2aWavUQBCFv3FfcAU3VBBRUB8EQZ/05/umIPqggiKCiiuuuC8jn3TBTNLJZO69ZDozHgg60cytc+pUdXfljsbjMauMTatMXqy8AFs2wAGj9B3xZ1+I2l1XDa9FAIl66R6f3wZsBTan+31A0r+Bn8AP4BfwB/7dn0uQeQWQtIR3AnuBfcB+YA+wPYnQByT/HfgEvAc+AB+Br0kQxeiErgKYcf/vbuAQcAI4CRwHjiQhdvQswLdE/CXwDHgCPAVeA5+TK2a6oYsAkje7B4BTwIV0nQaOpvu7Uhn01Qckpv2/AO+AF8Aj4G66Hqf7uqRVhNGMfYCEzOxh4DxwGbgEnE33dIQl0Wf9B6IP2APM+CvgAXALuAncS/d0SqMIbQ6IzGvxi8A14ApwBjiYXGFP6CvrOSi8DdieZB/SpcZmfzIxd5I7Gp3QJoD/5heeS+Svpszb+PyhiyQ+CeNQCEXQqZar5IXukPybVDI1NAlgZrW3Na/tzby2t+P7TCnkq0KYGGM0Vsm7MrhCuDr499rq0CSACtrtbXjWvLaPzJcME6MIxmrMb4HnyQH2Aq8p5LbC3tNOLnUKoJrWlV88FBirMRu7HOQipxrfJgFsIq7zLnVRVyXavgnRwI1dDnKRUycBLAstpGqu8/YCm8zQYMzGLge5yKlW8lVFVM76t5GonqtAdNQhwtjlIBc5+XnKybkSsH5cU1XMHd4Qsx8wdjnIRU61PpZzgA+5lroDLHXJ64o4w8glDmszHRAbC4VYhoGJHOSS3a4vA8F1ISdAHDI8c3c+VxcMOcjFq3YoqgoQ5N0/u2ty0jLzTF0wjF0OcpFTTYScAzxnO2lxD+1524eGCmOXg1zkJLfWrbCKeYhwzOT52mGDn4cKY5eDXOTk5ylH5xygZVTM8ZKTFocNQ3SBMRu7HOQiJ7m1OkDYNDw6OmNzzKR6M0dLhcEsG7Oxy0Eu2eNwzgEK4PlZ1ZyxOWbyWFmrn4JhrMZs7HKQi5w6zwOsFaerPnxsYgRW8kBERNfX7g/TfFAOcsn2sqaBiEpZP05XHTDGjM3zdWkjsUBMiiVv5m+k2OUgl+yepm0maMOwg96vzNhKGopG1iVnzWt7My/56yl2OdSaX6BNgGgkvni4PTFj84cMaSze2sDbBAh13UUpgjWkvZyxOWZaiRcjgaV9NTbrzVBu37BUL0fnFUAs1evxtQhQxcr9gkQVG/KbGovC/4nQopQvBX8BhwQXffvwN4wAAAAASUVORK5CYII=", -- БИНДЫ: нарисованная подложка (PNG, 9-slice)
        kb_bar = "iVBORw0KGgoAAAANSUhEUgAAAA4AAAAjCAYAAACkejs5AAAB7UlEQVR4XpWV2UoEQQxF77jvy5MP+iD6/x/jNwgqggju+8gJuUW6uhUNFFVTk9O5SaeqZ/P5XJ3N+o20gePSBATogQEYanAFcV4ow5Fx/ioj4B5czD3mlVTzmtBHjW6Qp+NsgMhHCZ4naMkxVxDnZUnrCZzmfJ2z5RJkADraRjqe5HyW87sUchkjqeQFiJLjBHbS+VmKfKNoOLj0johU4MMEdyU9ZbHwCX/nSH5V6r6kg6ziXs6owQffSalrUjgDY8wvXcSRVKq6KkVeDGxb0k1WfCTVXYN04M3ME9vKaPyHzFYczKA7hwK5c5AO1KL1OWIuElFduFqU1vxRobR6Kuq+5dUTM3CoVs/e6MBWqVht4k8pBuZTQa+OzqMhA2/uSSl6lH2DzK0ABtnEiZ4ExlgT9ceIhohAQ9MtGGvAGjUiWjcgDoA0NQDG2kcqZNbz6HsFEImPkh7SibVzbnL9kg3yZJyA7hJkTZ78NwmSAxHJ7V7SbYKsXSB82i1XK8pTcWKPE4ERERU1YrtzcORp/ElEZl9S5Oj/BhHdNeg3iF2V4rgRfiwOOfoCvizvkUYfNEFfVYNIv0iQ/DgZfwJxdETk86ABOCufufoZYM3d41518VpxetBXyNRnzoWJ91jB+J1R/vV99Gux/XoLfAOAO9WD3Qcp4gAAAABJRU5ErkJggg==", -- БИНДЫ: нарисованная подложка (PNG, 9-slice)
        esp_arrow = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACQUlEQVR42u2ZT0ojQRSHX3eCWcowQ1y51QMoWYe5wBxhxCu4cxM9iQS8gms37lw6iB5AEZmtEtHuz4WvoCi6TXX1n1SgHzRJINR7v+9Xr7q6WqSPPuIOIOkpfBNJy/QHIpKKyIeISJIkNJ0jbbFwEZE/InKqhafrNO9T/bwC3oAfQLIW/WDoA1Mg5ytmjjNrQf9Si8+A/8DP6F1w6Jvi3/X7SfQuFND/0GmUR+9CCX0sIXG7UELfhO3CODoXltA3YXrhSP87XBf6WKJy4BYYAWkULnjSd3vhbzS94EnfdeEuChcq0o/PhYr043IhkH48LgTSL3Jho/P7AjDQpL8D6LsuHHTugjV9LgLo4+yTrm1HO5k6Sn8XeLW2CSGR6TXtzAWL/rwGfXcaXXbigkN/YTVjnTD9074LDdPv1oWW6Nd2oYraRI9HjkVkJCI0eK5kzotmzu+V088q3COCXEhboo+exqV6ZSKS+7qgfcAq6OfWkxfAA/DPadjMw4V9zTnoauVxC38CZsAv3XYcAjceQszYZ40sqR70iwo/AbYKxtrwEGLu6m+aM6m1rH5Df2nhwNDsMG2SJULeLTAmx7yWCyX0syqFuy86HCEjFXLvCDF5FrVcKKC/CCncQ8imjvVkjb+o5YJFfwd4aaJwDyFbBUJetIZqLlj0z3Wgx6YKLxEyLBDyqLnPK7lgPSpOgGddDsdNF+4hZKy5n4GJ90bPWjn2gO22C/cQsg3sBb/x7KrwZUJCl9GVv5iLpY4++og1PgEsW/4ydivLBwAAAABJRU5ErkJggg==", -- ESP: стрелка к игроку за экраном
        skin = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACn0lEQVR42u2YO2gUQRzGf5e7oKIxkKDxQcQkgomipRZCQiyEFHpIwE5E0MrWQmzsrFIJFoKVlQ98oAhiNGgpWKngNT5jogaFGI3RbMxnM4fHuMftzm729mA/GI7/7fxnvo+d+T82J4lGRhMNDlcB54Cf5ne5z/MW4CwwBUwCp6vMWwFcAH4AI05MJLkMT//wVFKn+T8v6YikSf2P15KGJeXM3G7jW4bnwiXneAdsJw94CawF1tXwHQemgT6gYD3LhSUSl4C4kMsucSYgE5AJyAQ0pIAuE8PDjK56CvAsu9lhjeYaay6pgM+W3eGwxgbL/pSkgPeW3e+wxoBlv0tSwKhlHw15jJYZn0rcT1LATcveApwK4X8G2GwVh9eT7AeQdMuq9/9IOhHA76SkRcv3qiuPKAJ6Jc36NC53Je2R1FQxNy9pQNKoz/wZST2uPFz7gTIOAZer1PFfgbcVeaLNZ84icBC47cwgwhsoj+OS5hUec5IOR90/DgFI6pdUCkH+uaTdcewdlwAkFSQdk/RY0oIPaU/SmGn683HtG/UOVEMb0FvR4H80Tf907E109mWuzihE8F0NDAF7TWG2EWgN6PsNmAA+AA+Be+brXCJhdLukG5J+KT7MSboiaetSRqFWSRerRJi4MC/pvKSVcUehbuAOsC2ho/0MKFZk8khRaCcwBrQnfD+nTM9QiiKgHXgC9NQpyLwBdgFfXMJoDrhWR/LlIvCSax4YBgZTEOqHgP1hj1DBXKS+lOSrErADWAj6BvaliDymrhoMc4SKKawaimGO0ITPd5t6YxzYFETAKuB7Smu3NXZI9TtC61NcfHYGuQMdKRbQEkTAbIoFzAQR8AJ4lULyJcOtpgDPZL5HwHwKiP8GHgAH/BJZ1hPXG38BakdgfUn5o94AAAAASUVORK5CYII=", -- SKINCHANGER: иконка вкладки (из твоей DLL)
        -- ВАТЕРМАРКА: иконки из твоей DLL (Font Awesome), те же, что в списке Items у NL
        wm_user = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACZ0lEQVR42u2ZzUtVURTFf/dZlFRUmhpIPYIGEQ1saB9EzQoto4icBM2CBkENIouGbyw07x8ogujjH5AQikSLqIlGBH2oFSmiUM/VwNPM9L5z9zn3PnoL7vBw1rp7n73X2SeRRD2jRJ3DWsBW4BLwEPgIzLvvA/AAuAhsMt1RksW3TtJtSTNaHdOSrkpqstjbgnxZ0phqx5Cktqz7JxkPcRl4BnR6rn8HHAam8zgD64HHGcgD7AHuZ+GRRcAtYJ/BMTwCXPZd7JtC24D3wEajWvIF2AUsxIpAvyF5gO1AT8wUOh6gJ52IKWB/AAFdsQQkQFsAAR317oWSWAIEfAsgYDJmBEYDCBiLKeBpAAFPYjaydmAC2GBE/qtrZPOxIjAJDBr+/YoP+SwR+GvmXgJ7M5IfAo4C1dhldAHodeH3xThw1pe8RR+YAA4Cbz3WPgcO+ZZP6ytls6SKpNkUN7EfkgYkrbXYOzEeq7QC55zZ63KWQ8AUMOIuQPeAGbP23ZgLNQT85wLWZFxfBk4CB5wVaAGaVlnz27nZcdfEHgGfY5bRkqQLkkZkg6qkYUlnJCWhJ3PHJI0qHIYldYcScMX9rdD4Jem6pYCSpLuKjztpUiqNgIryw82sAvolLeYooCqpz9cLbXGlriXnUj8F7P6Xf1qpkd0oAHmcIbxWq5lrZemJqLkgDXcO2Al8TxuB3gKRxw0PzteSQn0FtD09aVOoBPzEdnxugVlgs7sgrRiBHQUkD0vPs51pUqi9wO65I42AhDq6vywn4I1rHkXDJ+B1GgFzwGngFbBYAOJV4AVwarlHwMZUIm/8AUAVPNnXfgN5AAAAAElFTkSuQmCC",
        wm_preset = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACGUlEQVR42u3Zz4tNcRjH8dcdo5GiMRlk0GgWCClSYsfKwsRGSspG8QeIjY1s2E0kO1Fq2LKgoSwUKYvRlB+zMKvJwgzF1Ex+PDZHTTlz7517jzn35Hzquzqdc57393nO9/t5vqcSEYqsNgVXCVAClAAlQL5qz2gStmIDVmEKYxjGzD8niIhGx8aIuB4R45GuqYi4ExG7mnhHzdHITe0RcTkiZqI+/YqImxGxvBUAOiNiKBrTSESsyxqgMg8vtAj3cbCJin2Dfficxyp0qcngYQuuoRdXMZp86JN4ilNYPJ8H1puBXrxFR0YTN40lc1wbxuFkJcssA2czDF6V4GEHHqMrK4A2HFng/akvKdlMSmg7Xuewyc6gG1+bzcD6nFxCB/ZmUUKrc7Q6a5rxQhUcwpkcASYa/QZ6cAsHcgz+Z5KBT/Mtoc14kXPwf3b+J7iAFfVmoAsvk2WslfQFp3G3VgautGDw0IlBnK+WgT68L0CX1p+Yyr8ycLIgLeaN2VZkdsD7C9IGr8WJNIBNBerl+9MAlhUIYGcawESBAFamAYwVCGAyDeBRgQBG0wAGE/9RBD1IA3iXGLhW1zfcnstKnMOHFge4iI/V7PQ2DNXTTOSgeziGqGanR7Abz1so8MAAjs8OvtbhbiUijkbEs4j4Efnoe0Q8jIg9zR4tdiel1YOlCzDj0xjHKzWOISvlf+ISoAQoAUqA/xrgN5SL4Bt+F0GVAAAAAElFTkSuQmCC",
        wm_mem = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACXklEQVR42u2YMWsVQRSFvw1RNCCYRASVgIUgErWyUKxstFC7aCFiIwgiKPg6ifgfUlhoFxCJeUUKlaggiiAqCjaiplAIRkSjiSR5L0R9x2YXJsPs7MBT2A1zYVl25szMPTtzZu7cRBJVtg4qbpFAJBAJRAKRQFvW6SjbCJwCdgFrS+JnE3gNDAPfl9VIMp+jkn6qvPZD0iHT58QIJXYDz4E1JV81DWAP8NbWwGAFnAfoAi5nH+YMTAO9FdHut1Sry2agO7DxJHAaOAKMenBPgQHgGPDSg7sBHAbOAJ8Dfeh1ifhugIiWJG23hH/HgfsoqcvArJM06cCNWX31S/od4Ec9a2POwABwr4D5O+C9VVZ34O6nYstsDhh34Mas7zeZOD02ApxwHWQN4KQ1sG3zbZTNOcoWAnGZfU2X71LeSTwNPC6xeMdt0q5QYrHEBBaLYqFOYG+JCewvIjAIbPJ0sKqNstVt4DLrB87lxUJXAraveUnrra3vqgP3QlJiYDokvXLghqy+eiQtFPjQknQxa2M2bgYGVA8k7ZDULemCZ98ekrRZ0hZJ1zznytn0p+yU9CjQh4YrmKtagiiJN7JI4B9fKT9UkUASk7slWkK3Kub7cXsJxXMgauA/EagBG4AnHswf4ACwDfjiwU0BW4GDQMuDewj0AJcKvTOCudmcwKkvra95gqtPRj/1kMu4pCkPrpZi+nLqZ1yX+pt5HANEbtb5/mwrEFc05rBrGz2fZgX2WReNZvqe8OSBzITrM49jZt1tTyJtwhjbHPNXupSvx5M4EogEIoFIIBJYEQT+AokO2gcMxJE6AAAAAElFTkSuQmCC",
        wm_fps = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABw0lEQVR42u2aTStEURjHf1eSt1iQEnkL2ViThN2Ur2AxOxtlN5aUpQ+gZKP5AOzYkSLWKFkNyUpqTN5i9Ldwp8ZwzblcOcP516259z7/c86ve+c5597nepIoZZVR4nIAv63yH2q3CegFKv39B+AEuIy8J0lRbrWSkpKe9V5ZScuSqqPsM2qADRXXWpR9ehGm0RFg2zB2CNiz7U88GCJ22MYsVB0itsb2LPQVxYAJoDnv2COwCywCaZsBFoBEwLlxYBIYA05tnMhinww+p3ZgxdaZeMIwbtQHsQ6gNUSslQDed7KmW406AAfwhx9oGoApYACoyDt+ASSBTZsBeoAtoCXgfByYB+ZsvYWSnww+p1l/fWIdQFeItX3cRoAwU3ubjQBlpZTF3DzgAByAA3AADsABOAAH8FZ3Ify3Efjuv+gLBDgCbgwb3Mn7vR9iIPk+00LHNXCIYY1sxqBUlJJUX+BbN/CtFngaJJ0b+KbD1Mg8SQlJmYDGtiR1BBT5VvyCXqGeJC1JqvrA1y1pJ6CvdNDgTWpkVUA/UOfvZ4EUcFbkcjcCfbwtsx4DV0V8nby+wM29bMgAB77/Q3ly30o4gP8N8AKLRbiv9XEt1AAAAABJRU5ErkJggg==",
        wm_time = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAD40lEQVR42u2aS2hVVxSG/3M1RjSxAxUnIr5SmqKgThz46Miioo0mYFMEIQ5qB0FwoiCS4gNCBoKIdGJLoCCCiCi2VRHxgeBENGBuQuKLim2ND0RvHvX5OdnK5Wbvc/a955wbAi44XNh37bXXf/Zaa6+19gkAjWbKaJTT2JTkBpJ2SfpJ0lRJ/ZL6JPVKykq6LOmqpIHYKwFpPJuJpkHgKPAtEJS6VloATlEc3QC+K2WttHxgUpH8CyWdkvSXpFmj2YlXSeqQ1Jg0gCWStkpaGkO5nKQXnrt3VNLPSThxABwosNd9HrZ50WLnF4ExwGKgBfjHwzcOxHXiVovQt8C0EgHk84wz0ep+BIiWUgFsDBG6oIQodNLBWw38FgGioVgAXwI5h7A7QEUEgB8t85oi5jQCrx1rPgdm+gIIgAsOQS+BRR4+kAF2A/8aW9/peVitA1451v7TF8AGh4C35tRUyk9jiCmtjQIQALcck/eUQfmPz68OHa4X7mThxNWOid0mahTyLwCuAV3G6ZMCMBG469BlRRiAY45J6xwLdeTxvAeay5AQHnEBqAL+t0zoCnHA/wp4kwRRAfxt0WcAmGBL5pZJqrQc1u2SXGXbzoL/AkkHJTUnkBe9kXTYMj7BpDbDcqHlDkEnQhZpNzlSWiDOOMa/seVCpy3b9cBzu5uN+SRtThmgL+xUz2fu8T08ygzivMMvh/nAFMtW3Stiuw+FmNPmGGb0yDI21eYDVY4cXgmAaDO/SQGoTrMis4EYEzMaeVVkuQRq23wQWyQNmdZJc0gojqIvwiwjvy/0TNLkAsaZMd7cYUm/S3of9RYjyFbkP7XtQK+FcX5Mc3oVU3mXDj02AFkL4wxJs0ewS1EjabplPGsDcMUhpH4EATQ4xi99CnF53elqSU8s+VCXpHkxnDBO4zkr6auC8SFzZg3aotAfFkFfS6obgbe/3qK8TAdv0NUXWuvIwXuAyjJWZOOB2w5dVoYVNBkg65jYWkYAbQ4dbkaVlAJ+cEx+ZyuqU3jqLEmhszJ0tVUuOQQMAEtTVH6ZWcNGZ4tpbNWGCBpIaSfqQtZ8AcwptrXYFNKfeWd8ojIhh20LMRuA70tt7u6P6Fn2AvXG+UupthpCos1H2hunOx0A7R5t8G5gOzDXQ/EaYIeZE0W/RLUkA4974kDSfknbPA+gh5I6TTWXyzvlZ5sTfbqnnH2SWiIzgCK2fBPQT/r00oTyVG4pa0NCbBJ0zhVtkrxmDUwHuTNBxTuA9eW+J84Aa4Djjpak70X3yjgX3T5O7ENVpjW53GSvNZKm5XU6cpIeWz41GIz9TcPnr1VGmD4APfWjChGP+PMAAAAASUVORK5CYII=",
        wm_speed = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAD9klEQVR42u2aXWiXVRzHP//UUobg5tycqwslvfHCaL7ExFgUiJXYShECt4sVrCmIIINuRIkgSZFdGL5QyoouyjKWuywiDJyuohxSF0NXvg1pM23McP99vegMnp7Oc/ac8zz/ltAP/hf/8/zO7+U55/f+FCRxP8MD3OcwPUc69cAKoA5YDFQAcwABN4Eh4GfgW+AccAYoZmVcyHiF6oEm4CWg0nPvIHAC6ATOBksgKeS3WtLnyg9OS3o6RBbfDeWSDqt08JGkylIpsEHSoEoP1ySty1uBHZKKnoLcMKd1VNJvnnvHJL2WlwL7At7iRUnVERq1kn4NoLMnqwLtgdfA9va2BtLa6pLRFcg2AW8FOrerKdfSQAfwvG8krgWOAIWE5+eBTx1CPWtZWx+owDTgPaDKJw50O460PYJXlhAPipJ2SaqRtEDSm5LGM3qnE2ltYL2DyI+SCjH8+QHCjUlqMcb9iqTRlPueSaPAOQeBTxJOzNdNvhPbfyDlvq8nM+K1wHLHfVwBzIytLTOJW1ooAvsteVEaWAM86TLiLZMQeAQ4DsyNCP+hp1F2Af0Wj5cWmpOMeJakWymPshhwbSZgdewaNHjuH5L0oO0KNQCzPQqhigCX2AN8E1vb4UmjPHqNogqs/BcKqPjdX+wKUg5YaVOgrsTCXwJOWt5+SFlbZ1PgUQfjNqDRVE9kSAnGIv8r/mGQf5Wf7xpe24DLCbSW2Iz4akJKXB0zur0BhntT0uwYndcteG/EcGqN0cbhii2Q2aLhIUvQWhCgwN4YjRkJ6XWNhd9RC95ommw0r1bMXeBgbO1l4OEM11E2YYYtiI2WbkOrJ7OPgV9ia9sTcF+N/Z9vZIjDsM0GLiQcf7+kVkkvSDrmkbjdNnnVY7Er8ZRjz7gpQzdIapM0kIDXZ7OBrpyK8uuSmiQ9lJD45dGOOWmzge9y8PWXgVXG3f5peT7TNMOyQq/NBnpzINwMDDie3wFa8lQg2losM2ltWSDR74HHU+L2AUsD+dwCqs3L+NsJjACnMryV0x64X2Xg89mE8Daf/kEGwiMeuH9k4NPpCkrdwA+BhBd64C4K5NEDfDFZV2JjoGsbtuQ7tt8cSb8H8nguTVFfkPRlIIOOFAocCqTd7dNaXGgiaQjsljTNQnNGYCY7UUbW2mR1TWiaTAFfCLirPxlj64sU/82OmsMF48BmM83xntDs1tTDzizd6YKkg1Mo/Nt5DTi2Bww4ssC4Of1cR0wvmhKz1DBo+rMlGfJVSeos8ZBvXimnlP+5MWvWQfcTkUF3lefea8Y1vm8m91MyqY9OUepNZ7vO9G3KzU+mhh028WHiU4Me4+On9FOD/79WyQr3ANlY6sZyoggyAAAAAElFTkSuQmCC",
        wm_ping = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABW0lEQVR42u3ZwSpFURTG8d8VF2GgzEQZSFLSnSkxMTUxMRBvYHQLD2EkeQN5AyMTkVI3iYkXMKYwMdkmV47b3Ua4Z2evOp326ju1/mev8512qxJCkHJ0STwyQAb47wDdJa6tD+uYwR2O8NYqqpTURodwgdlC7hqLeE2hhXZaiocatlP5BhYi+cVUAAa/aa1soxkgA3QQYByHOMMBRlP6E4/jBsMFS1zDHB5S2IHdQvEfMdLMJ9FCc5F8LRWAaiTfm10oA2SAzgIs4wrPuMRSSkfKGk7Q01zP47R5b6SwA/VC8cWXspVKC01G8tOpAHR12hyyC2WAXwSoYqqNyyQBUMcT7vH4l7b4EwCr2EN/cz2AfaykArAR0W6mAjAW0U5kF/ojgJeI9rmM2nYA55GHz0qpDSG0XkMhhJvwNRohhIEyamMTml6f451bHGsz3imDtpIn9RkgA2SAjsY7Go3kID0w780AAAAASUVORK5CYII=",
        wm_var = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABQ0lEQVR42u3ZvS6FQRDG8d+iENWJ7hwqKr174A403IREpdRL3IFGpZBIFFwDWo2PhPiohIZorEYh8vrYc7xeJ+ZJttvJzH93Z2czm3LO+lkD+lwBEAABEADNaqhw/iBmMVZgc4FdPNdCkHP+7kg55+3cnTYL/BSNVFCJJ3Hcw1pN4KzJHGj16Gs0krgGgGmkijEd12gABEAABEBfPuZaryU/VcydqjmWNjpfPd1wgvsqgDmsY7iBhVzB8gcL914PmMfW+yO02lDw7YLgYQRrVTmQCh1nXP4AQKcL36kKYAlPBcGv4KaBHXvEYlUObGDnkyR+qytc1xjkAo5KkxjucPgHbscjHEQhC4AACIAA+HOtxV60HzvwiwB3PdrfNg1wiu0ubTcV9FBTjd+sg5jBeIHNOfYUtOJT/BMHQAAEQAD8a4AXDZbTf/xmKtcAAAAASUVORK5CYII=",
        wm_server = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADx0lEQVR42u2aW4hVVRjHfzNzTEJzhHSmq5jTDS2aMiKiy1tYBkJF9CKIRGE+RFA+dIXqNSjDblbWYNANa5phzKd6iwSFVCKikcrEappKzXQGx18va+CwW2vP7HP2HhuYPxw4a53v+9b61l7fdZ8WlemMVqY5qlKgBXgSOAj8DGyoTAO1is9a/4vVVaxV1RNYFZm7azpdoXmRufYZI54iBeYnnsC88Fu53qKkOHAe8ACwEugG2hJ0Y8BuoA94Hfj1dHuhC9V31VGL44T6ltrZzB4aZWxRH1aP2jz+UO+bSgVmq1stH5vVWUX3U9QGzgS2A7dU5FQ+DfHiZBVG3Aq8D9ydQ3MM6AUGgK+BoZBWdABXByO/IxxECq8AD1ZhxI/lPP6T6gvqwknI6VRfVMdy5K0t2wYuUY8nFjuk3tCALd2sDuUYdmeZCvQnFjqoLmnCDV6Wo8SbZSlwuXoqssCoem2EfpZ6j/qhulvdpb6nrlJbI/Q3hSsYixMdZSjwUuKEnovQXql+m3O3d6ldEb7nE/SPl6HAj4k72p6hW64em4S//129OMN7diIoftWsAl2JTbyWoZubUDSFvWpbRsaWhHebn7fHWqYMvD/46nE/vSDhfQcy43uBRQUC1hXA7SGpG0cfsCZD1wbsAI6E8d/Ax0BPLA48VeAEF2VOYnsDqcPbGRmLC/BuiJWU6wqc4G+Z8ZIG0oYszy8FeB8qu6BpK6GYKrKXUzGmNwoIWJgZDzagwP7MuKMA76vjX+qN+GngELAiY8TdEQHdwIG68Tbg1oIKbIvIjGFnxoh7gXcmm8yl3OimiBv9qYAR7lNrGRmbG3GjjQayIXVOhu66nISvHn+ql2Z429W/IrQ7y2hs9UfmFtR7grpHfWPkbtdjH3A98F1m/pFE36i/jIJmGbA3BLp6nACWA99k5meHoudO4KIw9z3wAfBJpNq6BvgSOCMzPwosDnbZdEGzI3EdBtVzmuxqHEjI7imzHliqjiQW2q8ua2DzV+UY/mH1/LK7Es/mGObxkPrOmYScueoTId9PYX0VbZWaOjCBhxlSN6or1HNDxllTL1BXqi+rwxPI6Al9p0raKmcBXwTDqwKfA7cBI1U1d4+GnlBfBZv/KKTyI0xBb7RNfSbHsIvgH/XRItemjN5ovXf6LFH0T4QxtTdRI1fWWkxhKbA+dN0mqsx+CC3ETZGI/L94ydel7omc+J4me0hT9pJvEBiOzA9PkCfNvCMrE0cic4enkwK9CT9fOmoVKbAlvPhbFwrwjcDWSv7TMPNvldOMfwGO6pw2zNboOAAAAABJRU5ErkJggg==",
        wm_items = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACIElEQVR42u3Zu2sUURTH8c/6iBtXsfOBBhFhwYiVaCGKBrRUTGsjInY+IOLrPxBTqJ2VoP+ALwRBBaONhZ0YNFgoosFgoRBfUVyL3Ei4zrhEZmdnyRxY2HNn7sz53rnn3N+dqTQaDZ1sc3S4lQAlwGwHmBf53biI7dGxn7iHAXwvMsARHEo5t46XOJ9wrA8bMbfF8X7FHYykAaxrcoENCW1ncSrHQf+G/gAy4xyoRP4KnMh51lQxmFUSL2tTIViZFcAwXrUB4FYawOcmHccjfwJ78Cj8b7V9whUc/TOnIzG3LZTLrpTk6cPjIpXRSoIaXYutWBAF/7BN02XGAKWUKAFms5ibsh7Mn+b/wJtOAOgJZbSecO4z7MJokQEOpwQP68MCciZqr+EkNv/jiWZl47iGq2kAS5tcYHmCuLuOnTkO+t4Qx7kskriec/BTdqzTq9CvrABGMNQGgEtpOfChScf3kd/A7rCp2ZRTEt8IijRRC63G/SDoYnse5vvboou5ClZ1ykJWqtESoFSjf9uasDeuRlvKIbwuOsCWUEarCed+MfnO9EmRp9C+lOBhIfYntPfigcmXvo0W/z7iMhanPYFaE+BFkd+FmykLXytsCQ4EmINZJHFvjsFPt/6sqtBYGI28bfR/AeJg3+FCzsFP4HRaDgw36fw0oW0At0MFq7U4+LFwrxdpWqg7jOiOhE9Md3G8aJ+YSjFXApQAJUB77TfX04lqU4ba1AAAAABJRU5ErkJggg==",
        wm_color = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADX0lEQVR42u2aW4hOURTH/98Yl5EoQ0ZqapAHDzKaF148TGomQwlhcinSIOWSB08eJKM8UF5MkmkiigcyuYWQPGhcRkl5EElRGMm4fWN+Xo76OvbeZ+9vzplLzar1MGevvfb/f2btvdZZ+8sBGspSoiEuwwQGWkotzyslNUr6JKlN0q/BSiBn2MRVkjokTYz+fiipTlJXgN+pkmZI+irpuaQ/mTEA4trM//IIKDfYxrUauAP0Fsz9COwFRnjMD1bTw32Y5QkwyeFsMdCNXdqBMf1BoBx4bQHRCUw2zGkAfpIsV9MmYRuoBF5ZQLwAphbY1gM/8JfrQFnWBARUAW8sIJ4DFQlv/h7QlfV/IsnAReIV8Msy1gLkgHnApyxJ+Bi5wskkJ4CSgvlzo5Mok3DyNfQlEQefOYkQ4yrgvQP8qShsbPMzCaeQWqhGUrljfL6kCsf4Y0m1UXkSlzpJlySVpZGJTboCyHuE0AtgSoKvVMPJx2i5J/jCZFfeXyR8wP+2LHTRccR2AOMSfKeyJ1yDyxzgzwKlwHQHiUMeAFwkzvSFwFJHkjodqyxtJNo9w8BForYYAg0O8G2WstiUsZsCNqONxKlQAtXAdwv41oSaflpE8D6wIyEnmHShYc0HIQRKohPEJCctGTZNPWBY91YIgfrA8iBNPWhZe38IgWOWkyCXMfjDFvDdUVg65xd2JWYYEnVeUnOGTYWZkpYbnvdK2iTpXUhbxdRi2TAAnZJeSZslnQvtC70dBG2ef2++tZjO3M1BAH6jAXyZpPE+1eho4C0DIz3AesMmHQe8jAq/Sp9EtiTWlOov8Ossp8yRArvzvqXE7n4Gv9ZRcvfE7Bf5FnO7BvjNC7hhmPMyCnWvcnpnhuHUAzQ61q5zzN0T8kHTlAEJV9j803uO+R8Kv9h8Uv32FEnkgdUJ69V4+GkKbatsS4FEHljlsdZRD1/3i+kLbekDiTyw0nOd2x7+uovpCx2XtFVS6L1sXtIaSec97b+E2IRe8rVIaorSfgj4CwFrXPGwuRza2Irr6oTbGKLWen0RvkdFV1quU2haMXsgrrOi9kr8cuNb9Ala2Qffk4FrBvBPgdmFtrkUfmowVtIcSRMkfZb0LMVr2WpJCySNlNQp6W48fNMgMHxTP0xgKMtfgTtqenaDJ2cAAAAASUVORK5CYII=",
        wm_check = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAABoUlEQVR42u2Zu0oDQRSGvw2xEC8kWgg2goWClSC2For4Ej6GdQp9GStr4wURiYUksdLSwkKwECs74beJsMruZLKbnZnAHNhmZtj5vtnbObOJJCY5akx4RIEoEAWiQBSIAqHGNNACzoAjYCpzlKQQj6akrv7GadbYJMBcqAFcANsZfSvAa7qhHhh8E7gEtnL66yE/A8Pgz4GXUAUaQNsA/wgchvoWMt3zv/D7wEeIAqXgfQuUhvcpMBZ4XwJjgzcJ2H3Gi70qrwzwPWDPFj4vlUgktf99xq8lzVSQHqSjOxgz0nmzGtdzJriTNFcQviHpwQDfl7RY5NxZjRuGiW4lzYaw8iaBmqR7w4SjXIlK4fMEkLQk6ckwcUfSvK/bxkbARsK0ek7ghwnYSiz4grcRsJHopSScwtsK2Ej0Ja26hh+1pFwGboC1nP5vQ4XXG6QHnz53Jd6AHeDZttxL5TYHVcAXSebegV2DRKnEzNW+kK1E5fBl0ulhEk7gy9YDeRLO4IGxbGw1gWNgE+gAJ8CXq+ooiX8po0AUiAJRIApEAY/xA9E/a7VPsZGNAAAAAElFTkSuQmCC",
        fx_glow = "iVBORw0KGgoAAAANSUhEUgAAACIAAAAiCAYAAAA6RwvCAAAB5UlEQVR42tWYPW/CQAyGnwsUUUDQpVURC2Lowh/g/0/9Aywdqi6Iqiyh6icfSZc3kpUm4evSBktWBjj7ke3z+c7FcUwVJKAiUj9yndvxe1wmiDNRdOabBojMd2+o+p4AieMLoGG0ZtIbAVtgZXRtwOJTQBKABtACusCVtAM0BYMgvoA3IJS+Ah+CiopgXMGucXJyKcd9aQjMgAWwTK3pAdfAQGvm0hD4FGx8CEgC0QZugBGwAe6B9z1rqg1MFPVH4EVrM2GyQJJ0tIBb4A54AqZH7rAxMAQegGel6lea6jnRaCi0oxMhMGtHqqEN8J0GCQqi0deiqYd+NZWtvmz/2vpZnfVCu6OvmvAl97LZlY/CFh+YtIQHFOY+8i6bV/IR5IG4VH3MSjhSZgbE2fTkRaSjPuFbFrJdGBHbP5oZzcqHLE033lmsgWnbZUgty29l5pEskOQULUu2ZkTIBYnNKdorAaIn29tdnTXSkf2mU9S3XMv2Kh2VIBWNWH8KdZT7loFsr9LDUl5Ekg7Y9gjRNh27MCKJrDVZzTVP+JKJbL7Kx85ijTQzzDUmjD1AjGVrnjePBDlXgSQ9jxpqxidCDGXL1sf5jIqVGp4rdZ340wuWO+A1oNQrpzvyWeJfL+EnOTqb95EfuMzHHUV2Bd0AAAAASUVORK5CYII=",
        -- [v94] текстуры эффектов ESP (Moving texture) и лепесток сакуры - из SkeetUI
        fx_galaxy = "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",
        fx_grid = "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",
        fx_stripes = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAB2ElEQVR42u3csU0AQAwEweWqov+Irp4eIEDI4wZOWufz8d776uf32e/P/h/uT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Hey/x7+5P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9PfD6A+PEBxI8PIH58APHjA4gfH0D8+ADixwcQPz6A+PEBxI8PIH58APHjA4gfH0D8+ADixwcQnw8gfnwA8eMDiB8fQPz4AOLHBxA/PoD48QHEjw8gfnwA8eMDiB8fQPz4AOLHBxA/PoD48QE8Pz6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT5AfADx4wOIHx9A/PgA4scHED8+gPjxAcSPDyB+fADx4wOIHx9A/PgA4scHED8+gPjxAcSPDyB+fADx4wOIHx9A/PgA4v+3/W8k0Q8rRLkkbAAAAABJRU5ErkJggg==",
        fx_matrix = "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",
        fx_petal = "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",
        camera = "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",
        config = "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",
        killer = "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",
        players = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAErUlEQVR42u1YT0gjVxh/b5KsJmY0tRr/VN0S3SWWanNoKgahe6g9KBEvHkSiCQErgshSxC6UPWzpob0V9raC4EkixmAgBkToRtrsQVARRMpqJLbENVgNZphk/rzXS59kbRYnkzFJYX8QJsnMvO/7ve977/2+D4D3+J8DQnj93Wg0UqOjo63Ly8szx8fHv6VSqQTLsheRSGRzaWnp2+Hh4fvV1dUw27tFdZ6maTgxMfFJLBbbxbcgGo2+Ghsba9VqtcUlQVEUAACAlpYWtc/ne4IxxqIo8gghMZvjCCFRFEWe/F5YWPimtraWKiqJxsZGVSgUeo4xxul0+gpLAEJIJM/6/f6nBoMBFiV1NBoNWFlZ+Q5jjHmeZ3GO4DiOwRjjubm5MRLNgsLpdLZhjLEgCGksE4S43W6vK0gaESNarRYcHR29zMd5AlEU+e3t7cWCLly73V73rsUqB4IgpLu6uvRyFjQlJwJ2u/1rhSNL9fX1We+cAEFnZ+cjCCGFMUYKRVZtsVhsBYuA0WhsUzo96+rqTLLIl5AkgQUjEI/HD5UmcHZ2dnznBDDGAAAA9vb2XmKMEYRQkQhijNHu7u7vmTbudBsdHBxswApCFEXeZrPRd66LyOA6nQ5EIpFNpQ6ynZ0dT8EXncvlepCvlCDvFkxK3BRzq6ur3+cr5ubn591Fk9PNzc2qcDj8Ihc5nflsMBj8MbNCK0pBYzKZNIFA4FlmQZNNJ5GChtxbXFycrq+vL25BQwxXVlbC6elpy/n5+evbZj8Wi+2Oj4+3V1RUlFZd/K8coJxOZ5vX652NRCKbDMPEk8nkm8PDw189Hs/jkZGRj2tqaigli3qoFImbB1BmlYUx/s/9bO8UlQCZTeJUNoczr9lIFZQARVHXsywIgqwx1Go1wBgDhJBsMlCO4yqVCvA8/9Z/VVVVsKysTNJ4qVQKX15evuWxRqMBgiDkTATmOmNktmmahlar1WA2mz8ym83mpqamVr1e/4EU4XZ1dfX3ycnJ64ODgz/29/f/2traSrAsCwAAQKVSAVEUld9t7t27BwAAQK/XQ7fb/dDr9c5K2TZvw+np6Z7H43nscDhMxAa5KrZNqtVqAAAAvb29H66trf1w81TlOI7heZ7N5cNxHEPkBNFFPp/vSU9PTyVJqby3WQjh9UKdnJz8lPQ+EUIix3FMZqswHzWaSSQajb5yuVwPyNqSTSJza5yZmfkilUoliHBTsqWSKTWIKGQYJj41NfXZTT9kna5ut/shx3EMQkhUQv9LldjpdPrK4XCYZJ3YJG1sNhvNsuwFCTUuEIitRCLxp9Vqrbh5skuCwWCA6+vrP+VbtOQbCb/f/5SmaZhzCg0NDTXJLVaUArE9MDBQn1MaabVaEA6HX7xL2xcKxH4oFHpeXl4unYDFYtGSAXCRQXzo6Ogol9wXstvtnyOEBFAiQAgJ/f39FskEuru7eymKUivVuFKi+Wuz2b6STMBsNn9ZQj1TCgAA2tvbH0lWowzDxHU6XQ0oISSTyTc0TddLioCSvX+leqcURakkp9DGxsYvpUKCNJGDweDPOTWsAoHAs0yVWCywLHvh9XpnGxoaKPAeJYh/AIMCouBCLR7LAAAAAElFTkSuQmCC",
        save = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFjUlEQVR42u1ZX0hbVxj/zrn3plkUK842FdvasKajYIelY+tARGn3YKdPc9Nbpa0UygaF0vkQCqUPAzukD3to0YcxfNDBZvakxT/4tIexPaQ1UBbZkKyK2mi8GVYTc/+cc/Ywj6TXJN7oTeOgHwQ0f+75fuf7vt/3D+CN7CPBGANCCDo6OjyTk5M9sVgsTCklLA/CnxuPx6NTU1M/3rlz56MjR45gAABBEHJXHiEEJSUlaGRk5F48Ho/qur6RL+XNQFRVXdvY2PgnFAo9vnTp0iEAAEmScgcxMjJyjxVYFhYWnsqyXAUAcODAAevKX758+UQikVAKpTillHCLz8/PB9rb208AADidzqx6i/yPa9eufeFwOIrTfYlSahiGkWSMUZtjThRF0YkQwggh/B8OalRWVp7r6en5GSH02eDg4N9OpxOSyWT2hymKMkMI0c03YxiG+jpuP50lFhcXpzo7O73ZLIFSbpkghHDqh4QQTRAERzAY/Km/v/+b6enpeUIIRQghxhjbza3z3xYVFTlqa2vP3bhxo7e0tLSKUmpgjLc8gjFGEUL4xYsXQZ/P9+nAwEA4qyXS3TyllDx58uSHCxculOWDtouKiqCrq+v9SCTyjFJKUj0g9f+FhYWnPCYcDoc1AKqqrjHG2K1bt2r4dyRJAlEUbXlxmnS5XFvsp2la3OxaqSCuXLnyTsY8YQaQTCZXGWPs4sWLZQAAoijabgHu1729vW2pZ2YCEYlEnvE8sUUEOx1CKWUIobxlf4QQZIsnhBDGGIuEEM3tdlc/ePDg+4qKCmwZwGbQ5Q2A1WdjjEVKqXH69OlPrl69+oFlACyf2udmKYwxFnVdT7S1tX1lGcB+E4fDUez1ehtysUC+bzZnK7tcrnLLADDGKJ8AGGOAMcY5/oZuq4XS+RwAgMfjOQQAMcMwIMdzdrz5ZDIJoijC4cOHj/JAtRoPljPxxMTE/TNnzjjzcfuiKIIsy1XhcPgXxhhLV4tlkm21UDo/5LXQ5ORkz8OHD78NhUIxwzDYpt/uxeehuLhYqK+vP+Xz+b47duzYh+ZayAq97wiAl9K5PHiXcUDTuoUdAPgBlFIjH9zOX7upai0D2I/CAfzvElnGltJun051ub24yo6WsNOFuOKCIKTtOgghGsZYtAOI7S7EmUQQBMfQ0NDtlpaWozU1Na6zZ8+6Wltbjw8PD9/lwPJBCGBHUz47O/tbY2PjobKyMmTm/vLyctza2np8eXl52o5BgG0AePacm5v7va6u7qBZcXMz1Nzc7I5EIs9yzbx5AcBHIOvr60vd3d0f8/mquWZCCL3yfl9fn6xpWjx1hFIQAHxmFAqFHnu9XokDyFb7AADU1dUdfP78+a97sYItDQ0vaxVFmZ2ZmdElSQJKMw/vCCGAMYZgMPhyZWUlbEdA28JCuq6rm3W9pRH+2toa03U9act40qY27y2MMRBCwMKUA0pKSpAkSc6CA+AJye12e6urq52EkKzLCUEQgFIK58+ff9vtdr+bsTl5XXmAs0gikVAePXr0OVdSEIRX6BMhBIIgbLnY4ODgl3yBUlAWSmWRlZWVv1paWo6a/d0cF9evXz8Vi8XC+yIPmDPx0tLSH52dnV6PxyOmWgBjDCdPnpRu3rz53urq6rydmTjreH23XdXExMT9sbEx/9zc3PLmYKCiqampvaGh4fZuOzDzWRhjwdKCI1d30nV9I9PnPPvu9YxoNPrnNhYKBAJDe10h8ZURIUTTNG1dVdWXqqq+1DRtnRCiSZLksoN1AoHA0LY3ZVmuKuSSL5e9spksYD+tWXcC4ff7u7IuuoeHh+++zkW3FaV1Xd+Ix+NRv9/f5XK5IOO+gnO2LMtV4+Pj3YqizBQSBKWUKIoyMzo6+jV3GzvHm2/EDvkXTEn7rbON78sAAAAASUVORK5CYII=",
        search = "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",
        sub_bot = "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",
        sub_killer = "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",
        sub_spectator = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADiUlEQVR42u1YTUzaYBj+aoG5lACtLtkaM5wlsWSAu9DG2xLZdVECJ5IevZqdtzCPW6YhymGLZsli4g7epJxUli1RCnSwi+E0WUSryTLKYVkWBOkuahgr2vLrkj7n7/373p/v+V4ANGjQoEGDhv8YUDuUDA4O9o2Pj9+iKMpB0/QjHMdJFEXvoihqBQCAYrG4XywW84IgZFOpVCyZTO5yHPe9UChIPYschmHg8XiwtbW1JycnJ78klahUKqXNzc2Xfr9/yGAwdDFlEAT8fv9QLpf7JLUJBwcHqenpaXtfX19nnXe73QjP8ytSh8Dz/ApFUUhHbn1mZuZBqVT6KXUY5XL59+zs7MO2ZcNoNELRaPS51GWwLBs0Go2tDRmLxQJxHLes1Gi1Wj1lWTbIMAxBEIQeQRCAIAggCELPMAzBsmywWq2eKtUXj8eXLBZLc0EMDAxAmUzmvVJj2Ww2StO08Sq9NE0bs9lsVKnedDq9imGYuiB0Oh2IxWJzSo3EYrE5s9ms2IjZbIbU6tfpdMoDWFhY8Kq5eTnnx8bGbgYCgeFAIDDscrn65YJQk4lQKDSpyHmfzzekpubry8Zut99IJBJv689yHLdMkqShvpzU9ITX68WvTO3R0dEXpQojkcizeudFUcw1Oi+KYq4+iEgk8kypPUEQMiaTqXGphsNhv5pRxzAMUSsvd/Nyk6VWhmEYQo3NcDjsl3XearXqKpVKSY0ym82mP5d3uVz9SuWcTudFT9hsNr1aDmW1Wi86+uK583g8IzAMq2JVx8fH5ZoA7iiVczqdt+V0KCSRhomJiZF/AmgVkiRJzZyFIKgtlL6rJeRwONpWQm1tYiW0Y2dn500rTby4uOhrmAWTyQQJgpBpdoySJGm4bIwWCoWvo6OjTY/Rw8PDz5eOUQAA8Hq9eCsPGUmShng8viR38/XOq33IpqamcEX9EAqFJlulEg6Ho/+cStTWfLNUYn5+/rEqMre1tfXqupC5jY2NFzAMq5tKGIZB6XR6tdd0muf5FRRFoaY/NHL13K0Pzfb29ms1mW34pWRZNtjtL+X6+vpTBEG0T/1foCiqo2uVVCr1zu12t3+tIrfY2tvb+9gux/P5fKIri61Gq8VmSqt2tajX63u73MUwDDpb7t6nadqD4ziJYZgVw7B7AAAgiuI3URT3z5a7H5LJ5G4ikfghimLvlrsaNGjQoEHDdcAfa3DcY57QdGAAAAAASUVORK5CYII=",
        sub_survivor = "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",
        survivor = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADyUlEQVR42u2YTUgbaRzG5ysxYYtiytoGFlbEj9pMDGghORTpQReE1UMx2lvpwWigsgch9iSepNfMjDkptBcRPARCy+JgLnG37UEqLryJQikm6sggETI7a8kmM7MnyzjOTDJpxix0frc3PO/wf3g//s8bCLKwsLCwsKgBn8/nXF5ensxkMm95nmd5nmczmcxbiqIm+vr6HGpzZmdnfblc7kOxWPyb53k2nU6/0dObgt1uh2Kx2BNBEEqSBoIglCiKmrDZbFfmut1u5Ozs7EBNT5JkUKk3pXiapl9KVULT9EtlUeFw2KOl39zcXDLVRCwWeyIZhCTJoPwbDocDYhhmV0tPEMS4aXteb9vobSev13tlj0ej0cda+nK5XFTq9UCqFYZCoTEEQTCjxhEEwUKh0Kj8N5qm/9DSoyhqn5qa+rXuK7C/v/+7VCPpdPqN/Fvt7e2Ynh4AkKi7AZ7n2VoN8DzPyr/ldDohPT3HcUzdt9C3IIqiIB/DMKyrlyRJrLuBo6OjnVoNHB8ff5SP29raMCP6uhhIJpOvazWwtbX1Sj7Gcfy2EX1Dr1G1a7HSNYrjuDnRgqKoCaMGlI2pUiOLRqOPTTuMNpvNUJRQiwYNjRKXJkiSDFYKcwRBjBsJc2p6U/F6vQ6SJIMAgMRlnAYAJAiCGNeKAuFw2COP3wCABEmSQSPRweL/BmwglEEDAwM/9Pf3/+zz+fpwHH/odrvvNTc3u1taWn6CIAgqFArHhULh5PT0dB8A8G5vb++v3d3d7M7Ozj+iqN1ce3p67JOTk4GDg4PD7e3tE4ZhhLq4wzAMGhsbu7uysvKUZVlQaxZiWRasrq4+Gx0dvYNh6k14eHj4dj6f/3QZ5paWln7p7e1tqqlwl8sFRyIRfzabfS/VmWw2+z4SifhdLte11R8cHGwplUpf5PpUKkWNjIz8WN1+gmFoZmbm/rckTyMJdXp6+r6yhrm5uQdq+lQqRXV2durfs4uLi4+kG2ZhYWFQ2WdyudwHLdNDQ0Mu1eIDgcAtURSFmzYgCELJ7/ffktcyPz8f0NJfXFzkVc/G+vr6b1KDWFtbey6vxePxNOnpNzY25q4Z0Fq2m+Dw8PBPIy82lmXBtT5QLpeLKIraG9GMBEH4F8OwJsWrTKpw4cBXDFSaYHpHVbwzqzWAyB/tjSqe47gT+bi1tRWuVo/InozRRhlIJpOkfNzR0eE0ov+aR87Pzz/f9AHO5/Ofurq6bMp/sY3ov9Ld3W2Px+MvOI5jzC6c4zgmHo+/UBaDoigEAEhUq7ewsLCw+L75D3xqnpHxu7/2AAAAAElFTkSuQmCC",
        world = "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",
    }
    Library.IconFolder = "NeverUI/icons"

    local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local B64Map = {}
    for i = 1, 64 do B64Map[string.byte(B64, i)] = i - 1 end
    local function B64Decode(str)
        local out, n = {}, 0
        for i = 1, #str, 4 do
            local a, b, c, d = string.byte(str, i, i + 3)
            local vc, vd = c and B64Map[c], d and B64Map[d]
            local triple = (B64Map[a] or 0) * 262144 + (B64Map[b] or 0) * 4096 + (vc or 0) * 64 + (vd or 0)
            n += 1
            out[n] = string.char(math.floor(triple / 65536) % 256)
            if vc then n += 1 out[n] = string.char(math.floor(triple / 256) % 256) end
            if vd then n += 1 out[n] = string.char(triple % 256) end
        end
        return table.concat(out)
    end

    local IconCache = {}
    local ICON_REV = { kb_soft = "_3", kb_pill = "_3", kb_bar = "_3", kb_ind = "_1" } -- [v31] новые версии картинок биндов
    function Library:GetIcon(name)
        if type(name) ~= "string" or name == "" then return nil end
        if string.find(name, "^rbx") then return name end
        local cached = IconCache[name]
        if cached ~= nil then return cached or nil end
        local loadAsset = getcustomasset or getsynasset
        local data = ICON_DATA[name]
        local id = nil
        if loadAsset and writefile and isfile and data then
            local ok, res = pcall(function()
                local path = ""
                for part in string.gmatch(self.IconFolder, "[^/]+") do
                    path = path == "" and part or (path .. "/" .. part)
                    if isfolder and makefolder and not isfolder(path) then makefolder(path) end
                end
                local file = self.IconFolder .. "/" .. name .. (ICON_REV[name] or "") .. ".png"
                if not isfile(file) then writefile(file, B64Decode(data)) end
                return loadAsset(file)
            end)
            if ok and type(res) == "string" and res ~= "" then id = res end
        end
        IconCache[name] = id or false
        return id
    end

    -- ШРИФТ NL (запасной, встроенный): Noto Sans Medium / SemiBold из NL dll, урезанные до латиницы +
    -- кириллицы (~40 КБ). Используется, если в папке fonts нет файлов и скачать с GitHub не вышло.
    local NL_FONT_B64 = {
        Medium = "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Moky1TMfMzkzUDNcM2gzdDOAM4wzlzOkM68z2DP1NAE0DTQZNCk0OTRFNGI0dDR9NIU0kTSdNKU0rTS5NMc01zVvNYk1mDW9NeI18QABAAAAAgNUHs4vhV8PPPUAAwPoAAAAAN2A0+cAAAAA4T2bF/2S/nYK8AQrAAAABgACAAAAAAAAAlgAXgEEAAABEgBEAasAQQKGABgCPAA4A1QALALhADEA7QBBATgAKAE4AB4CJQAmAjwAMAERACYBQgAlAREARAGAAAkCPAAtAjwAUAI8AC4CPAArAjwAFAI8ADsCPAAxAjwAJwI8AC0CPAAtAREARAERAB8CPAAwAjwANAI8ADABvwAJA4IAOAKOAAACkABfAnkAPALdAF8CLQBfAhAAXwLXADwC7ABfAWIAJgEi/7MCeABfAhgAXwOWAF8DCABfAxEAPAJkAF8DEQA8AnkAXwImADICMwANAuIAWQJnAAADrQAIAmIAAwJHAAACPgAiAUoATQGAAAkBSgAZAjwAIgGy//4BMQAoAj4ALQJsAFMB6gA0AmwANAI8ADQBZQAQAmwANAJ2AFMBEABMARD/xgIvAFMBEABTA7UAUwJ2AFMCYQA0AmwAUwJsADQBqQBTAeQAMQF/ABICdgBOAg4AAAMnAAsCHwAOAg8AAQHbACMBgAAYAicA6gGAACICPAAwAQQAAAESAEQCPABVAjwAIgI8ADoCPAALAicA6gH5ADkCTACRA0AAMQFtAB0CHAAoAjwAMAFCACUDQAAxAfT//QGsADICPAAwAWcAGQFnABUBMQAoAnoAUwKPADcBEQBEANsABQFnACcBfAAfAhwAJwMCAB4DIQAWAyAAGAG/ABkCjgAAAo4AAAKOAAACjgAAAo4AAAKOAAADhv//AnkAPAItAF8CLQBfAi0AXwItAF8BYgAgAWIAJgFi//wBYgAdAt0AHAMIAF8DEQA8AxEAPAMRADwDEQA8AxEAPAI8AEADEQA8AuIAWQLiAFkC4gBZAuIAWQJHAAACZABfAo8AUwI+AC0CPgAtAj4ALQI+AC0CPgAtAj4ALQNwAC0B6gA0AjwANAI8ADQCPAA0AjwANAEQ//cBEABOARD/0gEQ//QCYQA0AnYAUwJhADQCYQA0AmEANAJhADQCYQA0AjwAMAJhADQCdgBOAnYATgJ2AE4CdgBOAg8AAQJsAFMCDwABAo4AAAI+AC0CjgAAAj4ALQKOAAACPgAtAnkAPAHqADQCeQA8AeoANAJ5ADwB6gA0AnkAPAHqADQC3QBfAmwANALdABwCcgA0Ai0AXwI8ADQCLQBfAjwANAItAF8CPAA0Ai0AXwI8ADQCLQBfAjwANALXADwCbAA0AtcAPAJsADQC1wA8AmwANALXADwCbAA0AuwAXwJ2/9QC7AAAAnYABwFi//UBEP/LAWIAFwEQ/+4BYgALARD/4QFiACYBEAAgAWIAJgKEACYCIABMASL/swEQ/8YCeABfAi8AUwIvAFMCGABZARAATgIYAF8BEABCAhgAXwEQAFMCGABfASgAUwIYAAkBEP/2AwgAXwJ2AFMDCABfAnYAUwMIAF8CdgBTAsgAAQMIAF8CdgBTAxEAPAJhADQDEQA8AmEANAMRADwCYQA0A60APAO7ADMCeQBfAakAUwJ5AF8BqQBBAnkAXwGpAD4CJgAyAeQAMQImADIB5AAxAiYAMgHkADECJgAyAeQAMQIzAA0BfwASAjMADQF/ABIC4gBZAnYATgLiAFkCdgBOAuIAWQJ2AE4C4gBZAnYATgLiAFkCdgBOAuIAWQJ2AE4DrQAIAycACwJHAAACDwABAkcAAAI+ACIB2wAjAj4AIgHbACMCPgAiAdsAIwFXAFMBuwAoAbsAKAGDACgBnQAoAMgAKAEzACgA/wAoAcoAKAHOACgCLQBfAtoADQINAF8CgwA7AiQAMAEqAF8BKgAaASL/swP5AAQEDgBfAt4ADQKFAF8CcQAGAuUAXwKNAAACcABfAo8AXwINAF8C5wAKAi0AXwOkAAQCRgApAv4AXwL+AF8ChQBfAsUABAOWAF8C7wBfAv0AOwLmAF8CZQBfAoIAOwIzAA0CcQAGA0oANQJjAAQC7wBfAq8ASgQVAF8EEABfAsEADQNmAF8CagBgAooALAPsAF8CiwAbAjgALAJdADMCPwBUAcEAVAJoAAkCMQAvAxcABwHyACMCfQBUAn0AVAIsAFQCVwABAxQAVAJyAFQCWgAvAmsAVAJoAFQB9gAvAd0ADgIPAAEC9wAvAhIACAJxAFQCWwA8A48AUQOSAFQCfQAOAxMAVAIvAFQB+AApAy4AVAJKABwCMQAvAnUABAHCAFQB9wAvAd0AKgERAE0BEAAVARD/xwNmAAEDhQBUAnYABAIsAFQCDwAB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AAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/87/7P/i/87/xAAAAAAAAAAAAAAAAAAA/8T/zv/YAAAAAAAAAAD/7AAAAAD/sP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADIAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAD/7AAAAAAAAP/2AAAAAP/i/+wAAP/sAAAAAAAAAAAAAAAA/7AAAAAAAAAAAAAAAAD/7P/2//b/7P/YAAAAAAAAAAAAAAAAAAD/zv/2//YAAAAAAAAAAAAAAAAAAP/i//YAAP/EAAD/4v/Y/7oAAAAAAAAACgAUAAAAFAAA/+L/4gAAAAAAAAAAAAAAAP+wAAAAAAAA/7r/7P/O/7D/ugAA/+wAAAAAAAAAAAAU/8T/uv/EAAAAAP/YAAD/2AAAAAD/xP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAD/zgAAAAAAAP/sAAAAAP/E/8QAAP+6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAP/sAAAAAAAAAAAAAAAAAAAAAP9g//YAAAAAAAAAAAAoAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAP/OAAAAAAAAAAAAAAAAAAD/fgAAAAAAAP/2AAAAAAAAAAD/4v/sAAAAAAAAAAAAAAAAAAAAAAAAAB4AAAAAAAAAAAAA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AAD/7AAA/+IAAP/sAAD/xP/sAAD/9v/sAAAAAAAAAAAAAP+mAAAAAAAAAAAAAP/EAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7AAAP/YAAD/zv/s/8QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAADwAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAP/2AAD/9gAAAAAAAP/sAAD/2P/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//b/2AAA//YAAAAAAAAAAAAA/+IAAAAAAAD/zgAAAAAAAAAA/+L/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAD/7AAAAAAAAP/2AAD/4v/2AAAAAP/2AAAAAAAAAAAAAAAAAAD/+QAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAD/4gAA/9j/2AAA/9j/9gAAAAD/9v/2/7oAFAAA/+L/zv/t/+f/5wAA/+L/2AAU/+wAAP/iAAD/4gAAAAD/3QAAAAD/7P/s/9gAAAAAAAAAAP/O/7r/xAAAAAD/7AAAAAD/7P/Y/7oAFAAA/87/xP/Y/87/2AAAAAD/2AAA/+wAAAAA/8T/4gAAAAD/3gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAP/2AAD/2P/bAAAAAP/2AAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAGQAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAAAAAAA/+IAAP/sAAD/zv/s/+wAAP/sAAAAAAAAAAAAAP+6AAAAAAAAAAAAAP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+f/zv/s//YAAAAAAAAAAAAA/84AAP/sAAD/fgAA/8T/xAAA/9j/9gAAAAAAAP/2/+z/9gAAAAD/9gAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAA//EAAAAAAAAAAAAAAAAAAAAAAAD/7gAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/iAAD/2AAAAAAAAP/OAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAACgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//b/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAA/+wAAAAAAAD/xP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/5//YAAD/8f/iAAAAAAAA/93/3f/iAAD/2AAA/+L/6gAA//EAAP/2AAD/6//2AAAAAAAA//YAAP/2AAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7P/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB4AAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAAAAAAAAeAAAAAAAeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANAAIAFgADAAMAAAAIAAkAAQANAA8AAwA8ADwABgBcAFwABwBrAGsACAB7AHsACQFGAUoACgFOAVIADwFUAVsAFAFeAV4AHAFiAWIAHQFkAWoAHgFtAW4AJQFwAXIAJwF0AZgAKgGaAaYATwGoAaoAXAGsAa4AXwG2AbcAYgG8AbwAZAG+Ab8AZQACAFMAAwADAAoACAAIAAoACQAJABgADQANABAADgAOABIADwAPABAAPAA8ABgAXABcABgAawBrAB0AewB7AB4BRgFGAAwBRwFHABkBSAFIABUBSQFJAA0BSgFKACABTgFPAA8BUAFQABkBUQFRAAQBUgFSAAcBVAFUAAsBVQFVAB8BVgFWABsBVwFXABUBWAFYAAUBWQFZAAwBWgFaAAQBWwFbABsBXgFeAAQBYgFiAAIBZAFkABoBZQFlAA0BZgFmABUBZwFnAAcBaAFoACEBaQFpAAQBagFqAAUBbQFtAAUBbgFuAA8BcAFwAA8BcQFyAAIBdAF0ABcBdgF2ABQBdwF3AA4BeAF4AAMBegF6AAYBewF7ABQBfAF9AAEBfgF+AAYBfwGBAAEBgwGDAAEBhQGFABEBhgGGAA4BhwGHAAgBiQGJAAYBigGKAAMBiwGMAAEBjQGNAAMBjgGOAAkBjwGPAAEBkAGQAAkBkwGTAAEBlQGVABwBlgGWAA4BlwGXABEBmAGYACIBmgGaACQBmwGbACMBnAGdAAkBngGeABwBnwGfAAYBoAGgAAgBoQGhAAEBogGiABYBowGjABMBpAGmABIBqAGpAAoBqgGqABABrAGtAAoBrgGuABABtgG2AB0BtwG3AB4BvAG8AAwBvwG/AAEAAgBUAAMAAwAXAAgACAAXAAoACgAZAA0ADQAQAA4ADgAWAA8ADwAQABsAHAAaAD4APgAZAF4AXgAZAGsAawAbAHsAewAcAUcBRwANAUkBSQAYAUoBSgAeAU0BTQAhAU4BTgATAVABUAANAVIBUgAOAVQBVAAMAVgBWAASAVoBWgAFAVsBWwAIAV8BXwATAWIBYgAYAWUBZQAYAWYBZgANAWcBZwAOAWgBaAAfAWkBaQAFAWsBawAJAW4BbgANAXEBcQAIAXMBcwAgAXQBdAADAXUBdQAiAXYBdwABAXgBeAAEAXkBeQAGAXoBegAHAXsBewAKAXwBfgABAX8BfwAVAYABgQABAYIBggAGAYMBhAABAYUBhQAGAYYBhgALAYcBhwARAYgBiAAGAYkBiQAHAYoBigABAYsBiwAPAYwBjQABAY4BjgALAY8BkAABAZEBkQAKAZIBkgABAZMBkwAkAZQBlAAGAZUBlQAUAZYBlgABAZcBlwAGAZgBmAAjAZoBmgAmAZsBmwAlAZwBnAAVAZ0BnQABAZ4BngAUAZ8BnwABAaABoAARAaEBoQABAaMBowACAaQBpgAWAagBqAAdAakBqQAXAaoBqgAQAawBrAAdAa0BrQAXAa4BrgAQAbIBsgAQAbYBtgAbAbcBtwAcAb4BvgAGAb8BvwABAAAAAQAAAAoANgBEAAVERkxUACBjeXJsACBkZXYyACBncmVrACBsYXRuACAABAAAAAD//wABAAAAAWxpZ2EACAAAAAEAAAABAAQABAAIAAEACAABADYAAQAIAAUADAAUABwAIgAoAckAAwBHAEoBygADAEcATQHGAAIARwHHAAIASgHIAAIATQABAAEARwABAAEACAADAAAAFAADAAAALAACd2dodAEEAAB3ZHRoAQUAAWl0YWwBEwACAAYAEgAeAAEAAAAAAQoB9AAAAAEAAQACARIAZAAAAAMAAgACARQAAAAAAAEAAAAA",
        SemiBold = "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AkwALAKfAAACTAAsAnsAOwH1ADECewA7AfUAMQJ7ADsB9QAxAnsAOwH1ADEC4ABdAnIAMQLgABoCfQAxAi4AXQJFADECLgBdAkUAMQIuAF0CRQAxAi4AXQJFADECLgBdAkUAMQLWADsCcgAxAtYAOwJyADEC1gA7AnIAMQLWADsCcgAxAvQAXQKC/84C9AAAAoIABQFy//cBH//NAXIAGgEf//ABcgAHAR//3gFyACMBHwAmAXIAIwKnACMCPwBKATX/tAEf/8MChwBdAkwAUQJMAFECJgBbAR8AUAImAF0BHwBDAiYAXQEfAFECJgBdAUcAUQImAAYBH//1AxkAXQKCAFEDGQBdAoIAUQMZAF0CggBRAuMAAgMZAF0CggBRAxYAOwJmADEDFgA7AmYAMQMWADsCZgAxA7wAOwPGADAChgBdAbcAUQKGAF0BtwBEAoYAXQG3ADUCJgAwAeoALwImADAB6gAvAiYAMAHqAC8CJgAwAeoALwI6ABABlgAUAjoAEAGWABQC6wBXAoIATQLrAFcCggBNAusAVwKCAE0C6wBXAoIATQLrAFcCggBNAusAVwKCAE0DuQAFAz4ACgJaAAACIwAAAloAAAJAAB0B4QAgAkAAHQHhACACQAAdAeEAIAFqAFEB2AAoAdgAKAGOACgBtAAoANwAKAE8ACgBCgAoAdcAKAHnACgCLgBdAusAEAIfAF0ChwA7AiQALQE5AF0BOQAWATX/tAQBAAUEGQBdAvIAEAKbAF0CegAHAvEAXQKeAAACfABdApUAXQIfAF0C9gAKAi4AXQPCAAYCSwArAwoAXQMKAF0CmwBdAtIABQOhAF0C+ABdAwIAOgLvAF0CbQBcAoUAOwI6ABACegAHA2YANgJ9AAIC+gBdAr4ASAQgAF0EIQBdAtgAEAN9AF0CdwBdAo0AKgPyAF0CmQAYAkUAKgJmADECSwBSAc0AUgJyAAcCPAAuAzoABgH+ACMCjgBSAo4AUgJIAFICZQADAysAUgKAAFICYwAtAnkAUgJxAFICAQAtAeoADAIjAAIDDgAtAiYABgKAAFICawA8A6MAUQOlAFICjQAMAzIAUgI+AFICAwAnAz8AUgJUABMCPAAuAoAAAgHQAFICAwAtAeYAKwEhAEsBHwASAR//xQNzAAMDkABSAoEAAgJIAFICIwACAnkAUgIzAF0B4wBR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/+L/2AAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9gAAAAAAAAAAAAAACgAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/O/+z/4v/O/8QAAAAAAAAAAAAAAAAAAP/E/87/2AAAAAAAAAAA/+wAAAAA/7D/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAyAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAA/+wAAAAAAAD/9gAAAAD/4v/sAAD/7AAAAAAAAAAAAAAAAP+wAAAAAAAAAAAAAAAA/+z/9v/2/+z/2AAAAAAAAAAAAAAAAAAA/87/9v/2AAAAAAAAAAAAAAAAAAD/4v/2AAD/xAAA/+L/2P+6AAAAAAAAAAoAFAAAABQAAP/i/+IAAAAAAAAAAAAAAAD/sAAAAAAAAP+6/+z/zv+w/7oAAP/sAAAAAAAAAAAAFP/E/7r/xAAAAAD/2AAA/9gAAAAA/8T/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAA/84AAAAAAAD/7AAAAAD/xP/EAAD/ugAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAD/7AAAAAAAAAAAAAAAAAAAAAD/YP/2AAAAAAAAAAAAKAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAD/zgAAAAAAAAAAAAAAAAAA/34AAAAAAAD/9gAAAAAAAAAA/+L/7AAAAAAAAAAAAAAAAAAAAAAAAAAeAAAAAAAAAAAAAAAAAAAAAAAAAAAAKAAAAEYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAA8AAAAKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/i//YAAP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7D/4gAA/8QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAKcAAwAIAA0ADgAPACIAJAAlACYALAAtADAAMQAyADUANgA3ADgAOQA6ADsAQgBDAEYARwBJAE4ATwBQAFEAUwBVAFcAWABZAFoAawB7AIAAgQCCAIMAhACFAIYAhwCIAIkAigCLAJAAkgCTAJQAlQCWAJgAmQCaAJsAnACdAJ4AoAChAKIAowCkAKUApgCoAKkAqgCrAK4ArwCwALIAswC0ALUAtgC4AL0AvgC/AMAAwQDCAMMAxADFAMYAyADKAMwAzgDPANAA0gDTANQA1QDWANcA2ADZANoA2wDlAOkA6wD1APcA+AD6APwA/QD+AQABAwEFAQgBCgELAQwBDQEOAQ8BEAERARIBFAEWARgBIQEiASMBJAElAScBKQErAS0BLwExATIBMwE0ATUBNgE4AToBpAGlAaYBqAGpAaoBrAGtAa4BtgG3AcABwQHGAAIAcQADAAMADAAIAAgADAANAA0AEAAOAA4AEQAPAA8AEAAiACIAAgAkACQACQAlACUAAwAmACYABAAsACwAEwAtAC0ACgAwADAAAwAxADEAFAAyADIAAwA1ADUADQA2ADYABgA3ADgACwA5ADkAEwA6ADoABwA7ADsADwBCAEIAAQBHAEcAFgBJAEkAAQBOAE8AAQBTAFMAEgBVAFUADgBXAFgABQBZAFkAGQBaAFoABQBrAGsAFwB7AHsAGACAAIUAAgCGAIYABACHAIcACQCIAIsABACQAJAAAwCSAJYAAwCYAJgAAwCZAJwABgCdAJ0ABwCeAJ4AFACgAKUAAQCuAK8ACAC9AL0ABQC/AL8ABQDAAMAAAgDBAMEAAQDCAMIAAgDDAMMAAQDEAMQAAgDFAMUAAQDGAMYACQDIAMgACQDKAMoACQDMAMwACQDOAM4AAwDPAM8AFQDQANAAAwDSANIABADUANQABADWANYABADYANgABADaANoABADlAOUAAQDpAOkACADrAOsACAD1APUAEwD3APcAGQD4APgACgD6APoACgD8APwACgD9AP0AFQD+AP4ACgEAAQAACgEDAQMAAQEFAQUAAQEIAQgAAQEKAQoAAQELAQsAAwENAQ0AAwEPAQ8AAwERAREABAEUARQAEgEWARYAEgEYARgAEgEhASEADQEiASIADgEjASMADQEkASQADgElASUABgEnAScABgEpASkABgErASsABgEtAS0ABgEvAS8ABgExATEACwEyATIABQEzATMABwE0ATQABQE1ATUABwE2ATYADwE4ATgADwE6AToADwGkAaYAEQGoAakADAGqAaoAEAGsAa0ADAGuAa4AEAG2AbYAFwG3AbcAGAHAAcAADQHBAcEADgHGAcYAFgACAI4AAwADABMACAAIABMACgAKABUADQANAA0ADgAOABIADwAPAA0AIgAiAAUAJAAkAAIAKAAoAAIAMAAwAAIAMgAyAAIANQA1AAwANgA2AAYANwA4AAoAOgA6AAkAOwA7ABEAPgA+ABUAQgBCAAQAQwBDAAgARABGAAEARwBHAAsASABIAA4ASQBJAAgATABNAAgATgBPAAMAUABQAAEAUQBRAAMAUgBSAAEAUwBTAAMAVABUAA8AVQBVABAAVgBWAAMAVwBaAAcAWwBbABQAXgBeABUAawBrABcAewB7ABgAgACFAAUAhgCGABYAhwCHAAIAkgCWAAIAmACYAAIAmQCcAAYAnQCdAAkAoACgAAEAoQCmAAQApwCrAAEAsgC2AAEAuAC4AAEAuQC8AAMAvQC9AAcAvgC+AAgAvwC/AAcAwADAAAUAwQDBAAQAwgDCAAUAwwDDAAQAxADEAAUAxQDFAAQAxgDGAAIAxwDHAAEAyADIAAIAyQDJAAEAygDKAAIAywDLAAEAzADMAAIAzQDNAAEAzwDPAAEA0QDRAAEA0wDTAAEA1QDVAAEA1wDXAAEA2QDZAAEA2wDbAAEA3ADcAAIA3QDdAA4A3gDeAAIA3wDfAA4A4ADgAAIA4QDhAA4A4gDiAAIA4wDjAA4A5QDlAAgA9gD2AAgA9wD3AAMA+QD5AAgA+wD7AAgA/QD9AAgA/wD/AAgBAwEDAAMBBQEFAAMBCgEK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AAAAAAAA/+wAAP/iAAD/7AAA/8T/7AAA//b/7AAAAAAAAAAAAAD/pgAAAAAAAAAAAAD/xAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP+wAAD/2AAA/87/7P/EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9gAAAA8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAD/9gAA//YAAAAAAAD/7AAA/9j/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2/9gAAP/2AAAAAAAAAAAAAP/iAAAAAAAA/84AAAAAAAAAAP/i/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAA/+wAAAAAAAD/9gAA/+L/9gAAAAD/9gAAAAAAAAAAAAAAAAAA//wAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAA/+IAAP/Y/9gAAP/Y//YAAAAA//b/9v+6ABQAAP/i/87/7//n/+cAAP/i/9gAFP/sAAD/4gAA/+IAAAAA/90AAAAA/+z/7P/YAAAAAAAAAAD/zv+6/8QAAAAA/+wAAAAA/+z/2P+6ABQAAP/O/8T/2P/O/9gAAAAA/9gAAP/sAAAAAP/E/+IAAAAA/+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAD/9gAA/9j/3gAAAAD/9gAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+IAAABkAAAAAAAAADwAAAAAAAAAAAAAAAAAAAAAAAAAAP/iAAD/7AAA/87/7P/sAAD/7AAAAAAAAAAAAAD/ugAAAAAAAAAAAAD/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/n/87/7P/2AAAAAAAAAAAAAP/OAAD/7AAA/34AAP/E/8QAAP/Y//YAAAAAAAD/9v/s//YAAAAA//YAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAP/xAAAAAAAAAAAAAAAAAAAAAAAA//cAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAA/9gAAAAAAAD/zgAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2/+IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAP/sAAAAAAAA/8T/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+f/2AAA//H/4gAAAAAAAP/d/93/4gAA/9gAAP/i/+0AAP/xAAD/9gAA//X/9gAAAAAAAP/2AAD/9gAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+z/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAeAAAAAAAAABQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAAAAAAAAAAAAAAAAAHgAAAAAAHgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAACABYAAwADAAAACAAJAAEADQAPAAMAPAA8AAYAXABcAAcAawBrAAgAewB7AAkBRgFKAAoBTgFSAA8BVAFbABQBXgFeABwBYgFiAB0BZAFqAB4BbQFuACUBcAFyACcBdAGYACoBmgGmAE8BqAGqAFwBrAGuAF8BtgG3AGIBvAG8AGQBvgG/AGUAAgBTAAMAAwAKAAgACAAKAAkACQAYAA0ADQAQAA4ADgASAA8ADwAQADwAPAAYAFwAXAAYAGsAawAdAHsAewAeAUYBRgAMAUcBRwAZAUgBSAAVAUkBSQANAUoBSgAgAU4BTwAPAVABUAAZAVEBUQAEAVIBUgAHAVQBVAALAVUBVQAfAVYBVgAbAVcBVwAVAVgBWAAFAVkBWQAMAVoBWgAEAVsBWwAbAV4BXgAEAWIBYgACAWQBZAAaAWUBZQANAWYBZgAVAWcBZwAHAWgBaAAhAWkBaQAEAWoBagAFAW0BbQAFAW4BbgAPAXABcAAPAXEBcgACAXQBdAAXAXYBdgAUAXcBdwAOAXgBeAADAXoBegAGAXsBewAUAXwBfQABAX4BfgAGAX8BgQABAYMBgwABAYUBhQARAYYBhgAOAYcBhwAIAYkBiQAGAYoBigADAYsBjAABAY0BjQADAY4BjgAJAY8BjwABAZABkAAJAZMBkwABAZUBlQAcAZYBlgAOAZcBlwARAZgBmAAiAZoBmgAkAZsBmwAjAZwBnQAJAZ4BngAcAZ8BnwAGAaABoAAIAaEBoQABAaIBogAWAaMBowATAaQBpgASAagBqQAKAaoBqgAQAawBrQAKAa4BrgAQAbYBtgAdAbcBtwAeAbwBvAAMAb8BvwABAAIAVAADAAMAFwAIAAgAFwAKAAoAGQANAA0AEAAOAA4AFgAPAA8AEAAbABwAGgA+AD4AGQBeAF4AGQBrAGsAGwB7AHsAHAFHAUcADQFJAUkAGAFKAUoAHgFNAU0AIQFOAU4AEwFQAVAADQFSAVIADgFUAVQADAFYAVgAEgFaAVoABQFbAVsACAFfAV8AEwFiAWIAGAFlAWUAGAFmAWYADQFnAWcADgFoAWgAHwFpAWkABQFrAWsACQFuAW4ADQFxAXEACAFzAXMAIAF0AXQAAwF1AXUAIgF2AXcAAQF4AXgABAF5AXkABgF6AXoABwF7AXsACgF8AX4AAQF/AX8AFQGAAYEAAQGCAYIABgGDAYQAAQGFAYUABgGGAYYACwGHAYcAEQGIAYgABgGJAYkABwGKAYoAAQGLAYsADwGMAY0AAQGOAY4ACwGPAZAAAQGRAZEACgGSAZIAAQGTAZMAJAGUAZQABgGVAZUAFAGWAZYAAQGXAZcABgGYAZgAIwGaAZoAJgGbAZsAJQGcAZwAFQGdAZ0AAQGeAZ4AFAGfAZ8AAQGgAaAAEQGhAaEAAQGjAaMAAgGkAaYAFgGoAagAHQGpAakAFwGqAaoAEAGsAawAHQGtAa0AFwGuAa4AEAGyAbIAEAG2AbYAGwG3AbcAHAG+Ab4ABgG/Ab8AAQAAAAEAAAAKADYARAAFREZMVAAgY3lybAAgZGV2MgAgZ3JlawAgbGF0bgAgAAQAAAAA//8AAQAAAAFsaWdhAAgAAAABAAAAAQAEAAQACAABAAgAAQA2AAEACAAFAAwAFAAcACIAKAHJAAMARwBKAcoAAwBHAE0BxgACAEcBxwACAEoByAACAE0AAQABAEcAAQABAAgAAwAAABQAAwAAACwAAndnaHQBBAAAd2R0aAEFAAFpdGFsARMAAgAGABIAHgABAAAAAAELAlgAAAABAAEAAgESAGQAAAADAAIAAgEUAAAAAAABAAAAAA==",
    }
    -- иконка 14x14 (или точка 6x6, если экзекьютор не умеет getcustomasset)
    local function Icon(parent, name, colorKey, size, fallbackDot)
        local id = Library:GetIcon(name)
        if id then
            local img = Create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size or 14, size or 14),
                BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Fit, Parent = parent,
            })
            if colorKey then Theme(img, { ImageColor3 = colorKey }) end
            return img
        end
        if not fallbackDot then return nil end
        local dot = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
            BorderSizePixel = 0, Parent = parent,
        })
        Corner(dot, 3)
        if colorKey then Theme(dot, { BackgroundColor3 = colorKey }) end
        return dot
    end

    -- AMBIENCE: список с галочками (Multi dropdown); не закрывается после выбора
    local function OpenMultiList(anchor, values, isOn, onToggle)
        local n = #values
        local w = math.max(anchor.AbsoluteSize.X, 150)
        local h = math.clamp(n * 28 + 8, 36, 236)
        OpenPopup(anchor, w, h, function(frame)
            local scroll = Create("ScrollingFrame", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
                ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = frame,
            })
            Theme(scroll, { ScrollBarImageColor3 = "OutlineColor" })
            Pad(scroll, 4, 4, 4, 4)
            List(scroll, nil, 2)
            for i, v in ipairs(values) do
                local b = Button({ Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Parent = scroll })
                Theme(b, { BackgroundColor3 = "ItemColor" })
                Corner(b, 6)
                local lbl = Text({ Text = tostring(v), TextSize = 13, FontFace = F(W_REG), ColorKey = false,
                    Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -36, 1, 0), Parent = b })
                local chk = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Parent = b })
                local ic = Icon(chk, "wm_check", "AccentColor", 11, false)
                local function paint()
                    local on = isOn(v)
                    lbl.TextColor3 = on and Scheme.FontColor or Scheme.SubColor
                    if ic then ic.Visible = on end
                end
                paint()
                b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
                b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
                b.MouseButton1Click:Connect(function()
                    Safe(onToggle, v)
                    paint()
                end)
            end
        end)
    end


    --------------------------------------------------------
    -- ЭФФЕКТЫ: тень и свечение - ImageLabel с 9-slice текстурой вокруг объекта.
    -- Внутренность текстуры вырезана, поэтому под полупрозрачным окном фон не темнеет.
    --------------------------------------------------------
    local FX = {
        shadow = { R = 16, P = 16, Slice = Rect.new(32, 32, 34, 34) },
        glow   = { R = 10, P = 6,  Slice = Rect.new(16, 16, 18, 18) },
    }
    -- radius - скругление объекта; растушёвка масштабируется вместе с ним
    FxImage = function(parent, kind, radius, colorKey)
        local id = Library:GetIcon("fx_" .. kind)
        if not id then return nil end
        local f = FX[kind]
        local sc = (radius or f.R) / f.R
        local pad = f.P * sc
        local img = Create("ImageLabel", {
            Name = "FX_" .. kind, BackgroundTransparency = 1, Image = id, ScaleType = Enum.ScaleType.Slice,
            SliceCenter = f.Slice, SliceScale = sc, ImageColor3 = Color3.new(0, 0, 0), ZIndex = 0,
            Position = UDim2.fromOffset(-pad, -pad), Size = UDim2.new(1, pad * 2, 1, pad * 2), Parent = parent,
        })
        if colorKey then Theme(img, { ImageColor3 = colorKey }) end
        return img
    end
    Shadow = function(parent, radius) return FxImage(parent, "shadow", radius) end
    -- ФИКС «взрыва»: тень-ребёнок у рамки с AutomaticSize/UIListLayout/UIPadding
    -- участвует в раскладке и раздувает рамку. Для таких рамок тень живёт рядом
    -- (у того же родителя) и просто повторяет её положение и размер.
    local function FollowShadow(target, radius)
        local img = FxImage(target.Parent, "shadow", radius)
        if not img then return nil end
        img.ZIndex = math.max(0, (target.ZIndex or 1) - 1)
        local pad = FX.shadow.P * radius / FX.shadow.R
        local function upd()
            local p, sz, pp = target.AbsolutePosition, target.AbsoluteSize, target.Parent.AbsolutePosition
            img.Position = UDim2.fromOffset(p.X - pp.X - pad, p.Y - pp.Y - pad)
            img.Size = UDim2.fromOffset(sz.X + pad * 2, sz.Y + pad * 2)
            img.Visible = target.Visible
        end
        for _, prop in ipairs({ "AbsolutePosition", "AbsoluteSize", "Visible" }) do
            Connect(target:GetPropertyChangedSignal(prop), upd)
        end
        upd()
        return img
    end
    -- тень и прозрачность подсказки (сам Tip создан раньше)
    FollowShadow(Tip, 6)
    Library:AddRefresh(function() Tip.BackgroundTransparency = Library.Transparency end)
    local SHADOW_PAD = FX.shadow.P + 2 -- запас для CanvasGroup при анимации окна

    --------------------------------------------------------
    -- ЭФФЕКТ: размытый фон за окном («матовое стекло», на видео сквозь окно виден
    -- размытый силуэт оружия). В Roblox GUI сам ничего не размывает, поэтому приём
    -- как в Fluent/WindUI: почти невидимая стеклянная деталь вплотную к камере ровно
    -- под окном + DepthOfField (FarIntensity 0, InFocusRadius 0.1, NearIntensity 1).
    -- Деталь локальная (в Camera), на сервер не реплицируется. Пока блюр включён,
    -- чужие DepthOfField игры временно выключаются и потом возвращаются как были.
    -- Нужна высокая графика Roblox; на низкой просто не будет размытия.
    --------------------------------------------------------
    Acrylic = { On = false }
    do
        local Lighting = game:GetService("Lighting")
        local DIST = 0.001
        local part, mesh, dof
        local saved = {}
        local function build()
            return pcall(function()
                if not dof then
                    dof = Instance.new("DepthOfFieldEffect")
                    dof.Name = HttpService:GenerateGUID(false)
                    dof.FarIntensity, dof.InFocusRadius, dof.NearIntensity = 0, 0.1, 1
                end
                part = Instance.new("Part")
                part.Name = HttpService:GenerateGUID(false)
                part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
                part.Material = Enum.Material.Glass
                part.Color = Color3.new(0, 0, 0)
                part.Transparency = 0.98
                part.Size = Vector3.new(1, 1, 0)
                mesh = Instance.new("SpecialMesh")
                mesh.MeshType = Enum.MeshType.Brick
                mesh.Offset = Vector3.new(0, 0, -0.000001)
                mesh.Parent = part
            end)
        end
        -- одна деталь на всё время; если игра её удалила (Parent заблокирован) - создаём заново
        local function ensure(parent)
            if part and pcall(function() part.Parent = parent end) then return true end
            part = nil
            if not build() then part = nil return false end
            return pcall(function() part.Parent = parent end)
        end
        function Acrylic:Set(on)
            on = on == true
            if on == self.On then return end
            if on and not ensure(nil) then return end
            self.On = on
            pcall(function()
                local cam = workspace.CurrentCamera
                if on then
                    saved = {}
                    local function reg(x)
                        if x ~= dof and x:IsA("DepthOfFieldEffect") then saved[x] = x.Enabled x.Enabled = false end
                    end
                    for _, x in ipairs(Lighting:GetChildren()) do reg(x) end
                    if cam then for _, x in ipairs(cam:GetChildren()) do reg(x) end end
                    dof.Parent = Lighting
                    if not ensure(cam or workspace) then self.On = false dof.Parent = nil end
                else
                    if dof then dof.Parent = nil end
                    if part then part.Parent = nil end
                    for x, en in pairs(saved) do pcall(function() x.Enabled = en end) end
                    saved = {}
                end
            end)
        end
        -- каждый кадр: деталь накрывает прямоугольник окна (с отступом под скругление углов)
        function Acrylic:Update(gui, inset)
            if not self.On then return end
            local cam = workspace.CurrentCamera
            if not cam then return end
            -- камеру пересоздали или игра почистила её детей: возвращаем/пересоздаём деталь
            if not part or part.Parent ~= cam then
                if not ensure(cam) then return end
            end
            pcall(function()
                local p, sz = gui.AbsolutePosition, gui.AbsoluteSize
                local function at(x, y)
                    local r = cam:ScreenPointToRay(x, y)
                    return r.Origin + r.Direction * DIST
                end
                local tl = at(p.X + inset, p.Y + inset)
                local tr = at(p.X + sz.X - inset, p.Y + inset)
                local br = at(p.X + sz.X - inset, p.Y + sz.Y - inset)
                local cf = cam.CFrame
                mesh.Scale = Vector3.new((tr - tl).Magnitude, (tr - br).Magnitude, 0)
                part.CFrame = CFrame.fromMatrix((tl + br) / 2, cf.XVector, cf.YVector, cf.ZVector)
            end)
        end
        function Acrylic:Destroy()
            self:Set(false)
            pcall(function() if part then part:Destroy() end end)
            pcall(function() if dof then dof:Destroy() end end)
        end
    end

    --------------------------------------------------------
    -- метрики (сняты со скриншотов, px при масштабе 1)
    --------------------------------------------------------
    local ROW_H     = 38   -- высота строки в секции
    local ROW_PAD   = 13   -- отступ текста/контролов от краёв панели
    local SEP_INSET = 7    -- отступ разделителя строк от краёв панели
    local CTRL_W    = 135  -- ширина dropdown / input
    local CTRL_H    = 24
    local TRACK_W   = 90   -- полоса слайдера (в оригинале 104, урезано под длинные подписи)

    --------------------------------------------------------
    -- элементы: switch 34x20, кружок 14
    --------------------------------------------------------
    local function Switch(parent, order)
        local track = Create("Frame", { Size = UDim2.fromOffset(34, 20), BorderSizePixel = 0, LayoutOrder = order or 100, Parent = parent })
        Corner(track, 10)
        -- ЭФФЕКТ: свечение акцентом вокруг включённого переключателя (как на видео)
        local glow = FxImage(track, "glow", 10, "AccentColor")
        if glow then glow.ImageTransparency = 1 end
        local knob = Create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(14, 14),
            BorderSizePixel = 0, Parent = track,
        })
        Corner(knob, 7)
        return track, knob
    end

    local function PaintSwitch(track, knob, on, instant)
        local tc = on and Scheme.AccentColor or Scheme.OffTrack
        local kc = on and WHITE or Scheme.OffKnob
        if on and Library.Style and Library.Style.ClassicSwitch then
            -- старый NL: дорожка - тёмный оттенок акцента, кружок - акцент
            tc = Scheme.AccentColor:Lerp(Scheme.OffTrack, 0.78)
            kc = Scheme.AccentColor
        end
        local kp = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local glow = track:FindFirstChild("FX_glow")
        local gt = (on and Library.Glow) and 0 or 1
        if instant then
            track.BackgroundColor3, knob.BackgroundColor3, knob.Position = tc, kc, kp
            if glow then glow.ImageTransparency = gt end
        else
            Tween(track, 0.18, { BackgroundColor3 = tc })
            Tween(knob, 0.18, { BackgroundColor3 = kc, Position = kp })
            if glow then Tween(glow, 0.18, { ImageTransparency = gt }) end
        end
    end

    -- правая часть строки (аддоны + контрол), растёт влево
    local function RightBox(row)
        local box = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -ROW_PAD, 0.5, 0),
            Size = UDim2.fromOffset(0, 24), AutomaticSize = AX, BackgroundTransparency = 1, Parent = row,
        })
        List(box, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
        return box
    end

    -- подпись строки: как в NL текст обрезается краем, без "..."
    local function RowLabel(row, text)
        return Text({
            Text = tostring(text or ""), TextSize = 14, FontFace = F(W_REG), Position = UDim2.fromOffset(ROW_PAD, 0),
            Size = UDim2.new(1, -ROW_PAD * 2, 1, 0), ClipsDescendants = true, Parent = row,
        })
    end

    -- подпись не заезжает под правые контролы
    local function FitLabel(label, right, extra)
        local function fit()
            local sc = Library._UIScale and Library._UIScale.Scale or 1
            local w = math.floor(right.AbsoluteSize.X / math.max(sc, 0.01) + 0.5)
            label.Size = UDim2.new(1, -ROW_PAD * 2 - w - (extra or 8), 1, 0)
        end
        right:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
        fit()
    end

    -- "v"
    local function Chevron(parent, key)
        local c = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(9, 6),
            BackgroundTransparency = 1, Parent = parent,
        })
        for i, rot in ipairs({ 45, -45 }) do
            local f = Create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(i == 1 and 0.28 or 0.72, 0, 0.5, 0),
                Size = UDim2.fromOffset(6, 2), Rotation = rot, BorderSizePixel = 0, Parent = c,
            })
            Corner(f, 1)
            Theme(f, { BackgroundColor3 = key or "ValueColor" })
        end
        return c
    end

    -- ">"
    local function Arrow(parent, key, x)
        local c = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x or -ROW_PAD - 2, 0.5, 0), Size = UDim2.fromOffset(6, 10),
            BackgroundTransparency = 1, Parent = parent,
        })
        for i, rot in ipairs({ 45, -45 }) do
            local f = Create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, i == 1 and 0.28 or 0.72, 0),
                Size = UDim2.fromOffset(7, 2), Rotation = rot, BorderSizePixel = 0, Parent = c,
            })
            Corner(f, 1)
            Theme(f, { BackgroundColor3 = key or "ValueColor" })
        end
        return c
    end

    -- тёмное поле (значение слайдера, кнопка бинда): 22px, скругление 5
    local function ValueBox(parent, order, clickable)
        local props = { BackgroundTransparency = 0, BorderSizePixel = 0, Size = UDim2.fromOffset(0, 22), AutomaticSize = AX, LayoutOrder = order, Parent = parent }
        local box = clickable and Button(props) or Create("Frame", props)
        Theme(box, { BackgroundColor3 = "InputColor" })
        Corner(box, 5)
        Stroke(box, "InputBorder")
        Pad(box, 7, 7, 0, 0)
        Create("UISizeConstraint", { MinSize = Vector2.new(44, 22), Parent = box })
        local label = Text({
            Text = "", TextSize = 12, ColorKey = "ValueColor", Size = UDim2.fromScale(0, 1), AutomaticSize = AX,
            TextXAlignment = Enum.TextXAlignment.Center, Parent = box,
        })
        Create("UISizeConstraint", { MinSize = Vector2.new(30, 0), Parent = label })
        return box, label
    end

    -- поле 135x24 (dropdown / input)
    local function FieldFrame(class, row)
        local props = {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -ROW_PAD, 0.5, 0),
            Size = UDim2.fromOffset(CTRL_W, CTRL_H), BorderSizePixel = 0, Parent = row,
        }
        local f = class == "TextButton" and Button(props) or Create(class, props)
        f.BackgroundTransparency = 0
        Theme(f, { BackgroundColor3 = "InputColor" })
        Corner(f, 6)
        Stroke(f, "InputBorder")
        return f
    end

    --------------------------------------------------------
    -- color picker (кружок 16x16, скругление 5, как "Scope Overlay")
    --------------------------------------------------------
    local HUE_SEQ = ColorSequence.new({
        ColorSequenceKeypoint.new(0,     Color3.fromHSV(0, 1, 1)),
        ColorSequenceKeypoint.new(1 / 6, Color3.fromHSV(1 / 6, 1, 1)),
        ColorSequenceKeypoint.new(2 / 6, Color3.fromHSV(2 / 6, 1, 1)),
        ColorSequenceKeypoint.new(3 / 6, Color3.fromHSV(3 / 6, 1, 1)),
        ColorSequenceKeypoint.new(4 / 6, Color3.fromHSV(4 / 6, 1, 1)),
        ColorSequenceKeypoint.new(5 / 6, Color3.fromHSV(5 / 6, 1, 1)),
        ColorSequenceKeypoint.new(1,     Color3.fromHSV(1, 1, 1)),
    })

    local function NewColorPicker(idx, info, parent, order)
        info = info or {}
        local CP = {
            Type = "ColorPicker", Value = info.Default or WHITE, Transparency = info.Transparency or 0,
            Title = info.Title or info.Text or "Color", Changed = {}, Callback = info.Callback,
        }
        CP.Hue, CP.Sat, CP.Vib = CP.Value:ToHSV()

        local swatch = Button({ BackgroundTransparency = 0, Size = UDim2.fromOffset(16, 16), LayoutOrder = order, Parent = parent })
        Corner(swatch, 5)

        function CP:Display()
            swatch.BackgroundColor3 = self.Value
            if self._Sync then self._Sync() end
        end
        function CP:OnChanged(fn) table.insert(self.Changed, fn) end
        function CP:SetHSV(h, s, v)
            self.Hue, self.Sat, self.Vib = h, s, v
            self.Value = Color3.fromHSV(h, s, v)
            self:Display()
            Fire(self)
        end
        function CP:SetValueRGB(c, transparency)
            if typeof(c) ~= "Color3" then return end
            if transparency then self.Transparency = transparency end
            self.Value = c
            self.Hue, self.Sat, self.Vib = c:ToHSV()
            self:Display()
            Fire(self)
        end
        function CP:SetValue(v, transparency)
            if typeof(v) == "Color3" then return self:SetValueRGB(v, transparency) end
            if type(v) == "table" then
                if transparency then self.Transparency = transparency end
                return self:SetHSV(v[1] or 0, v[2] or 0, v[3] or 0)
            end
            return nil
        end

        swatch.MouseButton1Click:Connect(function()
            OpenPopup(swatch, 232, 238, function(frame, _, popup)
                Text({ Text = CP.Title, TextSize = 13, FontFace = F(W_SEMI), Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), Parent = frame })

                local sv = Button({ BackgroundTransparency = 0, Position = UDim2.fromOffset(12, 32), Size = UDim2.fromOffset(176, 150), Parent = frame })
                Corner(sv, 6)
                local white = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = sv })
                Corner(white, 6)
                Create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
                local black = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv })
                Corner(black, 6)
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
                local svCursor = Create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 3, Parent = sv,
                })
                Corner(svCursor, 5)
                Create("UIStroke", { Color = WHITE, Thickness = 2, Parent = svCursor })

                local hue = Button({ BackgroundTransparency = 0, BackgroundColor3 = WHITE, Position = UDim2.fromOffset(198, 32), Size = UDim2.fromOffset(20, 150), Parent = frame })
                Corner(hue, 6)
                Create("UIGradient", { Rotation = 90, Color = HUE_SEQ, Parent = hue })
                local hueCursor = Create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = WHITE,
                    BorderSizePixel = 0, ZIndex = 3, Parent = hue,
                })
                Corner(hueCursor, 2)

                local hex = Create("TextBox", {
                    Position = UDim2.fromOffset(12, 196), Size = UDim2.fromOffset(120, 28), BorderSizePixel = 0,
                    ClearTextOnFocus = false, FontFace = F(W_MED), TextSize = 13, Text = "", Parent = frame,
                })
                Theme(hex, { BackgroundColor3 = "InputColor", TextColor3 = "ValueColor" })
                Corner(hex, 6)
                Stroke(hex, "InputBorder")
                local preview = Create("Frame", { Position = UDim2.fromOffset(142, 196), Size = UDim2.fromOffset(76, 28), BorderSizePixel = 0, Parent = frame })
                Corner(preview, 6)

                local function sync()
                    sv.BackgroundColor3 = Color3.fromHSV(CP.Hue, 1, 1)
                    svCursor.Position = UDim2.fromScale(CP.Sat, 1 - CP.Vib)
                    hueCursor.Position = UDim2.new(0.5, 0, CP.Hue, 0)
                    preview.BackgroundColor3 = CP.Value
                    if not hex:IsFocused() then hex.Text = "#" .. string.upper(CP.Value:ToHex()) end
                end
                CP._Sync = sync
                sync()

                local function rel(gui, pos)
                    local a, s = gui.AbsolutePosition, gui.AbsoluteSize
                    return math.clamp((pos.X - a.X) / math.max(s.X, 1), 0, 1), math.clamp((pos.Y - a.Y) / math.max(s.Y, 1), 0, 1)
                end
                sv.InputBegan:Connect(function(input)
                    if not IsClick(input) then return end
                    BeginDrag(input, function(pos)
                        local x, y = rel(sv, pos)
                        CP:SetHSV(CP.Hue, x, 1 - y)
                    end)
                    ActiveDrag.Popup = popup
                end)
                hue.InputBegan:Connect(function(input)
                    if not IsClick(input) then return end
                    BeginDrag(input, function(pos)
                        local _, y = rel(hue, pos)
                        CP:SetHSV(math.min(y, 0.999), CP.Sat, CP.Vib)
                    end)
                    ActiveDrag.Popup = popup
                end)
                hex.FocusLost:Connect(function()
                    local h = string.match(hex.Text, "^#?(%x%x%x%x%x%x)$")
                    if h then CP:SetValueRGB(Color3.fromHex(h)) else sync() end
                end)

                return function() CP._Sync = nil end
            end)
        end)

        CP:Display()
        if idx then Options[idx] = CP end
        return CP
    end

    --------------------------------------------------------
    -- key picker (поле как у значения слайдера)
    --------------------------------------------------------
    local function NewKeyPicker(idx, info, parent, order)
        info = info or {}
        local KP = {
            Type = "KeyPicker", Value = info.Default or "None", Mode = info.Mode or "Toggle",
            Changed = {}, Callback = info.ChangedCallback or info.Callback, Text = info.Text,
        }
        local btn, label = ValueBox(parent, order, true)

        function KP:Display() label.Text = self._Picking and "..." or tostring(self.Value) end
        function KP:OnChanged(fn) table.insert(self.Changed, fn) end
        function KP:SetValue(data)
            if type(data) == "table" then
                self.Value = data[1] or self.Value
                self.Mode = data[2] or self.Mode
            elseif data ~= nil then
                self.Value = tostring(data)
            end
            self:Display()
            Fire(self)
        end

        btn.MouseButton1Click:Connect(function()
            if KP._Picking then return end
            KP._Picking = true
            Library._Binding = true
            KP:Display()
            local conn
            conn = UIS.InputBegan:Connect(function(input)
                local key
                if input.UserInputType == KB then
                    key = input.KeyCode.Name
                    if key == "Escape" then key = KP.Value end
                    if key == "Backspace" then key = "None" end
                elseif input.UserInputType == MB2 then
                    key = "MB2"
                elseif input.UserInputType == MB1 or input.UserInputType == TOUCH then
                    key = KP.Value -- клик мимо = отмена
                else
                    return
                end
                conn:Disconnect()
                KP._Picking = false
                task.defer(function() Library._Binding = false end)
                KP:SetValue(key)
            end)
        end)

        KP:Display()
        if idx then Options[idx] = KP end
        return KP
    end

    --------------------------------------------------------
    -- БИНДЫ (как у NL): ПКМ по любому переключателю -> клавиша и режим Toggle / Hold / Always.
    -- Library.Binds[idx] = { Key = "F", Mode = "Toggle" }; сохраняются в конфиг (SaveManager).
    --------------------------------------------------------
    Library.Binds = {}
    local BIND_MODES = { "Toggle", "Hold", "Always" }
    local BindMarks = {} -- [idx] = подпись клавиши в строке переключателя

    local function InputKeyName(input)
        if input.UserInputType == KB then return input.KeyCode.Name end
        if input.UserInputType == MB2 then return "MB2" end
        if input.UserInputType == Enum.UserInputType.MouseButton3 then return "MB3" end
        return nil
    end

    local function ShortKey(k)
        local map = { LeftShift = "LShift", RightShift = "RShift", LeftControl = "LCtrl", RightControl = "RCtrl",
            LeftAlt = "LAlt", RightAlt = "RAlt", CapsLock = "Caps" }
        return map[k] or tostring(k)
    end

    function Library:SetBind(idx, key, mode)
        local T = Toggles[idx]
        if not T then return end
        if key == nil or key == "None" or key == "" then
            Library.Binds[idx] = nil
        else
            local m = table.find(BIND_MODES, mode) and mode or "Toggle"
            Library.Binds[idx] = { Key = tostring(key), Mode = m }
            if m == "Always" and not T.Value then T:SetValue(true) end
        end
        local b = Library.Binds[idx]
        local mark = BindMarks[idx]
        if b and not mark and T.Right then
            mark = Text({ Text = "", TextSize = 12, ColorKey = "DimColor", Size = UDim2.fromOffset(0, 20), AutomaticSize = AX,
                LayoutOrder = 99, Parent = T.Right })
            BindMarks[idx] = mark
        end
        if mark then
            mark.Visible = b ~= nil
            mark.Text = b and ("[" .. ShortKey(b.Key) .. "]") or ""
        end
        if Library.KeybindList then Library.KeybindList:Refresh() end
    end

    function Library:ClearBinds()
        for idx in pairs(Library.Binds) do Library:SetBind(idx, nil) end
    end

    -- клавиши: Toggle - переключить, Hold - включено, пока держишь
    Connect(UIS.InputBegan, function(input)
        if Library.Unloaded or Library._Binding then return end
        if UIS:GetFocusedTextBox() then return end
        local name = InputKeyName(input)
        if not name then return end
        for idx, b in pairs(Library.Binds) do
            local T = Toggles[idx]
            if T and b.Key == name then
                if b.Mode == "Toggle" then T:SetValue(not T.Value)
                elseif b.Mode == "Hold" then b.Held = true T:SetValue(true) end
            end
        end
    end)
    Connect(UIS.InputEnded, function(input)
        if Library.Unloaded then return end
        local name = InputKeyName(input)
        if not name then return end
        for idx, b in pairs(Library.Binds) do
            local T = Toggles[idx]
            if T and b.Key == name and b.Mode == "Hold" and b.Held then
                b.Held = false
                T:SetValue(false)
            end
        end
    end)

    -- окно настройки бинда (ПКМ по строке)
    local function OpenBindPopup(anchor, idx, title)
        local cur = Library.Binds[idx]
        local key, mode = cur and cur.Key or "None", cur and cur.Mode or "Toggle"
        OpenPopup(anchor, 240, 116, function(frame)
            Text({ Text = tostring(title or idx), TextSize = 13, FontFace = F(W_SEMI), Position = UDim2.fromOffset(ROW_PAD, 6),
                Size = UDim2.new(1, -ROW_PAD * 2, 0, 22), ClipsDescendants = true, Parent = frame })
            local function row(y, text)
                local r = Create("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Parent = frame })
                local line = Create("Frame", { Position = UDim2.fromOffset(SEP_INSET, 0), Size = UDim2.new(1, -SEP_INSET * 2, 0, 1), BorderSizePixel = 0, Parent = r })
                Theme(line, { BackgroundColor3 = "SeparatorColor" })
                Text({ Text = text, TextSize = 13, FontFace = F(W_REG), Position = UDim2.fromOffset(ROW_PAD, 0), Size = UDim2.new(0, 60, 1, 0), Parent = r })
                local right = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -ROW_PAD + 4, 0.5, 0),
                    Size = UDim2.fromOffset(0, 24), AutomaticSize = AX, BackgroundTransparency = 1, Parent = r })
                List(right, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
                return right
            end
            -- клавиша: клик -> "..." -> следующая клавиша; Backspace - убрать, Esc - отмена
            local kbtn, klabel = ValueBox(row(36, "Key"), 1, true)
            local function showKey() klabel.Text = key == "None" and "None" or ShortKey(key) end
            showKey()
            local listening
            kbtn.MouseButton1Click:Connect(function()
                if listening then return end
                Library._Binding = true
                klabel.Text = "..."
                listening = UIS.InputBegan:Connect(function(input)
                    local k
                    if input.UserInputType == KB then
                        k = input.KeyCode.Name
                        if k == "Escape" then k = key elseif k == "Backspace" then k = "None" end
                    elseif input.UserInputType == MB1 or input.UserInputType == TOUCH then
                        k = key
                    else
                        k = InputKeyName(input)
                        if not k then return end
                    end
                    listening:Disconnect()
                    listening = nil
                    task.defer(function() Library._Binding = false end)
                    key = k
                    showKey()
                    Library:SetBind(idx, key, mode)
                end)
            end)
            -- режим: три кнопки, выбранная - на подложке
            local modeRow = row(74, "Mode")
            local btns = {}
            local function paint()
                for m, b in pairs(btns) do
                    b.Button.BackgroundTransparency = (m == mode) and 0 or 1
                    b.Label.TextColor3 = (m == mode) and Scheme.FontColor or Scheme.SubColor
                end
            end
            for i, m in ipairs(BIND_MODES) do
                local b = Button({ Size = UDim2.fromOffset(0, 22), AutomaticSize = AX, LayoutOrder = i, Parent = modeRow })
                Theme(b, { BackgroundColor3 = "ItemColor" })
                Corner(b, 5)
                Pad(b, 7, 7, 0, 0)
                local l = Text({ Text = m, TextSize = 12, ColorKey = false, Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = b })
                btns[m] = { Button = b, Label = l }
                b.MouseButton1Click:Connect(function()
                    mode = m
                    paint()
                    if key ~= "None" then Library:SetBind(idx, key, mode) end
                end)
            end
            paint()
            return function()
                if listening then listening:Disconnect() listening = nil Library._Binding = false end
            end
        end)
    end

    local DetachedGroup, OpenSettings, DotsButton -- AMBIENCE: определены ниже, после Group
    local function AddonMixin(obj)
        -- AMBIENCE: «...» справа в строке, открывает мини-панель доп. настроек (как у NL у Override DoF).
        -- build(group) вызывается один раз: элементы живут всё время (их значения сохраняются в конфиг),
        -- а в popup панель только «одалживается» на время показа.
        function obj:AddSettings(info)
            info = info or {}
            local g = DetachedGroup()
            Safe(info.Build, g)
            local dots = DotsButton(self.Right, #self.Addons + 1)
            dots.MouseButton1Click:Connect(function() OpenSettings(dots, g, info.Title, info.Width) end)
            table.insert(self.Addons, dots)
            self.SettingsGroup = g
            return self
        end
        function obj:AddColorPicker(idx, info)
            table.insert(self.Addons, NewColorPicker(idx, info, self.Right, #self.Addons + 1))
            return self
        end
        function obj:AddKeyPicker(idx, info)
            table.insert(self.Addons, NewKeyPicker(idx, info, self.Right, #self.Addons + 1))
            return self
        end
    end

    --------------------------------------------------------
    -- groupbox (секция): строки 38px, разделитель с отступом 7
    --------------------------------------------------------
    local Group = {}
    Group.__index = Group

    function Group:_Row(height, tooltip, searchText, clickable)
        self.Count += 1
        local row
        if clickable then
            row = Button({ Size = UDim2.new(1, 0, 0, height), LayoutOrder = self.Count, Parent = self.Panel })
        else
            row = Create("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = self.Count, Parent = self.Panel })
        end
        if self.Rows > 0 and not self.AfterDivider then
            local line = Create("Frame", {
                Position = UDim2.fromOffset(SEP_INSET, 0), Size = UDim2.new(1, -SEP_INSET * 2, 0, 1),
                BorderSizePixel = 0, Parent = row,
            })
            Theme(line, { BackgroundColor3 = "SeparatorColor" })
        end
        self.Rows += 1
        self.AfterDivider = false
        AttachTooltip(row, tooltip)
        table.insert(self.Page.Rows, { Row = row, Group = self, Text = string.lower(tostring(searchText or "")) })
        return row
    end

    function Group:AddCheckbox(idx, info)
        info = info or {}
        local row = self:_Row(ROW_H, info.Tooltip, info.Text, true)
        local label = RowLabel(row, info.Text or idx)
        local right = RightBox(row)
        local track, knob = Switch(right, 100)
        FitLabel(label, right)

        local T = {
            Type = "Toggle", Value = info.Default == true, Changed = {}, Callback = info.Callback,
            Text = info.Text, Row = row, Right = right, Addons = {}, BindIcon = info.BindIcon,
        }
        function T:Display(instant)
            PaintSwitch(track, knob, self.Value, instant)
            -- [v45] как в NL: подпись выключенной функции серее
            local dim = Library.Style and Library.Style.DimOff and not self.Value
            label.TextColor3 = dim and Scheme.SubColor or Scheme.FontColor
        end
        function T:OnChanged(fn) table.insert(self.Changed, fn) end
        function T:SetValue(v)
            self.Value = v == true
            self:Display()
            Fire(self)
        end
        AddonMixin(T)
        row.MouseButton1Click:Connect(function() T:SetValue(not T.Value) end)
        -- БИНДЫ: ПКМ по строке -> клавиша и режим (кроме служебных переключателей меню)
        if idx and not info.NoBind then
            row.MouseButton2Click:Connect(function() OpenBindPopup(right, idx, info.Text or idx) end)
        end
        Library:AddRefresh(function() T:Display(true) end)

        if idx then Toggles[idx] = T end
        return T
    end
    Group.AddToggle = Group.AddCheckbox

    -- слайдер в строку: [подпись] .... [====o-----] [ 58 ]
    function Group:AddSlider(idx, info)
        info = info or {}
        local row = self:_Row(ROW_H, info.Tooltip, info.Text, false)
        local label = RowLabel(row, info.Text or idx)
        local right = RightBox(row)
        right:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 7)

        local S = {
            Type = "Slider", Min = info.Min or 0, Max = info.Max or 100, Rounding = info.Rounding or 0,
            Suffix = info.Suffix or "", Changed = {}, Callback = info.Callback,
        }
        S.Value = math.clamp(Round(info.Default or S.Min, S.Rounding), S.Min, S.Max)

        local hit = Button({ Size = UDim2.fromOffset(TRACK_W, 18), LayoutOrder = 1, Parent = right })
        local bar = Create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 4),
            BorderSizePixel = 0, Parent = hit,
        })
        Theme(bar, { BackgroundColor3 = "TrackColor" })
        Corner(bar, 2)
        local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, Parent = bar })
        Theme(fill, { BackgroundColor3 = "AccentColor" })
        Corner(fill, 2)
        local knob = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 2, Parent = hit,
        })
        Corner(knob, 5)
        local _, valueLabel = ValueBox(right, 2, false)
        FitLabel(label, right)

        local function fmt(v)
            local s = S.Rounding > 0 and string.format("%." .. S.Rounding .. "f", v) or tostring(math.floor(v + 0.5))
            return s .. S.Suffix
        end
        function S:Display()
            local range = self.Max - self.Min
            local a = range ~= 0 and (self.Value - self.Min) / range or 0
            fill.Size = UDim2.fromScale(a, 1)
            knob.Position = UDim2.fromScale(a, 0.5)
            valueLabel.Text = fmt(self.Value)
        end
        function S:OnChanged(fn) table.insert(self.Changed, fn) end
        function S:SetValue(v)
            v = tonumber(v)
            if not v then return end
            v = math.clamp(Round(v, self.Rounding), self.Min, self.Max)
            if v == self.Value then self:Display() return end
            self.Value = v
            self:Display()
            Fire(self)
        end
        function S:SetMin(v) self.Min = v self:SetValue(self.Value) end
        function S:SetMax(v) self.Max = v self:SetValue(self.Value) end

        hit.InputBegan:Connect(function(input)
            if not IsClick(input) then return end
            BeginDrag(input, function(pos)
                local a = math.clamp((pos.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
                S:SetValue(S.Min + (S.Max - S.Min) * a)
            end)
        end)

        S:Display()
        if idx then Options[idx] = S end
        return S
    end

    function Group:AddLabel(text, wrap)
        if type(text) == "table" then
            wrap = text.DoesWrap
            text = text.Text
        end
        text = tostring(text or "")
        local L = { Addons = {} }
        local row, label
        if wrap then
            row = self:_Row(0, nil, text, false)
            row.AutomaticSize = AY
            label = Text({
                Text = text, TextSize = 13, FontFace = F(W_REG), ColorKey = "SubColor", TextWrapped = true,
                Position = UDim2.fromOffset(ROW_PAD, 0), Size = UDim2.new(1, -ROW_PAD * 2, 0, 0), AutomaticSize = AY, Parent = row,
            })
            Pad(label, 0, 0, 11, 11)
        else
            row = self:_Row(ROW_H, nil, text, false)
            label = RowLabel(row, text)
        end
        L.Row = row
        L.Right = RightBox(row)
        if not wrap then FitLabel(label, L.Right) end
        function L:SetText(t) label.Text = tostring(t) end
        AddonMixin(L)
        return L
    end

    -- разделитель внутри секции: полоса на всю ширину панели
    function Group:AddDivider()
        self.Count += 1
        local d = Create("Frame", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, LayoutOrder = self.Count, Parent = self.Panel })
        local line = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = d })
        Theme(line, { BackgroundColor3 = "OutlineColor" })
        self.AfterDivider = true
    end

    -- кнопка = строка со стрелкой ">" (как "View Options >")
    function Group:AddButton(info, func)
        if type(info) == "string" then info = { Text = info, Func = func } end
        info = info or {}
        local row = self:_Row(ROW_H, info.Tooltip, info.Text, true)
        local label = RowLabel(row, info.Text)
        label.Size = UDim2.new(1, -ROW_PAD * 2 - 16, 1, 0)
        Arrow(row)
        row.MouseEnter:Connect(function() label.TextColor3 = Scheme.AccentColor end)
        row.MouseLeave:Connect(function() label.TextColor3 = Scheme.FontColor end)
        local B = { Row = row, Label = label, Text = tostring(info.Text or "") }
        local armed = 0
        row.MouseButton1Click:Connect(function()
            label.TextColor3 = WHITE
            Tween(label, 0.3, { TextColor3 = Scheme.AccentColor })
            -- [v94] info.Confirm (как в SkeetUI): первый клик - «Are you sure?», второй в течение 3 с - выполняет
            if info.Confirm and Library.Confirmations ~= false and os.clock() > armed then
                armed = os.clock() + 3
                label.Text = "Are you sure?"
                task.delay(3, function() if os.clock() >= armed then label.Text = B.Text end end)
                return
            end
            armed = 0
            label.Text = B.Text
            Safe(info.Func or info.Callback)
        end)
        local group = self
        function B:AddButton(...) return group:AddButton(...) end
        function B:SetText(t) self.Text = tostring(t) label.Text = self.Text end -- [v94]
        return B
    end

    function Group:AddInput(idx, info)
        info = info or {}
        local row = self:_Row(ROW_H, info.Tooltip, info.Text, false)
        RowLabel(row, info.Text or idx).Size = UDim2.new(1, -ROW_PAD * 2 - CTRL_W - 8, 1, 0)
        local I = { Type = "Input", Value = tostring(info.Default or ""), Changed = {}, Callback = info.Callback }
        local box = FieldFrame("TextBox", row)
        box.ClearTextOnFocus = false
        box.FontFace = F(W_REG)
        box.TextSize = 13
        box.Text = I.Value
        box.PlaceholderText = info.Placeholder or ""
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClipsDescendants = true
        Theme(box, { TextColor3 = "ValueColor", PlaceholderColor3 = "DimColor" })
        Pad(box, 9, 9, 0, 0)
        function I:OnChanged(fn) table.insert(self.Changed, fn) end
        function I:SetValue(v)
            self.Value = tostring(v or "")
            if box.Text ~= self.Value then box.Text = self.Value end
            Fire(self)
        end
        box:GetPropertyChangedSignal("Text"):Connect(function()
            if box.Text ~= I.Value then I:SetValue(box.Text) end
        end)
        if idx then Options[idx] = I end
        return I
    end

    function Group:AddDropdown(idx, info)
        info = info or {}
        local row = self:_Row(ROW_H, info.Tooltip, info.Text, false)
        local rowLabel = RowLabel(row, info.Text or idx)
        rowLabel.Size = UDim2.new(1, -ROW_PAD * 2 - CTRL_W - 8, 1, 0)
        local D = { Type = "Dropdown", Values = info.Values or {}, Value = info.Default, Changed = {}, Callback = info.Callback, Multi = info.Multi == true }
        if type(D.Value) == "number" then D.Value = D.Values[D.Value] end
        -- AMBIENCE: Multi = true - значение-таблица { [вариант] = true }, как в Obsidian
        local function toSet(v)
            local set = {}
            if type(v) == "table" then
                for k, x in pairs(v) do
                    if type(k) == "number" then set[x] = true elseif x then set[k] = true end
                end
            elseif v ~= nil then
                set[v] = true
            end
            return set
        end
        if D.Multi then D.Value = toSet(D.Value) end

        local btn = FieldFrame("TextButton", row)
        local label = Text({
            Text = "", TextSize = 13, FontFace = F(W_REG), ColorKey = "ValueColor", Position = UDim2.fromOffset(9, 0),
            Size = UDim2.new(1, -30, 1, 0), ClipsDescendants = true, Parent = btn,
        })
        Chevron(btn)
        -- ESP: место под аддоны (цвет) слева от поля, как у NL «Player [цвет] [Glow v]»
        local addons = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -ROW_PAD - CTRL_W - 8, 0.5, 0),
            Size = UDim2.fromOffset(0, 24), AutomaticSize = AX, BackgroundTransparency = 1, Parent = row,
        })
        List(addons, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
        D.Right, D.Addons = addons, {}
        AddonMixin(D)
        FitLabel(rowLabel, addons, CTRL_W + 16)

        function D:Display()
            if self.Multi then
                local parts = {}
                for _, v in ipairs(self.Values) do if self.Value[v] then table.insert(parts, tostring(v)) end end
                label.Text = #parts > 0 and table.concat(parts, ", ") or "Select"
            else
                label.Text = self.Value ~= nil and tostring(self.Value) or "Select"
            end
        end
        function D:OnChanged(fn) table.insert(self.Changed, fn) end
        function D:SetValues(v) self.Values = v or {} self:Display() end
        function D:SetValue(v)
            self.Value = self.Multi and toSet(v) or v
            self:Display()
            Fire(self)
        end
        btn.MouseButton1Click:Connect(function()
            if D.Multi then
                OpenMultiList(btn, D.Values, function(v) return D.Value[v] == true end, function(v)
                    local set = table.clone(D.Value)
                    set[v] = (not set[v]) or nil
                    D:SetValue(set)
                end)
            else
                OpenList(btn, D.Values, D.Value, function(v) D:SetValue(v) end)
            end
        end)

        D:Display()
        if idx then Options[idx] = D end
        return D
    end

    --------------------------------------------------------
    -- AMBIENCE: служебные элементы для панелей настроек (NL World > Ambience)
    --------------------------------------------------------
    local Storage = Create("Frame", { Name = "Storage", Visible = false, Size = UDim2.fromOffset(260, 0), Parent = ScreenGui })

    -- секция без страницы: её элементы живут в скрытом хранилище, пока панель не показана
    DetachedGroup = function()
        local G = setmetatable({ Page = { Groups = {}, Rows = {} }, Name = "", Count = 0, Rows = 0 }, Group)
        local panel = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = Storage })
        List(panel)
        G.Panel, G.Holder = panel, panel
        return G
    end

    -- popup с «одолженной» секцией
    OpenSettings = function(anchor, G, title, width)
        local head = title and 32 or 4
        local h = head + G.Rows * ROW_H + 4
        OpenPopup(anchor, width or 270, h, function(frame, _, p)
            if title then
                Text({ Text = tostring(title), TextSize = 13, FontFace = F(W_SEMI), Position = UDim2.fromOffset(ROW_PAD, 6), Size = UDim2.new(1, -ROW_PAD * 2, 0, 22), Parent = frame })
            end
            G.Panel.Position = UDim2.fromOffset(0, head)
            G.Panel.Parent = frame
            p.Late = function() if G.Panel.Parent ~= nil then G.Panel.Parent = Storage end end
            return nil
        end)
    end

    -- «...» (три точки 3px), как у NL справа в строке
    DotsButton = function(parent, order)
        local b = Button({ Size = UDim2.fromOffset(18, 18), LayoutOrder = order, Parent = parent })
        local dots = {}
        for i = -1, 1 do
            local d = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 5, 0.5, 0), Size = UDim2.fromOffset(3, 3), BorderSizePixel = 0, Parent = b })
            Corner(d, 2)
            Theme(d, { BackgroundColor3 = "ValueColor" })
            table.insert(dots, d)
        end
        b.MouseEnter:Connect(function() for _, d in ipairs(dots) do d.BackgroundColor3 = Scheme.AccentColor end end)
        b.MouseLeave:Connect(function() for _, d in ipairs(dots) do d.BackgroundColor3 = Scheme.ValueColor end end)
        return b
    end

    -- ESP: кнопки-переключатели (ESP Items у NL). Каждая кнопка - обычный Toggle (Toggles[idx]),
    -- просто нарисованный чипом: конфиги, OnChanged и фичи работают как с чекбоксом.
    function Group:AddChips(info)
        info = info or {}
        local row = self:_Row(0, nil, info.Text or "", false)
        row.AutomaticSize = AY
        local wrap = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = row })
        Pad(wrap, ROW_PAD - 3, ROW_PAD - 3, 8, 10)
        List(wrap, nil, 6)
        if info.Title then
            Text({ Text = tostring(info.Title), TextSize = 12, ColorKey = "DimColor", Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0, Parent = wrap })
        end
        local holder = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, LayoutOrder = 1, Parent = wrap })
        local layout = List(holder, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
        pcall(function() layout.Wraps = true end) -- перенос на следующую строку
        local hidden = DetachedGroup()
        local C = { Toggles = {} }
        for i, it in ipairs(info.Items or {}) do
            local T = hidden:AddCheckbox(it.Idx, { Text = it.Text, Default = it.Default == true, Tooltip = it.Tooltip })
            C.Toggles[it.Idx] = T
            local chip = Button({ Size = UDim2.fromOffset(0, 24), AutomaticSize = AX, LayoutOrder = i, Parent = holder })
            Theme(chip, { BackgroundColor3 = "ItemColor" })
            Corner(chip, 6)
            Pad(chip, 9, 9, 0, 0)
            local lbl = Text({ Text = tostring(it.Text), TextSize = 13, ColorKey = false, Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = chip })
            local function paint(instant)
                local on = T.Value
                if instant == true or not Library.Animations then chip.BackgroundTransparency = on and 0 or 1
                else Anim(chip, T_NAV, { BackgroundTransparency = on and 0 or 1 }) end
                lbl.TextColor3 = on and Scheme.FontColor or Scheme.SubColor
            end
            T:OnChanged(function() paint() end)
            paint(true)
            Library:AddRefresh(function() paint(true) end)
            chip.MouseButton1Click:Connect(function() T:SetValue(not T.Value) end)
            chip.MouseButton2Click:Connect(function() OpenBindPopup(chip, it.Idx, it.Text) end) -- БИНДЫ
            AttachTooltip(chip, it.Tooltip)
        end
        return C
    end

    -- SKINCHANGER: картинка (превью аватара) на всю ширину секции
    function Group:AddImage(info)
        info = info or {}
        local h = info.Height or 200
        local row = self:_Row(h + 20, nil, info.Text or "", false)
        local box = Create("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20), BorderSizePixel = 0, Parent = row })
        Theme(box, { BackgroundColor3 = "InputColor" })
        Corner(box, 10)
        Stroke(box, "InputBorder")
        local img = Create("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Parent = box })
        local hint = Text({ Text = tostring(info.Placeholder or "No preview"), TextSize = 13, ColorKey = "DimColor",
            TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = box })
        local I = { Row = row, Image = img }
        -- SKINCHANGER: 3D-превью поверх картинки. ЛКМ - крутить, колесо - приблизить,
        -- без касания модель медленно вращается сама.
        local vp = Create("ViewportFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Active = true,
            Ambient = Color3.fromRGB(170, 170, 180), LightColor = Color3.fromRGB(255, 255, 255), LightDirection = Vector3.new(-0.6, -1, -0.8),
            Parent = box,
        })
        local world = Create("WorldModel", { Parent = vp })
        -- ESP: прозрачный слой поверх 3D - на нём рисуется ESP превью; он же ловит мышь
        local overlay = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = true,
            ClipsDescendants = true, Visible = false, ZIndex = 3, Parent = box })
        local cam = Create("Camera", { FieldOfView = 40, Parent = vp })
        pcall(function() vp.CurrentCamera = cam end)
        local view = { Model = nil, Center = Vector3.new(), Rot = CFrame.new(), Dist = 8, MinD = 3, MaxD = 20, Yaw = 0, Pitch = 0.08, Touched = 0 }
        local function place()
            if not view.Model then return end
            pcall(function()
                cam.CFrame = CFrame.new(view.Center) * view.Rot * CFrame.Angles(0, math.pi + view.Yaw, 0)
                    * CFrame.Angles(-view.Pitch, 0, 0) * CFrame.new(0, 0, view.Dist)
            end)
        end
        I.View = view
        I.Overlay, I.Viewport, I.Camera, I.Box = overlay, vp, cam, box
        function I:SetModel(model)
            if view.Model and view.Model ~= model then pcall(function() view.Model:Destroy() end) end
            view.Model = model
            -- ФИКС: картинка - только запасной вариант; при 3D-модели она скрыта
            if not model then vp.Visible = false overlay.Visible = false img.Visible = true hint.Visible = img.Image == "" return end
            img.Visible = false
            overlay.Visible = true
            model.Parent = world
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            local okB, cf, size = pcall(function() return model:GetBoundingBox() end)
            if okB and cf and size then
                view.Center = cf.Position
                local maxDim = math.max(size.X, size.Y, size.Z)
                view.Dist = (maxDim / 2) / math.tan(math.rad(20)) * 1.15
            elseif root then
                view.Center = root.Position
                view.Dist = 8
            end
            view.MinD, view.MaxD = view.Dist * 0.4, view.Dist * 2.5
            local okR, rot = pcall(function() return root.CFrame.Rotation end)
            view.Rot = (okR and rot) or CFrame.new()
            view.Yaw, view.Pitch = 0, 0.08
            vp.Visible = true
            hint.Visible = false
            place()
        end
        function I:GetWorld() return world end
        local function onBegan(input)
            if not IsClick(input) or not view.Model then return end
            local last = V2(input.Position)
            view.Touched = os.clock()
            BeginDrag(input, function(pos)
                local d = pos - last
                last = pos
                view.Yaw -= d.X * 0.012
                view.Pitch = math.clamp(view.Pitch + d.Y * 0.008, -0.7, 0.7)
                view.Touched = os.clock()
                place()
            end)
        end
        local function onWheel(input)
            if input.UserInputType ~= Enum.UserInputType.MouseWheel or not view.Model then return end
            local z = input.Position and input.Position.Z or 0
            view.Dist = math.clamp(view.Dist * (z > 0 and 0.9 or 1.1), view.MinD, view.MaxD)
            view.Touched = os.clock()
            place()
        end
        vp.InputBegan:Connect(onBegan)
        vp.InputChanged:Connect(onWheel)
        overlay.InputBegan:Connect(onBegan)
        overlay.InputChanged:Connect(onWheel)
        Connect(RunService.RenderStepped, function(dt)
            if not view.Model or not vp.Visible then return end
            if os.clock() - view.Touched > 3 then -- автоповорот, пока не трогаешь
                view.Yaw += (dt or 0.016) * 0.5
                place()
            end
        end)
        function I:SetImage(id)
            img.Image = tostring(id or "")
            img.Visible = not vp.Visible
            hint.Visible = img.Image == "" and not vp.Visible
        end
        function I:SetHint(t) hint.Text = tostring(t or "") end
        return I
    end

    -- строка с «>» (как Weather у NL): открывает панель настроек
    function Group:AddSubmenu(text, info)
        info = info or {}
        local g = DetachedGroup()
        Safe(info.Build, g)
        local row = self:_Row(ROW_H, info.Tooltip, text, true)
        local label = RowLabel(row, text)
        label.Size = UDim2.new(1, -ROW_PAD * 2 - 16, 1, 0)
        local arrow = Arrow(row)
        row.MouseEnter:Connect(function() label.TextColor3 = Scheme.AccentColor end)
        row.MouseLeave:Connect(function() label.TextColor3 = Scheme.FontColor end)
        row.MouseButton1Click:Connect(function() OpenSettings(arrow, g, info.Title or text, info.Width) end)
        return { Row = row, SettingsGroup = g }
    end

    -- список-выбор (Map Selection у NL): строка выделена рамкой, справа «...» или «Add»
    -- info.Items() -> { { Name, Text, Added, Selected } }, info.OnSelect(name), info.OnAdd(name), info.Menu(name) -> { {Text, Func} }
    function Group:AddSelectList(info)
        info = info or {}
        local row = self:_Row(0, nil, "", false)
        row.AutomaticSize = AY
        local holder = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = row })
        Pad(holder, 6, 6, 6, 6)
        List(holder, nil, 6)
        local SL = {}
        function SL:Refresh()
            for _, c in ipairs(holder:GetChildren()) do if c:IsA("GuiButton") then c:Destroy() end end
            local items = {}
            pcall(function() items = info.Items() or {} end)
            for i, it in ipairs(items) do
                local b = Button({ BackgroundTransparency = it.Selected and 0 or 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, Parent = holder })
                Theme(b, { BackgroundColor3 = "ItemColor" })
                Corner(b, 8)
                local st = Stroke(b, "InputBorder")
                st.Transparency = it.Selected and 0 or 1
                Text({ Text = tostring(it.Text or it.Name), TextSize = 14, ColorKey = it.Selected and "FontColor" or "ValueColor",
                    Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -80, 1, 0), ClipsDescendants = true, Parent = b })
                local right = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(0, 22),
                    AutomaticSize = AX, BackgroundTransparency = 1, Parent = b })
                List(right, Enum.FillDirection.Horizontal, 4, nil, Enum.VerticalAlignment.Center)
                if it.Added then
                    local dots = DotsButton(right, 1)
                    dots.MouseButton1Click:Connect(function()
                        local acts = {}
                        pcall(function() acts = info.Menu(it.Name) or {} end)
                        local names = {}
                        for _, a in ipairs(acts) do table.insert(names, a.Text) end
                        OpenList(dots, names, nil, function(v)
                            for _, a in ipairs(acts) do if a.Text == v then Safe(a.Func) end end
                            SL:Refresh()
                        end)
                    end)
                else
                    local add = Button({ Size = UDim2.fromOffset(0, 22), AutomaticSize = AX, LayoutOrder = 1, Parent = right })
                    Pad(add, 6, 6, 0, 0)
                    Text({ Text = "+ Add", TextSize = 13, ColorKey = "ValueColor", Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = add })
                    add.MouseButton1Click:Connect(function()
                        Safe(info.OnAdd, it.Name)
                        SL:Refresh()
                    end)
                end
                b.MouseButton1Click:Connect(function()
                    Safe(info.OnSelect, it.Name)
                    SL:Refresh()
                end)
            end
        end
        SL:Refresh()
        return SL
    end

    --------------------------------------------------------
    -- window 800x613: сайдбар 169 | шапка 54 | две колонки секций
    --------------------------------------------------------
    function Library:CreateWindow(info)
        info = info or {}
        local W, H, SIDE, HEAD = 800, 613, 169, 54
        local title = tostring(info.Title or "Menu")
        local Window = { Tabs = {}, Active = nil }
        Library.Window = Window

        -- Main - прозрачная рамка (ловит клики, масштаб, позиция при драге).
        -- АНИМАЦИЯ: фон/обводка и всё содержимое перенесены в Body, чтобы окно
        -- целиком плавно проявлялось (Body на время анимации уходит в CanvasGroup).
        local Main = Button({
            Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
            Visible = info.AutoShow ~= false, Parent = ScreenGui,
        })
        local Body = Create("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = Main })
        Theme(Body, { BackgroundColor3 = "MainColor" })
        Corner(Body, 16)
        Stroke(Body, "OutlineColor")
        Shadow(Body, 16) -- ЭФФЕКТ: тень ~0.4 у края, гаснет за ~9px (замер со скринов)
        local Scale = Create("UIScale", { Parent = Main })
        Library._UIScale = Scale
        local fitScale, zoom = 1, 1
        Library.MenuScale = Library.MenuScale or 1
        -- [v43] Menu Scale из попапа - отдельный множитель, анимация открытия (zoom) его больше не затирает
        local function applyScale() Scale.Scale = fitScale * zoom * (Library.MenuScale or 1) end
        function Library:SetMenuScale(v)
            Library.MenuScale = math.clamp(tonumber(v) or 1, 0.5, 2)
            applyScale()
            if Library._ThemeSave then Library._ThemeSave() end
        end
        local function rescale()
            local vp = ScreenGui.AbsoluteSize
            if vp.X <= 0 then return end
            fitScale = math.clamp(math.min((vp.X - 24) / W, (vp.Y - 24) / H), 0.45, 1)
            applyScale()
        end
        rescale()
        Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), rescale)
        -- масштаб открытия (0.97 -> 1) твинится через NumberValue, чтобы не ломать подгонку под экран
        local ZoomValue = Create("NumberValue", { Value = 1 })
        Connect(ZoomValue:GetPropertyChangedSignal("Value"), function() zoom = ZoomValue.Value applyScale() end)

        -- сайдбар
        local Side = Create("Frame", { Size = UDim2.new(0, SIDE, 1, 0), BorderSizePixel = 0, Parent = Body })
        Theme(Side, { BackgroundColor3 = "BackgroundColor" })
        Corner(Side, 16)
        local patch = Create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 16, 1, 0), BorderSizePixel = 0, Parent = Side })
        Theme(patch, { BackgroundColor3 = "BackgroundColor" })
        -- ЭФФЕКТ: прозрачность окна. Слои полупрозрачных рамок складываются и окно
        -- становится непрозрачным, поэтому при прозрачности сайдбар без своего фона
        -- (его цвет почти совпадает с основным: #0b0e18 против #0d0e16).
        Library:AddRefresh(function()
            local t = math.clamp(Library.Transparency or 0, 0, 0.9)
            Body.BackgroundTransparency = t
            -- [v45] тема со своим цветом сайдбара (Classic): рисуем его и при прозрачности окна
            local own = Library.Style and Library.Style.SideOwn
            Side.BackgroundTransparency = (t > 0 and not own) and 1 or (own and t or 0)
            patch.BackgroundTransparency = (t > 0 and not own) and 1 or (own and t or 0)
        end)
        local sideLine = Create("Frame", { Position = UDim2.fromOffset(SIDE, 0), Size = UDim2.new(0, 1, 1, 0), BorderSizePixel = 0, Parent = Body })
        Theme(sideLine, { BackgroundColor3 = "OutlineColor" })

        -- логотип: [бейдж] Название / подпись, по центру сайдбара
        local initials = info.Logo or string.upper((title:gsub("(%w)%w*%s*", "%1"))):sub(1, 2)
        Library.LogoText = initials -- УВЕДОМЛЕНИЯ: тот же бейдж, что в логотипе
        local Logo = Create("Frame", { Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, Active = true, Parent = Side })
        local logoRow = Create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(0, 24),
            AutomaticSize = AX, BackgroundTransparency = 1, Parent = Logo,
        })
        List(logoRow, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
        local badge = Create("Frame", { Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(4, 5, 9), BorderSizePixel = 0, LayoutOrder = 1, Parent = logoRow })
        Corner(badge, 4)
        Stroke(badge, "OutlineColor")
        Text({ Text = initials, TextSize = 10, FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = badge })
        local logoText = Create("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = AX, BackgroundTransparency = 1, LayoutOrder = 2, Parent = logoRow })
        List(logoText, nil, 0)
        Text({ Text = title, TextSize = 14, FontFace = F(W_BOLD), Size = UDim2.fromOffset(0, 16), AutomaticSize = AX, LayoutOrder = 1, Parent = logoText })
        Text({ Text = tostring(info.Footer or ""), TextSize = 9, ColorKey = "DimColor", Size = UDim2.fromOffset(0, 10), AutomaticSize = AX, LayoutOrder = 2, Parent = logoText })
        local logoLine = Create("Frame", { Position = UDim2.fromOffset(9, HEAD), Size = UDim2.new(1, -18, 0, 1), BorderSizePixel = 0, Parent = Side })
        Theme(logoLine, { BackgroundColor3 = "OutlineColor" })

        -- навигация
        local Nav = Create("ScrollingFrame", {
            Position = UDim2.fromOffset(0, HEAD - 2), Size = UDim2.new(1, 0, 1, -(HEAD - 2) - 56), BackgroundTransparency = 1,
            BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = Side,
        })
        -- АНИМАЦИЯ: промежуток 6px перенесён внутрь самих пунктов (высота 31+6),
        -- иначе при раскрытии подпунктов UIListLayout дёргал бы отступы скачком.
        -- Визуально раскладка та же, что раньше.
        local NAV_GAP, NAV_H = 6, 31
        List(Nav, nil, 0)
        Pad(Nav, 9, 10, 0, 8 - NAV_GAP)
        local navOrder = 0
        local function nextOrder() navOrder += 1 return navOrder * 100 end

        -- пункт: 31px, скругление 8, иконка по центру x=16, текст с x=36
        local function NavItem(text, indent, order, icon)
            local wrap = Create("Frame", {
                Size = UDim2.new(1, 0, 0, NAV_H + NAV_GAP), BackgroundTransparency = 1, ClipsDescendants = true,
                LayoutOrder = order, Parent = Nav,
            })
            local item = Button({ Position = UDim2.fromOffset(indent, 0), Size = UDim2.new(1, -indent, 0, NAV_H), Parent = wrap })
            Corner(item, 8)
            local slot = Create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(16, 16),
                BackgroundTransparency = 1, Parent = item,
            })
            local glyph = Icon(slot, icon, nil, 14, true)
            local label = Text({
                Text = tostring(text), TextSize = 14, ColorKey = false, Position = UDim2.fromOffset(36, 0),
                Size = UDim2.new(1, -40, 1, 0), ClipsDescendants = true, Parent = item,
            })
            local hovered = false
            local N = { Wrap = wrap, Item = item, Label = label, Open = true }
            -- АНИМАЦИЯ: подсветка/hover/цвет текста и иконки - кроссфейд 0.13s (как на видео, без «ползущей» плашки)
            local function set(inst, props)
                if Library.Animations then Anim(inst, T_NAV, props) else for k, v in pairs(props) do inst[k] = v end end
            end
            function N:Paint(selected, bright)
                item.BackgroundColor3 = Scheme.ItemColor
                set(item, { BackgroundTransparency = selected and 0 or (hovered and 0.6 or 1) })
                set(label, { TextColor3 = (selected or bright) and Scheme.FontColor or Scheme.SubColor })
                label.FontFace = F(selected and W_SEMI or W_MED)
                local gc = selected and Scheme.AccentColor or ((selected or bright) and Scheme.FontColor or Scheme.SubColor)
                if glyph:IsA("ImageLabel") then set(glyph, { ImageColor3 = gc }) else set(glyph, { BackgroundColor3 = gc }) end
            end
            -- АНИМАЦИЯ: раскрытие/сворачивание подпунктов - высота 0 <-> 37 за 0.15s
            function N:SetOpen(on, instant)
                if N.Open == on then return end
                N.Open = on
                local h = UDim2.new(1, 0, 0, on and (NAV_H + NAV_GAP) or 0)
                if instant or not Library.Animations then
                    wrap.Size = h
                    wrap.Visible = on
                    return
                end
                wrap.Visible = true
                Anim(wrap, T_EXPAND, { Size = h }, 0, function()
                    if not N.Open then wrap.Visible = false end
                end)
            end
            item.MouseEnter:Connect(function() hovered = true if N.Repaint then N.Repaint() end end)
            item.MouseLeave:Connect(function() hovered = false if N.Repaint then N.Repaint() end end)
            return N
        end

        -- профиль внизу: аватар 34, имя, подпись, ">"
        local Profile = Create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Parent = Side })
        local pLine = Create("Frame", { Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -18, 0, 1), BorderSizePixel = 0, Parent = Profile })
        Theme(pLine, { BackgroundColor3 = "OutlineColor" })
        local avatar = Create("ImageLabel", { Position = UDim2.fromOffset(14, 11), Size = UDim2.fromOffset(34, 34), BorderSizePixel = 0, Image = "", Parent = Profile })
        Theme(avatar, { BackgroundColor3 = "ItemColor" })
        Corner(avatar, 17)
        task.spawn(function()
            local ok, img = pcall(function()
                return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            end)
            if ok and avatar.Parent then avatar.Image = img end
        end)
        Text({ Text = LP.DisplayName, TextSize = 14, FontFace = F(W_SEMI), Position = UDim2.fromOffset(59, 12), Size = UDim2.new(1, -86, 0, 17), ClipsDescendants = true, Parent = Profile })
        Text({ Text = "@" .. LP.Name, TextSize = 11, ColorKey = "DimColor", Position = UDim2.fromOffset(59, 30), Size = UDim2.new(1, -86, 0, 14), ClipsDescendants = true, Parent = Profile })
        local profArrow = Arrow(Profile, "SubColor", -16)

        -- [v42] попап настроек по стрелке: как dropdown NL (OpenPopup: прозрачность, тень, скругление, авто-закрытие)
        Library.ESPScale = Library.ESPScale or 1
        Library.Units = Library.Units or "studs"
        local tillDate = os.date("%b %d, %Y", os.time() + 3 * 86400)
        local menuSteps = { 70, 80, 90, 100, 110, 125, 150 }
        local espSteps = { 60, 80, 100, 125, 150, 200 }
        local accents, accI = { Color3.fromRGB(150, 164, 255), Color3.fromRGB(120, 230, 150), Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 180, 80), Color3.fromRGB(190, 130, 255) }, 1
        local function pct(v) return math.floor((v or 1) * 100 + 0.5) end
        local function nextStep(steps, cur)
            for _, st in ipairs(steps) do if st > cur then return st end end
            return steps[1]
        end

        local function buildAccountPopup(frame, close)
            local col = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = frame })
            List(col, nil, 2)
            Pad(col, 10, 10, 10, 10)
            -- шапка
            local head = Create("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = 1, Parent = col })
            local av = Create("ImageLabel", { Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(34, 34), BorderSizePixel = 0, Image = avatar.Image, Parent = head })
            Theme(av, { BackgroundColor3 = "ItemColor" })
            Corner(av, 17)
            Text({ Text = LP.DisplayName, TextSize = 14, FontFace = F(W_SEMI), Position = UDim2.fromOffset(44, 2), Size = UDim2.new(1, -44, 0, 17), ClipsDescendants = true, Parent = head })
            Text({ Text = "Till: " .. tillDate, TextSize = 11, ColorKey = "DimColor", Position = UDim2.fromOffset(44, 19), Size = UDim2.new(1, -44, 0, 13), Parent = head })
            local renewLink = Button({ BackgroundTransparency = 1, Position = UDim2.fromOffset(44, 30), Size = UDim2.fromOffset(44, 12), Parent = head })
            Text({ Text = "Renew", TextSize = 11, ColorKey = "AccentColor", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Left, Parent = renewLink })
            local sep = Create("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = 2, Parent = col })
            Theme(sep, { BackgroundColor3 = "OutlineColor" })
            local ord = 2
            -- kind: nil/value row (getVal + optional onClick), "swatch", "toggle" (getVal bool), "plain" (no value)
            local function row(iconName, label, getVal, onClick, kind)
                ord = ord + 1
                local r = Button({ Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = ord, Parent = col })
                Theme(r, { BackgroundColor3 = "ItemColor" })
                Corner(r, 6)
                local islot = Create("Frame", { Position = UDim2.fromOffset(4, 7), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Parent = r })
                Icon(islot, iconName, "SubColor", 15, true)
                Text({ Text = label, TextSize = 13, ColorKey = "FontColor", Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -96, 1, 0), Parent = r })
                local valT, swatch, pill, knob
                if kind == "swatch" then
                    swatch = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, Parent = r })
                    Corner(swatch, 5)
                    Arrow(r, "SubColor", -9)
                elseif kind == "toggle" then
                    pill = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(32, 18), BorderSizePixel = 0, Parent = r })
                    Corner(pill, 9)
                    knob = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, Parent = pill })
                    Corner(knob, 6)
                    Theme(knob, { BackgroundColor3 = "MainColor" })
                elseif kind ~= "plain" then
                    valT = Text({ Text = "", TextSize = 12, ColorKey = "ValueColor", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -22, 0.5, 0), Size = UDim2.fromOffset(62, 16), TextXAlignment = Enum.TextXAlignment.Right, Parent = r })
                    Arrow(r, "SubColor", -9)
                else
                    Arrow(r, "SubColor", -9)
                end
                local function refresh()
                    local v = getVal and getVal()
                    if swatch then swatch.BackgroundColor3 = v
                    elseif pill then pill.BackgroundColor3 = v and Scheme.AccentColor or Scheme.OffTrack
                    elseif valT then valT.Text = tostring(v) end
                end
                r.MouseEnter:Connect(function() r.BackgroundTransparency = 0 end)
                r.MouseLeave:Connect(function() r.BackgroundTransparency = 1 end)
                r.BackgroundTransparency = 1
                r.MouseButton1Click:Connect(function() if onClick then onClick() end refresh() end)
                refresh()
            end
            -- порядок как в NL. Рабочие: Menu/ESP Scale, Units, Style. Остальное - заглушки для вида.
            row("world", "Language", function() return "English" end, nil)
            row("config", "Menu Scale", function() return pct(Library.MenuScale) .. "%" end, function()
                Library:SetMenuScale(nextStep(menuSteps, pct(Library.MenuScale)) / 100)
            end)
            row("kb_eye", "ESP Scale", function() return pct(Library.ESPScale) .. "%" end, function()
                Library.ESPScale = nextStep(espSteps, pct(Library.ESPScale)) / 100
                if Library._ThemeSave then Library._ThemeSave() end
            end)
            row("camera", "Windows Scale", function() return "100%" end, nil)
            row("misc", "Units", function() return Library.Units end, function()
                Library.Units = Library.Units == "studs" and "meters" or "studs"
                if Library._ThemeSave then Library._ThemeSave() end
            end)
            -- [v45] Style листает темы меню (свотч - акцент текущей темы)
            row("wm_color", "Style", function() return Scheme.AccentColor end, function()
                local i = 1
                for k, t in ipairs(Library.Themes) do if t.Name == Library.ThemeName then i = k end end
                Library:ApplyTheme(Library.Themes[i % #Library.Themes + 1].Name)
            end, "swatch")
            -- разделитель перед «системными» заглушками
            ord = ord + 1
            local sep2 = Create("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, LayoutOrder = ord, Parent = col })
            Theme(sep2, { BackgroundColor3 = "OutlineColor" })
            row("kb_shield", "Safe Mode", function() return "Automatic" end, nil)
            row("wm_server", "Synchronization", function() return true end, nil, "toggle")
            row("players", "About", nil, nil, "plain")
            row("kb_list", "Chat", nil, nil, "plain")
        end

        local profBtn = Button({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Profile })
        profBtn.ZIndex = 50
        profBtn.MouseButton1Click:Connect(function()
            OpenPopup(Profile, SIDE + 20, 404, buildAccountPopup, true, false, function(ap, as, vp, w, h)
                -- справа от стрелки; стрелка примерно по центру попапа (опущен вниз на пол-высоты)
                local x = math.clamp(ap.X + as.X - 2, 6, math.max(6, vp.X - w - 6))
                local y = math.clamp(ap.Y + as.Y / 2 - h / 2, 6, math.max(6, vp.Y - h - 6))
                return x, y
            end)
        end)

        -- контент
        local Content = Create("Frame", { Position = UDim2.fromOffset(SIDE + 1, 0), Size = UDim2.new(1, -SIDE - 1, 1, 0), BackgroundTransparency = 1, Parent = Body })
        local Header = Create("Frame", { Size = UDim2.new(1, 0, 0, HEAD), BackgroundTransparency = 1, Active = true, Parent = Content })
        local hLine = Create("Frame", { Position = UDim2.fromOffset(0, HEAD), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = Content })
        Theme(hLine, { BackgroundColor3 = "OutlineColor" })
        local PagesHolder = Create("Frame", { Position = UDim2.fromOffset(0, HEAD + 1), Size = UDim2.new(1, 0, 1, -HEAD - 1), BackgroundTransparency = 1, Parent = Content })

        -- шапка: [сохранить | конфиг v]  ...  (o)
        local cfgGroup = Create("Frame", { Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(0, 30), AutomaticSize = AX, BackgroundTransparency = 1, Parent = Header })
        Corner(cfgGroup, 6)
        Stroke(cfgGroup, "OutlineColor")
        List(cfgGroup, Enum.FillDirection.Horizontal, 0, nil, Enum.VerticalAlignment.Center)

        local SaveBtn = Button({ Size = UDim2.fromOffset(35, 30), LayoutOrder = 1, Parent = cfgGroup })
        if not Icon(SaveBtn, "save", "ValueColor", 13) then -- запасная дискета из фреймов
            local body = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0, Parent = SaveBtn })
            Theme(body, { BackgroundColor3 = "ValueColor" })
            Corner(body, 2)
            local slot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(6, 3), BorderSizePixel = 0, Parent = body })
            Theme(slot, { BackgroundColor3 = "MainColor" })
            local hole = Create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(4, 3), BorderSizePixel = 0, Parent = body })
            Theme(hole, { BackgroundColor3 = "MainColor" })
        end
        AttachTooltip(SaveBtn, "Save current config")
        local cfgDiv = Create("Frame", { Size = UDim2.fromOffset(1, 30), BorderSizePixel = 0, LayoutOrder = 2, Parent = cfgGroup })
        Theme(cfgDiv, { BackgroundColor3 = "OutlineColor" })
        local ConfigBtn = Button({ Size = UDim2.fromOffset(106, 30), LayoutOrder = 3, Parent = cfgGroup })
        local ConfigLabel = Text({
            Text = "default", TextSize = 14, ColorKey = "ValueColor", Position = UDim2.fromOffset(12, 0),
            Size = UDim2.new(1, -36, 1, 0), ClipsDescendants = true, Parent = ConfigBtn,
        })
        Chevron(ConfigBtn).Position = UDim2.new(1, -12, 0.5, 1)

        local SearchBtn = Button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(26, 26), Parent = Header })
        if not Icon(SearchBtn, "search", "ValueColor", 14) then -- запасная лупа из фреймов
            local ring = Create("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(11, 11), BackgroundTransparency = 1, Parent = SearchBtn })
            Corner(ring, 6)
            Stroke(ring, "ValueColor", 0, 1.6)
            local handle = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(19, 19), Size = UDim2.fromOffset(2, 6), Rotation = -45, BorderSizePixel = 0, Parent = SearchBtn })
            Theme(handle, { BackgroundColor3 = "ValueColor" })
            Corner(handle, 1)
        end
        local SearchBox = Create("TextBox", {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -46, 0, 12), Size = UDim2.fromOffset(180, 30),
            BorderSizePixel = 0, ClearTextOnFocus = false, FontFace = F(W_REG), TextSize = 14, Text = "",
            PlaceholderText = "Search", TextXAlignment = Enum.TextXAlignment.Left, Visible = false, Parent = Header,
        })
        Theme(SearchBox, { BackgroundColor3 = "InputColor", TextColor3 = "ValueColor", PlaceholderColor3 = "DimColor" })
        Corner(SearchBox, 6)
        Stroke(SearchBox, "InputBorder")
        Pad(SearchBox, 10, 10, 0, 0)

        -- перетаскивание окна за шапку / логотип
        local function draggable(handle)
            handle.InputBegan:Connect(function(input)
                if not IsClick(input) then return end
                local start, startPos = V2(input.Position), Main.Position
                BeginDrag(input, function(pos)
                    local d = pos - start
                    Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end)
            end)
        end
        draggable(Header)
        draggable(Logo)

        -- страница: отступы 10, промежуток колонок 10; секция = заголовок 16 + 4 + панель
        local AllPages = {}
        -- parent: AMBIENCE - страница внутри панели поверх контента (не участвует в переключении вкладок)
        local function NewPage(parent)
            local Page = { Groups = {}, Rows = {} }
            local scroll = Create("ScrollingFrame", {
                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
                CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y,
                Visible = parent ~= nil, Parent = parent or PagesHolder,
            })
            if not parent then table.insert(AllPages, scroll) end
            Theme(scroll, { ScrollBarImageColor3 = "ItemColor" })
            -- ФИКС: UIPadding внутри ScrollingFrame не уменьшает базу для scale-размеров,
            -- поэтому колонки были по 311px и слипались. Поля задаём обычной рамкой-контейнером.
            local body = Create("Frame", {
                Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 0), AutomaticSize = AY,
                BackgroundTransparency = 1, Parent = scroll,
            })
            Pad(body, 0, 0, 0, 12)
            local function column(left)
                local c = Create("Frame", {
                    Position = left and UDim2.new() or UDim2.new(0.5, 5, 0, 0), Size = UDim2.new(0.5, -5, 0, 0),
                    AutomaticSize = AY, BackgroundTransparency = 1, Parent = body,
                })
                List(c, nil, 16)
                return c
            end
            Page.Scroll = scroll
            local cols = { Left = column(true), Right = column(false) }
            local function addGroup(col, name)
                local G = setmetatable({ Page = Page, Name = tostring(name or ""), Count = 0, Rows = 0 }, Group)
                local holder = Create("Frame", { Size = UDim2.fromScale(1, 0), AutomaticSize = AY, BackgroundTransparency = 1, LayoutOrder = #Page.Groups + 1, Parent = col })
                List(holder, nil, 4)
                local titleLabel = Text({ Text = G.Name, TextSize = 12, ColorKey = "DimColor", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1, Parent = holder })
                Pad(titleLabel, 14, 0, 0, 0)
                -- ПЕРЕКЛЮЧАТЕЛЬ (как «Enemies» у NL): живёт в строке заголовка первой правой секции, справа
                if col == cols.Right and Page.SwitchTab and not Page.SwitchBar then
                    local bar = Create("Frame", {
                        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Size = UDim2.fromOffset(0, 24),
                        AutomaticSize = AX, BackgroundTransparency = 1, Parent = titleLabel,
                    })
                    List(bar, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
                    Page.SwitchBar, Page.SwitchButtons = bar, {}
                    Page.SwitchTab:Paint()
                end
                local panel = Create("Frame", { Size = UDim2.fromScale(1, 0), AutomaticSize = AY, BorderSizePixel = 0, LayoutOrder = 2, Parent = holder })
                Theme(panel, { BackgroundColor3 = "GroupColor" })
                local panelCorner = Corner(panel, 12)
                -- [v45] стиль темы: заголовок капсом, скругление панели
                Library:AddRefresh(function()
                    local st = Library.Style or {}
                    titleLabel.Text = st.UpperTitles and string.upper(G.Name) or G.Name
                    panelCorner.CornerRadius = UDim.new(0, st.Round or 12)
                end)
                Stroke(panel, "OutlineColor")
                List(panel)
                G.Holder, G.Panel = holder, panel
                table.insert(Page.Groups, G)
                return G
            end
            function Page:AddLeftGroupbox(name) return addGroup(cols.Left, name) end
            function Page:AddRightGroupbox(name) return addGroup(cols.Right, name) end
            return Page
        end

        function Window:CurrentPage()
            local t = self.Active
            if not t then return nil end
            return (#t.SubTabs > 0) and t.ActiveSub or t.Default
        end

        function Window:ApplySearch()
            local page = self:CurrentPage()
            if not page then return end
            local q = string.lower(SearchBox.Text or "")
            local groupHit, groupAny = {}, {}
            for _, g in ipairs(page.Groups) do
                groupHit[g] = q ~= "" and string.find(string.lower(g.Name), q, 1, true) ~= nil
            end
            for _, r in ipairs(page.Rows) do
                local show = q == "" or groupHit[r.Group] or string.find(r.Text, q, 1, true) ~= nil
                r.Row.Visible = show
                if show then groupAny[r.Group] = true end
            end
            for _, g in ipairs(page.Groups) do
                g.Holder.Visible = q == "" or groupAny[g] == true
            end
        end
        SearchBox:GetPropertyChangedSignal("Text"):Connect(function() Window:ApplySearch() end)
        SearchBtn.MouseButton1Click:Connect(function()
            SearchBox.Visible = not SearchBox.Visible
            if SearchBox.Visible then
                SearchBox:CaptureFocus()
            else
                SearchBox.Text = ""
            end
        end)

        -- АНИМАЦИЯ смены страницы (замер с видео): старая гаснет 0.10s -> пауза -> новая проявляется 0.12s.
        -- Быстрые повторные клики не копят анимации: устаревшие обрываются по токену.
        local Overlays = {} -- AMBIENCE: панели поверх контента (Window:AddOverlay)
        local Shown, pageToken = nil, 0
        local function ShowPage(scroll)
            if scroll == Shown then return end
            local old = Shown
            Shown = scroll
            pageToken += 1
            local tok = pageToken
            for _, p in ipairs(AllPages) do
                if p ~= old and p ~= scroll then
                    if Fading[p] then Fading[p].Restore() end
                    p.Visible = false
                end
            end
            local animate = Library.Animations and Main.Visible and old ~= nil
            local function fadeIn(delay)
                if tok ~= pageToken or not scroll then return end
                scroll.Visible = true
                if animate then
                    local from = 1
                    if Fading[scroll] then from = nil end -- уже гаснет: разворачиваем с текущей прозрачности
                    Fade(scroll, 0, from, 0, T_PAGE_IN, delay)
                end
            end
            if animate and old.Visible then
                if scroll and Fading[scroll] then Fading[scroll].Restore() end
                if scroll then scroll.Visible = false end
                Fade(old, 0, nil, 1, T_PAGE_OUT, 0, function()
                    old.Visible = false
                    fadeIn(T_PAGE_GAP)
                end)
            else
                if old then
                    if Fading[old] then Fading[old].Restore() end
                    old.Visible = false
                end
                fadeIn(0)
            end
        end

        function Window:SelectTab(tab)
            Library:ClosePopup()
            HideTip()
            for _, o in ipairs(Overlays) do o:Close(true) end -- AMBIENCE: панель закрывается при смене вкладки
            self.Active = tab
            for _, t in ipairs(self.Tabs) do
                local on = t == tab
                for _, s in ipairs(t.SubTabs) do
                    if s.Nav then s.Nav:SetOpen(on) end -- подпункты плавно раскрываются под активной вкладкой
                end
                t:Paint()
            end
            local page = self:CurrentPage()
            ShowPage(page and page.Scroll or nil)
            self:ApplySearch()
        end

        -- AMBIENCE: панель поверх области контента (как Ambience у NL): шапка с заголовком и «x»,
        -- ниже - две колонки секций. Под ней страница затемнена (размыть GUI в Roblox нельзя).
        function Window:AddOverlay(titleText)
            local ov = Button({
                Name = "Overlay", BackgroundTransparency = 0.03, Size = UDim2.fromScale(1, 1), ZIndex = 20,
                Visible = false, Parent = Content,
            })
            Theme(ov, { BackgroundColor3 = "MainColor" })
            Corner(ov, 16)
            -- левый край прямой (стык с сайдбаром)
            local edge = Create("Frame", { Size = UDim2.new(0, 16, 1, 0), BorderSizePixel = 0, BackgroundTransparency = 0.03, Parent = ov })
            Theme(edge, { BackgroundColor3 = "MainColor" })
            Text({ Text = tostring(titleText or ""), TextSize = 15, FontFace = F(W_SEMI), Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -80, 0, HEAD), Parent = ov })
            local line = Create("Frame", { Position = UDim2.fromOffset(0, HEAD), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = ov })
            Theme(line, { BackgroundColor3 = "OutlineColor" })
            -- «x» (как у NL справа сверху)
            local x = Button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0, HEAD / 2), Size = UDim2.fromOffset(22, 22), Parent = ov })
            local bars = {}
            for _, rot in ipairs({ 45, -45 }) do
                local b = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(13, 2), Rotation = rot, BorderSizePixel = 0, Parent = x })
                Corner(b, 1)
                Theme(b, { BackgroundColor3 = "ValueColor" })
                table.insert(bars, b)
            end
            x.MouseEnter:Connect(function() for _, b in ipairs(bars) do b.BackgroundColor3 = Scheme.FontColor end end)
            x.MouseLeave:Connect(function() for _, b in ipairs(bars) do b.BackgroundColor3 = Scheme.ValueColor end end)
            local body = Create("Frame", { Position = UDim2.fromOffset(0, HEAD + 1), Size = UDim2.new(1, 0, 1, -HEAD - 1), BackgroundTransparency = 1, Parent = ov })
            local page = NewPage(body)
            local O = { Frame = ov, Page = page, IsOpen = false }
            function O:AddLeftGroupbox(n) return page:AddLeftGroupbox(n) end
            function O:AddRightGroupbox(n) return page:AddRightGroupbox(n) end
            function O:Open()
                Library:ClosePopup()
                HideTip()
                for _, other in ipairs(Overlays) do if other ~= O and other.IsOpen then other:Close(true) end end
                O.IsOpen = true
                ov.Visible = true
                Fade(ov, 0, 1, 0, T_PAGE_IN)
                if O.OnOpen then Safe(O.OnOpen) end
            end
            function O:Close(instant)
                if not O.IsOpen then return end
                O.IsOpen = false
                Library:ClosePopup()
                if instant then
                    if Fading[ov] then Fading[ov].Restore() end
                    ov.Visible = false
                else
                    Fade(ov, 0, nil, 1, T_PAGE_OUT, 0, function() if not O.IsOpen then ov.Visible = false end end)
                end
            end
            x.MouseButton1Click:Connect(function() O:Close() end)
            table.insert(Overlays, O)
            return O
        end

        function Window:AddCategory(name)
            local l = Text({
                Text = string.upper(tostring(name)), TextSize = 12, ColorKey = "DimColor", Size = UDim2.new(1, 0, 0, 26 + NAV_GAP),
                TextYAlignment = Enum.TextYAlignment.Bottom, LayoutOrder = nextOrder(), Parent = Nav,
            })
            Pad(l, 10, 0, 0, 2 + NAV_GAP)
        end

        -- кнопка переключателя: иконка; у активной - иконка акцентом + подпись на подложке
        local function SwitchButton(page, sub, tab, i)
            local b = Button({ Size = UDim2.fromOffset(0, 24), AutomaticSize = AX, LayoutOrder = i, Parent = page.SwitchBar })
            Corner(b, 6)
            Pad(b, 6, 7, 0, 0)
            List(b, Enum.FillDirection.Horizontal, 5, nil, Enum.VerticalAlignment.Center)
            local slot = Create("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, LayoutOrder = 1, Parent = b })
            local glyph = Icon(slot, sub.Icon, nil, 14, true)
            local label = Text({ Text = sub.Name, TextSize = 13, ColorKey = false, Size = UDim2.fromOffset(0, 24), AutomaticSize = AX,
                Visible = false, LayoutOrder = 2, Parent = b })
            local hovered = false
            local B = { Button = b, Label = label, Sub = sub }
            function B:Paint(on)
                b.BackgroundColor3 = Scheme.ItemColor
                b.BackgroundTransparency = on and 0 or (hovered and 0.6 or 1)
                label.Visible = on
                label.TextColor3 = Scheme.AccentColor
                local gc = on and Scheme.AccentColor or (hovered and Scheme.FontColor or Scheme.SubColor)
                if glyph:IsA("ImageLabel") then glyph.ImageColor3 = gc else glyph.BackgroundColor3 = gc end
            end
            b.MouseEnter:Connect(function() hovered = true tab:Paint() end)
            b.MouseLeave:Connect(function() hovered = false tab:Paint() end)
            b.MouseButton1Click:Connect(function() tab:SelectSub(sub) end)
            AttachTooltip(b, sub.Name)
            return B
        end

        -- opts.Switcher = true: подвкладки не в сайдбаре, а переключателем над правой колонкой (как Enemies у NL)
        function Window:AddTab(name, icon, opts)
            opts = opts or {}
            local order = nextOrder()
            local Tab = { Name = tostring(name), SubTabs = {}, ActiveSub = nil, Default = nil, Switcher = opts.Switcher == true }
            local nav = NavItem(Tab.Name, 0, order, icon)
            Tab.Nav = nav

            function Tab:Paint()
                local on = Window.Active == self
                local hasSubs = #self.SubTabs > 0 and not self.Switcher
                -- как в NL: у раскрытой вкладки подсвечен подпункт, а не сама вкладка
                nav:Paint(on and not hasSubs, on and hasSubs)
                for _, s in ipairs(self.SubTabs) do
                    if s.Nav then s.Nav:Paint(on and self.ActiveSub == s, false) end
                    if s.SwitchBar then
                        for i, other in ipairs(self.SubTabs) do
                            s.SwitchButtons[i] = s.SwitchButtons[i] or SwitchButton(s, other, self, i)
                            s.SwitchButtons[i]:Paint(other == s)
                        end
                    end
                end
            end
            nav.Repaint = function() Tab:Paint() end
            nav.Item.MouseButton1Click:Connect(function() Window:SelectTab(Tab) end)

            local function default()
                if not Tab.Default then
                    Tab.Default = NewPage()
                    if Window.Active == Tab then Window:SelectTab(Tab) end
                end
                return Tab.Default
            end
            function Tab:AddLeftGroupbox(n) return default():AddLeftGroupbox(n) end
            function Tab:AddRightGroupbox(n) return default():AddRightGroupbox(n) end

            function Tab:SelectSub(sub)
                self.ActiveSub = sub
                if Window.Active == self then Window:SelectTab(self) else self:Paint() end
            end

            -- подвкладка = подпункт в сайдбаре с отступом 16
            function Tab:AddSubTab(sname, sicon)
                local Sub = NewPage()
                Sub.Name, Sub.Icon = tostring(sname), sicon
                if self.Switcher then
                    Sub.SwitchTab = self
                    table.insert(self.SubTabs, Sub)
                    if not self.ActiveSub then self.ActiveSub = Sub end
                    if Window.Active == self then Window:SelectTab(self) else self:Paint() end
                    return Sub
                end
                Sub.Nav = NavItem(Sub.Name, 16, order + #self.SubTabs + 1, sicon)
                Sub.Nav:SetOpen(Window.Active == self, true)
                Sub.Nav.Repaint = function() Tab:Paint() end
                Sub.Nav.Item.MouseButton1Click:Connect(function() Tab:SelectSub(Sub) end)
                table.insert(self.SubTabs, Sub)
                if not self.ActiveSub then self.ActiveSub = Sub end
                if Window.Active == self then Window:SelectTab(self) else self:Paint() end
                return Sub
            end

            table.insert(Window.Tabs, Tab)
            Library:AddRefresh(function() Tab:Paint() end)
            if not Window.Active then Window:SelectTab(Tab) end
            return Tab
        end

        -- конфиг в шапке (провайдер ставит SaveManager)
        function Window:SetConfigName(n)
            ConfigLabel.Text = tostring(n or "default")
            Library.ConfigName = ConfigLabel.Text -- ВАТЕРМАРКА: пункт Preset
        end
        function Window:SetConfigProvider(p) self.ConfigProvider = p end
        ConfigBtn.MouseButton1Click:Connect(function()
            local p = Window.ConfigProvider
            if not p then return end
            OpenList(cfgGroup, p.List(), p.Current(), p.Load, true)
        end)
        SaveBtn.MouseButton1Click:Connect(function()
            local p = Window.ConfigProvider
            if p then p.Save() end
        end)

        -- освобождение мыши (first person) + свой курсор
        local Modal = Button({ Size = UDim2.fromOffset(0, 0), Modal = true, Visible = Main.Visible, Parent = ScreenGui })
        local Cursor = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = WHITE,
            BorderSizePixel = 0, ZIndex = 100, Visible = false, Parent = ScreenGui,
        })
        Corner(Cursor, 4)
        Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = Cursor })
        local showCursor = info.ShowCustomCursor ~= false

        Connect(RunService.RenderStepped, function()
            if not Main.Visible then return end
            -- ЭФФЕКТ: стекло блюра следует за окном (драг, масштаб); 5px под скругление 16
            Acrylic:Update(Main, 5 * Scale.Scale)
            local m = MousePos()
            if showCursor then Cursor.Position = UDim2.fromOffset(m.X, m.Y) end
            if Tip.Visible then
                local vp = ScreenGui.AbsoluteSize
                local s = Tip.AbsoluteSize
                Tip.Position = UDim2.fromOffset(math.min(m.X + 14, vp.X - s.X - 6), math.min(m.Y + 16, vp.Y - s.Y - 6))
            end
        end)

        -- АНИМАЦИЯ открытия/закрытия. Состояние (мышь, курсор, бинды) меняется сразу,
        -- анимация только визуальная: во время закрытия окно уже не кликается.
        Library.Toggled = Main.Visible
        -- ЭФФЕКТ: блюр включается, когда окно полностью открылось, и гаснет сразу при закрытии,
        -- чтобы размытый прямоугольник никогда не был виден без окна
        UpdateBlur = function()
            Acrylic:Set(Library.Blur and Library.Toggled and not Library.Unloaded and Fading[Body] == nil)
        end
        Library.UpdateBlur = UpdateBlur
        function Library:Toggle(state)
            if state == nil then state = not Library.Toggled end
            Library.Toggled = state
            Modal.Visible = state
            Cursor.Visible = state and showCursor and not UIS.TouchEnabled
            pcall(function() Body.Interactable = state end)
            if state then
                local wasClosing = Fading[Body] ~= nil
                Main.Visible = true
                if Library.Animations then
                    -- открытие: 0.20s Quad Out, прозрачность 1 -> 0, масштаб 0.97 -> 1
                    if not wasClosing then ZoomValue.Value = ZOOM_FROM end
                    Anim(ZoomValue, T_OPEN, { Value = 1 })
                    local from = 1
                    if wasClosing then from = nil end -- открыли посреди закрытия: продолжаем с текущего кадра
                    Fade(Body, SHADOW_PAD, from, 0, T_OPEN, 0, UpdateBlur)
                else
                    ZoomValue.Value = 1
                    UpdateBlur()
                end
            else
                Acrylic:Set(false)
                Library:ClosePopup()
                HideTip()
                ActiveDrag = nil
                if Library.Animations and Main.Visible then
                    -- закрытие (на видео не нашлось чистого кадра): симметрично, 0.15s
                    Anim(ZoomValue, T_CLOSE, { Value = ZOOM_FROM })
                    Fade(Body, SHADOW_PAD, nil, 1, T_CLOSE, 0, function()
                        if Library.Toggled then return end
                        Main.Visible = false
                        ZoomValue.Value = 1
                    end)
                else
                    if Fading[Body] then Fading[Body].Restore() end
                    Main.Visible = false
                    ZoomValue.Value = 1
                end
            end
        end
        Library:Toggle(Main.Visible)

        Connect(UIS.InputBegan, function(input)
            if Library.Unloaded or Library._Binding or input.UserInputType ~= KB then return end
            if UIS:GetFocusedTextBox() then return end
            local kb = Library.ToggleKeybind
            local key = kb and kb.Value or "RightShift"
            if input.KeyCode.Name == key then Library:Toggle() end
        end)

        -- мобильная кнопка открытия меню
        if UIS.TouchEnabled then
            local mob = Button({
                BackgroundTransparency = 0, Position = UDim2.new(0, 12, 0.3, 0), Size = UDim2.fromOffset(44, 44),
                ZIndex = 40, Parent = ScreenGui,
            })
            Theme(mob, { BackgroundColor3 = "GroupColor" })
            Corner(mob, 12)
            Stroke(mob, "OutlineColor")
            Text({ Text = initials, TextSize = 15, FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = mob })
            mob.MouseButton1Click:Connect(function() Library:Toggle() end)
        end

        Library:CreateWatermark({ Title = title }) -- ВАТЕРМАРКА справа сверху
        return Window
    end

    --------------------------------------------------------
    -- ВАТЕРМАРКА (как в NL CS2, справа сверху). Замер с твоих скриншотов
    -- (в единицах меню, NL-окно там 748px против наших 800):
    --   плашка высотой 24, отступ от края 6, скругление 7, фон ~65% непрозрачности
    --   (цвет плашки меняется вслед за фоном игры) + мягкая тень;
    --   поля 9, между пунктами 10, иконка 12 акцентом + 5, текст 13 semibold, аватар 16;
    --   правый клик - панель «Watermark» (Items / Additional Color / Display Avatar),
    --   Items раскрывает список с галочками, строки 26px.
    -- Пункты NL, для которых в Roblox нет данных (KD, GPU/CPU Load, CPU Frequency,
    -- Loss, Connectivity Issues), не добавлены, чтобы не показывать выдуманные цифры.
    --------------------------------------------------------
    local Stats = game:GetService("Stats")
    local WM_ITEMS = {
        { Key = "Logo",      Text = "Logo",           Icon = "wm_items" },
        { Key = "Speed",     Text = "Speed",          Icon = "wm_speed" },
        { Key = "Framerate", Text = "Framerate",      Icon = "wm_fps" },
        { Key = "Memory",    Text = "Memory Load",    Icon = "wm_mem" },
        { Key = "Latency",   Text = "Latency",        Icon = "wm_ping" },
        { Key = "Var",       Text = "Var",            Icon = "wm_var" },
        { Key = "Server",    Text = "Server Address", Icon = "wm_server" },
        { Key = "Preset",    Text = "Preset",         Icon = "wm_preset" },
        { Key = "Username",  Text = "Username",       Icon = "wm_user" },
        { Key = "Time",      Text = "Time",           Icon = "wm_time" },
        -- аватар - обычный пункт: таскается и убирается как остальные (по умолчанию в конце, как у NL)
        { Key = "Avatar",    Text = "Avatar",         Icon = "wm_user" },
    }
    -- «Additional Color»: на скрине NL им подсвечен пункт с высокой нагрузкой (64% MEM),
    -- поэтому здесь это цвет предупреждения, когда значение плохое
    local WM_WARN = {
        Framerate = function(v) return v < 30 end,
        Latency   = function(v) return v > 150 end,
        Var       = function(v) return v > 25 end,
        Memory    = function(v) return v > 3000 end,
    }

    -- БИНДЫ (v26, по видео NL CS2):
    --   * индикаторы слева (как «HC» / «MD»): тонкая цветная полоска, тёмная скруглённая плашка,
    --     иконка + крупный жирный текст. Видны, пока бинд работает.
    --   * окно «Hotkeys»: шапка-пилюля с синей иконкой, ниже строки «название .... [переключатель]».
    --     Новая строка проявляется, ушедшая гаснет, строки ниже плавно поднимаются, правая колонка
    --     и ширина шапки плавно подстраиваются под самое длинное название.
    -- Обе стопки перетаскиваются при открытом меню; включаются в Config -> Theme.
    Library.KeybindColor = Color3.fromRGB(235, 50, 65)

    -- ШРИФТ БИНДОВ (v28): у NL - Noto Sans (Medium / SemiBold, лежат в dll NL сжатыми stb).
    -- Ищем файлы в <папка скрипта>/fonts/NotoSans-*.ttf; нет - качаем с GitHub (notofonts, лицензия OFL)
    -- через HttpGet экзекутора; дальше FontFamily-json + getcustomasset. Не вышло - встроенный шрифт.
    Library.BindFonts = {}
    local NOTO_URL = "https://raw.githubusercontent.com/notofonts/notofonts.github.io/main/fonts/NotoSans/hinted/ttf/NotoSans-%s.ttf"
    local function BindFont(weight)
        return Library.BindFonts[weight] or F(weight)
    end
    function Library:LoadBindFonts()
        if self._BindFontsStarted then return end
        self._BindFontsStarted = true
        task.spawn(function()
            local loadAsset = getcustomasset or getsynasset
            if not (loadAsset and writefile and readfile and isfile and isfolder and makefolder) then return end
            local root = (tostring(Library.IconFolder or "NeverUI/icons"):match("^(.-)/[^/]*$")) or "NeverUI"
            local dir = root .. "/fonts"
            pcall(function()
                local acc = ""
                for part in string.gmatch(dir, "[^/]+") do
                    acc = acc == "" and part or (acc .. "/" .. part)
                    if not isfolder(acc) then makefolder(acc) end
                end
            end)
            local faces = {}
            for _, w in ipairs({ { "Medium", 500 }, { "SemiBold", 600 }, { "Bold", 700 } }) do
                local path = dir .. "/NotoSans-" .. w[1] .. ".ttf"
                if not isfile(path) then
                    local ok, data = pcall(function() return game:HttpGet(string.format(NOTO_URL, w[1])) end)
                    if ok and type(data) == "string" and #data > 10000 and string.sub(data, 1, 4) == "\0\1\0\0" then
                        pcall(writefile, path, data)
                    end
                end
                -- [v28] нет файла и интернета -> встроенная урезанная копия (Bold = SemiBold)
                local embedded = NL_FONT_B64[w[1] == "Bold" and "SemiBold" or w[1]]
                local small = dir .. "/NotoSans-" .. w[1] .. "-nl.ttf"
                if not isfile(path) and embedded then
                    if not isfile(small) then pcall(writefile, small, B64Decode(embedded)) end
                    if isfile(small) then path = small end
                end
                if isfile(path) then
                    local ok, id = pcall(loadAsset, path)
                    if ok and id then table.insert(faces, { name = w[1], weight = w[2], style = "normal", assetId = id }) end
                end
            end
            if #faces == 0 then return end
            local json = dir .. "/NotoSans.json"
            if not pcall(writefile, json, HttpService:JSONEncode({ name = "NotoSans", faces = faces })) then return end
            local ok, fam = pcall(loadAsset, json)
            if not ok or not fam then return end
            for _, f in ipairs(faces) do
                pcall(function() Library.BindFonts[Enum.FontWeight[f.name]] = Font.new(fam, Enum.FontWeight[f.name]) end)
            end
        end)
    end
    local function ActiveBinds()
        local list = {}
        for idx, b in pairs(Library.Binds) do
            local T = Toggles[idx]
            if T and (T.Value or b.Mode == "Always") then table.insert(list, idx) end
        end
        table.sort(list, function(a, b)
            local ta, tb = Toggles[a], Toggles[b]
            return tostring(ta.Text or a) < tostring(tb.Text or b)
        end)
        return list
    end
    local function DragWhenMenuOpen(frame)
        frame.InputBegan:Connect(function(input)
            if not IsClick(input) or not Library.Toggled then return end
            local start, startPos = V2(input.Position), frame.Position
            BeginDrag(input, function(pos)
                local d = pos - start
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end, function()
                if Library._ThemeSave then Library._ThemeSave() end
            end)
        end)
    end
    local function Tw(inst, t, props, onDone)
        if Library.Animations then return Anim(inst, t, props, 0, onDone) end
        for k, v in pairs(props) do inst[k] = v end
        if onDone then onDone() end
    end
    -- [v29] подложки биндов нарисованы PNG (мягкие края, как у NL): kb_soft / kb_pill / kb_bar.
    -- У картинки поля 6px под размытие, поэтому она на 12px больше видимой плашки.
    -- Нет getcustomasset -> обычная рамка со скруглением. Возвращает объект и имя свойства прозрачности.
    local SOFT_PAD = 6
    local function SoftBg(parent, icon, slice, color, z, radius)
        local id = Library:GetIcon(icon)
        if id then
            return Create("ImageLabel", { BackgroundTransparency = 1, Image = id, ImageColor3 = color, ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Slice, SliceCenter = slice, ZIndex = z, Parent = parent }), "ImageTransparency", SOFT_PAD
        end
        local f = Create("Frame", { BackgroundColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z, Parent = parent })
        Corner(f, radius or 8)
        return f, "BackgroundTransparency", 0
    end
    local SOFT_SLICE, PILL_SLICE = Rect.new(16, 16, 32, 32), Rect.new(26, 6, 38, 34)
    local BLOB = Color3.fromRGB(14, 12, 16)

    local function PosOf(frame)
        return { x = frame.Position.X.Offset, xs = frame.Position.X.Scale, y = frame.Position.Y.Offset, ys = frame.Position.Y.Scale }
    end
    local function SetPos(frame, d)
        if type(d) == "table" and type(d.x) == "number" and type(d.y) == "number" then
            frame.Position = UDim2.new(tonumber(d.xs) or 0, d.x, tonumber(d.ys) or 0, d.y)
        end
    end

    -- [v51] строка индикатора (как SLOW / биндов в левом списке) для чужого родителя - например, бар генератора
    -- над картой. Те же картинки kb_bar / kb_ind, отступы, шрифт биндов, цвет полоски+текста+иконки.
    -- Возвращает { Row, SetText(t), SetColor(c), SetVisible(b) }. icon = nil -> без иконки.
    function Library:CreateIndicator(parent, text, color, icon)
        self:LoadBindFonts()
        local ROW_H = 34
        local row = Create("Frame", { Size = UDim2.fromOffset(0, ROW_H), AutomaticSize = AX, BackgroundTransparency = 1, ZIndex = 41, Parent = parent })
        local barId = self:GetIcon("kb_bar")
        local bar, barProp
        if barId then
            bar = Create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -6, 0.5, -1.5), Size = UDim2.fromOffset(14, 35),
                BackgroundTransparency = 1, Image = barId, ZIndex = 42, Parent = row })
            barProp = "ImageColor3"
        else
            bar = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(2, 19),
                BorderSizePixel = 0, ZIndex = 42, Parent = row })
            Corner(bar, 1)
            barProp = "BackgroundColor3"
        end
        local box, boxProp, pad = SoftBg(row, "kb_ind", SOFT_SLICE, BLOB, 41, 9)
        box[boxProp] = 0.28
        box.Position = UDim2.fromOffset(7 - pad, -pad)
        box.Size = UDim2.fromOffset(0, ROW_H + pad * 2)
        box.AutomaticSize = AX
        Pad(box, 9 + pad, 18 + pad, 0, 3)
        List(box, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
        local ic
        if icon then
            local slot = Create("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 42, Parent = box })
            ic = Icon(slot, icon, nil, 16, true)
            ic.ZIndex = 42
        end
        local label = Text({ Text = tostring(text or ""), TextSize = 20, FontFace = BindFont(W_SEMI), ColorKey = false, Size = UDim2.fromOffset(0, ROW_H),
            AutomaticSize = AX, LayoutOrder = 2, ZIndex = 42, Parent = box })
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextStrokeTransparency = 0.7
        label.TextTransparency = 0
        local I = { Row = row, Bar = bar, Box = box, Label = label, Icon = ic }
        function I:SetText(t)
            t = tostring(t)
            if label.Text ~= t then label.Text = t end
            local ff = BindFont(W_SEMI)
            if label.FontFace ~= ff then label.FontFace = ff end
        end
        function I:SetColor(c)
            if bar[barProp] ~= c then bar[barProp] = c end
            if label.TextColor3 ~= c then label.TextColor3 = c end
            if ic then if ic:IsA("ImageLabel") then ic.ImageColor3 = c else ic.BackgroundColor3 = c end end
        end
        function I:SetVisible(v) if row.Visible ~= v then row.Visible = v end end
        I:SetColor(color or Library.KeybindColor)
        return I
    end

    function Library:CreateKeybindList()
        if self.KeybindList then return self.KeybindList end
        self:LoadBindFonts()
        local T_IN, T_OUT = 0.18, 0.14

        ------------------------------------------------ индикаторы
        -- [v33] замер по твоей разметке: у NL плашка выше (над «H» ~8px, под ней ~11px), текст чуть выше центра
        local ROW_H, GAP = 34, 7
        local KL = { Enabled = true, Items = {}, Order = {}, Count = 0, Status = {} }
        self.KeybindList = KL
        local holder = Create("Frame", { Name = "Indicators", Position = UDim2.new(0, 14, 0.6, 0), Size = UDim2.fromOffset(220, ROW_H),
            BackgroundTransparency = 1, Active = true, ZIndex = 40, Parent = ScreenGui })
        KL.Frame = holder
        local hint = Create("Frame", { Position = UDim2.fromOffset(-6, -6), Size = UDim2.new(1, 12, 1, 12), BackgroundTransparency = 1,
            Visible = false, ZIndex = 40, Parent = holder })
        Corner(hint, 8)
        local hintStroke = Stroke(hint, "OutlineColor")
        local hintLabel = Text({ Text = "Indicators", TextSize = 12, ColorKey = "DimColor", Position = UDim2.fromOffset(14, 6),
            Size = UDim2.fromOffset(200, ROW_H - 4), Visible = false, ZIndex = 41, Parent = hint })

        local function fadeProps(it, a)
            return {
                { it.Box, it.BoxProp, 0.28 + 0.72 * a },
                { it.Bar, it.BarProp, a },
                { it.Label, "TextTransparency", a },
                { it.Label, "TextStrokeTransparency", 0.7 + 0.3 * a },
                { it.Icon, it.Icon:IsA("ImageLabel") and "ImageTransparency" or "BackgroundTransparency", a },
            }
        end
        local function fade(it, a)
            for _, p in ipairs(fadeProps(it, a)) do p[1][p[2]] = p[3] end
        end
        local function fadeTo(it, a, t, onDone)
            for i, p in ipairs(fadeProps(it, a)) do Tw(p[1], t, { [p[2]] = p[3] }, i == 1 and onDone or nil) end
        end
        local function makeItem(idx)
            -- [v29] как «HC» у NL: светящаяся полоска (PNG) + тёмная мягкая плашка (PNG), иконка, Noto Sans SemiBold
            local row = Create("Frame", { Size = UDim2.fromOffset(0, ROW_H), AutomaticSize = AX, BackgroundTransparency = 1, ZIndex = 41, Parent = holder })
            local barId = Library:GetIcon("kb_bar")
            local bar, barProp
            if barId then
                -- [v31] как у NL: полоска-«веретено» со свечением - из точки, шире чуть выше середины, к низу снова в точку
                bar = Create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -6, 0.5, -1.5), Size = UDim2.fromOffset(14, 35),
                    BackgroundTransparency = 1, Image = barId, ZIndex = 42, Parent = row })
                barProp = "ImageTransparency"
            else
                bar = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(2, 19),
                    BorderSizePixel = 0, ZIndex = 42, Parent = row })
                Corner(bar, 1)
                barProp = "BackgroundTransparency"
            end
            local box, boxProp, pad = SoftBg(row, "kb_ind", SOFT_SLICE, BLOB, 41, 9)
            box.Position = UDim2.fromOffset(7 - pad, -pad)
            box.Size = UDim2.fromOffset(0, ROW_H + pad * 2)
            box.AutomaticSize = AX
            Pad(box, 9 + pad, 18 + pad, 0, 3) -- снизу +3: иконка и текст на 1.5px выше центра, как у NL
            List(box, Enum.FillDirection.Horizontal, 8, nil, Enum.VerticalAlignment.Center)
            local slot = Create("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 42, Parent = box })
            local T = Toggles[idx]
            local sinfo = KL.Status[idx]
            local icon = Icon(slot, (sinfo and sinfo.Icon) or (T and T.BindIcon) or "kb_key", nil, 16, true)
            icon.ZIndex = 42
            local label = Text({ Text = "", TextSize = 20, FontFace = BindFont(W_SEMI), ColorKey = false, Size = UDim2.fromOffset(0, ROW_H),
                AutomaticSize = AX, LayoutOrder = 2, ZIndex = 42, Parent = box })
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            local it = { Idx = idx, Row = row, Box = box, BoxProp = boxProp, Bar = bar, BarProp = barProp, Icon = icon, Label = label, Y = 0 }
            fade(it, 1)
            return it
        end

        function KL:Refresh()
            local shown = KL.Enabled and not Library.Unloaded
            local want = {}
            local order = {}
            if shown then
                for _, idx in ipairs(ActiveBinds()) do want[idx] = true order[#order + 1] = idx end
                for key in pairs(KL.Status) do if not want[key] then want[key] = true order[#order + 1] = key end end
            end
            for i = #KL.Order, 1, -1 do
                local idx = KL.Order[i]
                if not want[idx] then
                    local it = KL.Items[idx]
                    table.remove(KL.Order, i)
                    KL.Items[idx] = nil
                    Tw(it.Row, T_OUT, { Position = UDim2.fromOffset(-16, it.Y) })
                    fadeTo(it, 1, T_OUT, function() it.Row:Destroy() end)
                end
            end
            for _, idx in ipairs(order) do
                if want[idx] and not KL.Items[idx] then
                    local it = makeItem(idx)
                    it.New = true
                    KL.Items[idx] = it
                    table.insert(KL.Order, idx)
                end
            end
            local c = Library.KeybindColor
            for i, idx in ipairs(KL.Order) do
                local it = KL.Items[idx]
                local T = Toggles[idx]
                local sinfo = KL.Status[idx]
                local txt = sinfo and tostring(sinfo.Text) or tostring(T and T.Text or idx)
                if it.Label.Text ~= txt then it.Label.Text = txt end
                local ff = BindFont(W_SEMI)
                if it.Label.FontFace ~= ff then it.Label.FontFace = ff end
                local col = sinfo and sinfo.Color or c
                if it.BarProp == "ImageTransparency" then it.Bar.ImageColor3 = col else it.Bar.BackgroundColor3 = col end
                it.Label.TextColor3 = col
                if it.Icon:IsA("ImageLabel") then it.Icon.ImageColor3 = col else it.Icon.BackgroundColor3 = col end
                local y = (i - 1) * (ROW_H + GAP)
                if it.New then
                    it.New, it.Y = nil, y
                    it.Row.Position = UDim2.fromOffset(Library.Animations and -16 or 0, y)
                    Tw(it.Row, T_IN, { Position = UDim2.fromOffset(0, y) })
                    fadeTo(it, 0, T_IN)
                elseif it.Y ~= y then
                    it.Y = y
                    Tw(it.Row, T_IN, { Position = UDim2.fromOffset(0, y) })
                end
            end
            KL.Count = #KL.Order
            local editing = Library.Toggled == true and shown
            holder.Size = UDim2.fromOffset(220, math.max(KL.Count, 1) * (ROW_H + GAP) - GAP)
            hint.Visible = editing
            hintStroke.Transparency = editing and 0.3 or 1
            hintLabel.Visible = editing and KL.Count == 0
            holder.Visible = shown
        end
        -- [v42] статус-строки (не кейбинды): SLOW и т.п. info = { Text, Icon?, Color? } или nil чтобы убрать
        function KL:SetStatus(key, info)
            if (info == nil) == (KL.Status[key] == nil) and info == nil then return end
            KL.Status[key] = info
            KL:Refresh()
        end
        DragWhenMenuOpen(holder)

        ------------------------------------------------ окно Hotkeys
        local HEAD_H, LINE_H, PADX, PITCH, FIRST = 26, 20, 8, 32, 6 -- [v30] замерено по скрину NL
        local HK = { Enabled = true, Items = {}, Order = {}, Count = 0, ColX = 0, Width = 0 }
        self.HotkeyList = HK
        local win = Create("Frame", { Name = "Hotkeys", Position = UDim2.new(0.27, 0, 0.24, 0), Size = UDim2.fromOffset(150, HEAD_H),
            BackgroundTransparency = 1, Active = true, ZIndex = 40, Parent = ScreenGui })
        HK.Frame = win
        local head = Create("Frame", { Size = UDim2.fromOffset(110, HEAD_H), BackgroundTransparency = 1, ZIndex = 41, Parent = win })
        -- [v29] шапка - нарисованная мягкая пилюля (PNG)
        local headBg, headProp, hpad = SoftBg(head, "kb_pill", PILL_SLICE, BLOB, 41, HEAD_H / 2)
        headBg.Position = UDim2.fromOffset(-hpad, -hpad)
        headBg.Size = UDim2.new(1, hpad * 2, 1, hpad * 2)
        headBg[headProp] = 0.2
        local hslot = Create("Frame", { Position = UDim2.fromOffset(PADX + 3, (HEAD_H - 14) / 2), Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1, ZIndex = 42, Parent = head })
        local hicon = Icon(hslot, "kb_list", "AccentColor", 14, true)
        hicon.ZIndex = 42
        local htext = Text({ Text = "Hotkeys", TextSize = 13, FontFace = BindFont(W_SEMI), ColorKey = false, TextColor3 = Color3.fromRGB(185, 185, 192),
            Position = UDim2.fromOffset(PADX + 22, 0), Size = UDim2.new(1, -PADX - 26, 1, 0), ZIndex = 42, Parent = head })
        -- скрытая «линейка» для ширины названий
        local measure = Text({ Text = "", TextSize = 12, FontFace = BindFont(W_MED), ColorKey = false, TextTransparency = 1,
            Size = UDim2.fromOffset(0, LINE_H), AutomaticSize = AX, Position = UDim2.fromOffset(-2000, 0), Parent = win })
        local function textW(t)
            measure.Text = t
            local ok, w = pcall(function() return measure.TextBounds.X end)
            if not ok or type(w) ~= "number" or w <= 0 then w = #t * 7 end
            return w
        end

        local function makeLine(idx)
            local f = Create("Frame", { Size = UDim2.new(1, 0, 0, LINE_H), BackgroundTransparency = 1, ZIndex = 41, Parent = win })
            -- как у NL: под текстом тёмная мягкая «подложка» по его ширине
            local nameBg, nameProp, npad = SoftBg(f, "kb_soft", SOFT_SLICE, BLOB, 41, 6)
            nameBg.Position = UDim2.fromOffset(PADX - 6 - npad, -npad)
            nameBg.Size = UDim2.fromOffset(0, LINE_H + npad * 2)
            nameBg.AutomaticSize = AX
            Pad(nameBg, 6 + npad, 6 + npad, npad, npad) -- [v33] ФИКС: текст был прижат к верху подложки
            local name = Text({ Text = "", TextSize = 12, FontFace = BindFont(W_MED), ColorKey = false, TextColor3 = Color3.fromRGB(232, 232, 238),
                Size = UDim2.fromOffset(0, LINE_H), AutomaticSize = AX, ZIndex = 42, Parent = nameBg })
            name.TextStrokeColor3 = Color3.new(0, 0, 0)
            -- значок переключателя (как у NL): белая пилюля с тёмной точкой справа
            local sw = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(15, 8),
                BackgroundColor3 = Color3.fromRGB(235, 235, 240), BorderSizePixel = 0, ZIndex = 42, Parent = f })
            Corner(sw, 4)
            local dot = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -2, 0.5, 0), Size = UDim2.fromOffset(5, 5),
                BackgroundColor3 = Color3.fromRGB(20, 20, 26), BorderSizePixel = 0, ZIndex = 43, Parent = sw })
            Corner(dot, 3)
            -- у NL и под значком своя тёмная подложка
            -- [v32] ФИКС: подложка значка была ребёнком белого значка и рисовалась ПОВЕРХ него (дети в Roblox
            -- всегда выше родителя) -> значок выглядел серым. Теперь она соседка значка в строке, под ним.
            local swBg, swProp, spad = SoftBg(f, "kb_soft", SOFT_SLICE, BLOB, 41, 6)
            swBg.AnchorPoint = Vector2.new(0, 0.5)
            swBg.Size = UDim2.fromOffset(15 + 12 + spad * 2, 8 + 12 + spad * 2)
            local ln = { Idx = idx, Frame = f, Name = name, NameBg = nameBg, NameProp = nameProp, Switch = sw, SwitchBg = swBg, SwProp = swProp, SwPad = spad, Dot = dot, Y = 0 }
            return ln
        end
        local function lineFade(ln, a, t, onDone)
            Tw(ln.Name, t, { TextTransparency = a, TextStrokeTransparency = 0.7 + 0.3 * a }, onDone)
            Tw(ln.NameBg, t, { [ln.NameProp] = 0.5 + 0.5 * a })
            Tw(ln.SwitchBg, t, { [ln.SwProp] = 0.5 + 0.5 * a })
            Tw(ln.Switch, t, { BackgroundTransparency = a })
            Tw(ln.Dot, t, { BackgroundTransparency = a })
        end

        function HK:Refresh()
            local shown = HK.Enabled and not Library.Unloaded
            local list = shown and ActiveBinds() or {}
            local hf, mf = BindFont(W_SEMI), BindFont(W_MED)
            if htext.FontFace ~= hf then htext.FontFace = hf end
            if measure.FontFace ~= mf then measure.FontFace = mf end
            local want = {}
            for _, idx in ipairs(list) do want[idx] = true end
            for i = #HK.Order, 1, -1 do
                local idx = HK.Order[i]
                if not want[idx] then
                    local ln = HK.Items[idx]
                    table.remove(HK.Order, i)
                    HK.Items[idx] = nil
                    lineFade(ln, 1, T_OUT, function() ln.Frame:Destroy() end)
                end
            end
            for _, idx in ipairs(list) do
                if not HK.Items[idx] then
                    local ln = makeLine(idx)
                    ln.New = true
                    HK.Items[idx] = ln
                    table.insert(HK.Order, idx)
                end
            end
            -- правая колонка = самое длинное название + отступ
            local maxW = textW("Hotkeys") - 20
            for _, idx in ipairs(HK.Order) do
                local T = Toggles[idx]
                local txt = tostring(T and T.Text or idx)
                local ln = HK.Items[idx]
                if ln.Name.Text ~= txt then ln.Name.Text = txt end
                local ff = BindFont(W_MED)
                if ln.Name.FontFace ~= ff then ln.Name.FontFace = ff end
                maxW = math.max(maxW, textW(txt))
            end
            local colX = math.floor(PADX + maxW + 22)
            local width = colX + 15 + PADX + 4
            for i, idx in ipairs(HK.Order) do
                local ln = HK.Items[idx]
                local y = HEAD_H + FIRST + (i - 1) * PITCH
                local b = Library.Binds[idx]
                -- [v55] в списке только включённые -> точка всегда справа (раньше у Hold была слева)
                ln.Dot.Position = UDim2.new(1, -2, 0.5, 0)
                ln.Dot.AnchorPoint = Vector2.new(1, 0.5)
                if ln.New then
                    ln.New, ln.Y = nil, y
                    ln.Frame.Position = UDim2.fromOffset(0, y)
                    ln.Switch.Position = UDim2.new(0, colX, 0.5, 0)
                    ln.SwitchBg.Position = UDim2.new(0, colX - 6 - ln.SwPad, 0.5, 0)
                    ln.Name.TextTransparency, ln.Name.TextStrokeTransparency = 1, 1
                    ln.NameBg[ln.NameProp], ln.SwitchBg[ln.SwProp] = 1, 1
                    ln.Switch.BackgroundTransparency, ln.Dot.BackgroundTransparency = 1, 1
                    lineFade(ln, 0, T_IN)
                else
                    if ln.Y ~= y then ln.Y = y Tw(ln.Frame, T_IN, { Position = UDim2.fromOffset(0, y) }) end
                    if ln.ColX ~= colX then
                        Tw(ln.Switch, T_IN, { Position = UDim2.new(0, colX, 0.5, 0) })
                        Tw(ln.SwitchBg, T_IN, { Position = UDim2.new(0, colX - 6 - ln.SwPad, 0.5, 0) })
                    end
                end
                ln.ColX = colX
            end
            if HK.Width ~= width then
                HK.Width = width
                Tw(head, T_IN, { Size = UDim2.fromOffset(width, HEAD_H) })
            end
            HK.Count = #HK.Order
            win.Size = UDim2.fromOffset(width, HEAD_H + FIRST + math.max(HK.Count, 0) * PITCH)
            win.Visible = shown and (HK.Count > 0 or Library.Toggled == true)
        end
        DragWhenMenuOpen(win)

        ------------------------------------------------ общее
        function KL:Serialize()
            return { enabled = KL.Enabled, color = Library.KeybindColor:ToHex(), hotkeys = HK.Enabled,
                ind = PosOf(holder), win = PosOf(win) }
        end
        function KL:Load(d)
            if type(d) ~= "table" then return end
            if type(d.enabled) == "boolean" then KL.Enabled = d.enabled end
            if type(d.hotkeys) == "boolean" then HK.Enabled = d.hotkeys end
            if type(d.color) == "string" then pcall(function() Library.KeybindColor = Color3.fromHex(d.color) end) end
            SetPos(holder, d.ind)
            SetPos(win, d.win)
            KL:Refresh()
            HK:Refresh()
        end

        local acc = 0
        Connect(RunService.Heartbeat, function(dt)
            acc += dt or 0
            if acc < 0.1 then return end
            acc = 0
            KL:Refresh()
            HK:Refresh()
        end)
        KL:Refresh()
        HK:Refresh()
        return KL
    end

    function Library:CreateWatermark(info)
        info = info or {}
        if self.WatermarkObj then return self.WatermarkObj end
        local WM = {
            Enabled = true, AltColor = Color3.fromRGB(240, 160, 130),
            Items = { Logo = true, Framerate = true, Latency = true, Username = true, Time = true, Avatar = true },
            Order = {}, Title = tostring(info.Title or "Menu"), Cells = {},
        }
        for _, it in ipairs(WM_ITEMS) do table.insert(WM.Order, it.Key) end
        self.WatermarkObj = WM

        -- ФИКС «взрыва»: раньше у плашки был AutomaticSize + UIListLayout, и тень-ребёнок
        -- раскладывалась как пункт и растягивала плашку на весь экран. Теперь раскладка
        -- ручная (нужна и для перетаскивания), ширину считает код.
        -- Позиция: у самого верха экрана, как у NL (над полосой Roblox сверху)
        local insetY = 0
        pcall(function() insetY = GuiService:GetGuiInset().Y end)
        local PADL, GAP, ICON_W, AV = 9, 10, 17, 16
        local bar = Button({
            Name = "Watermark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6 - insetY),
            Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 0.35, ZIndex = 40, Parent = ScreenGui,
        })
        Theme(bar, { BackgroundColor3 = "MainColor" })
        Corner(bar, 7)
        Shadow(bar, 7) -- безопасно: размер плашки задаётся кодом, раскладки внутри нет
        WM.Bar = bar

        for _, it in ipairs(WM_ITEMS) do
            local cell = Create("Frame", { Size = UDim2.fromOffset(0, 24), BackgroundTransparency = 1, Visible = false, ZIndex = 1, Parent = bar })
            local C = { Key = it.Key, Cell = cell, Shown = false }
            if it.Key == "Avatar" then
                C.Fixed = AV
                C.Avatar = Create("ImageLabel", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(AV, AV),
                    BorderSizePixel = 0, Image = "", Parent = cell })
                Theme(C.Avatar, { BackgroundColor3 = "ItemColor" })
                Corner(C.Avatar, 8)
            elseif it.Key == "Logo" then
                -- [v34] перед названием - бейдж-логотип, как в шапке меню («VH» в тёмном квадрате)
                C.Pre = 21
                C.Badge = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16),
                    BackgroundColor3 = Color3.fromRGB(4, 5, 9), BorderSizePixel = 0, Parent = cell })
                Corner(C.Badge, 4)
                C.BadgeStroke = Stroke(C.Badge, "OutlineColor")
                C.BadgeText = Text({ Text = tostring(Library.LogoText or "UI"), TextSize = 8, FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center,
                    Size = UDim2.fromScale(1, 1), Parent = C.Badge })
                C.Label = Text({ Text = WM.Title, TextSize = 14, FontFace = F(W_BOLD), ColorKey = false, Position = UDim2.fromOffset(C.Pre, 0),
                    Size = UDim2.new(1, -C.Pre, 1, 0), Parent = cell })
            else
                local holder = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Parent = cell })
                C.Icon = Icon(holder, it.Icon, nil, 12, true)
                C.Label = Text({ Text = "", TextSize = 13, FontFace = F(W_SEMI), ColorKey = false, Position = UDim2.fromOffset(ICON_W, 0), Size = UDim2.new(1, -ICON_W, 1, 0), Parent = cell })
            end
            -- ФИКС дёрганья: невидимая «линейка» с тем же текстом, где все цифры заменены на 0.
            -- Ширина пункта берётся по ней, поэтому 65 -> 68 MS или 1 -> 2 VAR ширину не меняют.
            if C.Label then
                C.Measure = Text({ Text = "", TextSize = C.Label.TextSize, FontFace = C.Label.FontFace, ColorKey = false,
                    TextTransparency = 1, Size = UDim2.fromScale(0, 1), Parent = cell })
            end
            -- зона захвата пункта (перетаскивание и правый клик)
            C.Hit = Button({ Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = cell })
            WM.Cells[it.Key] = C
        end
        local avatar = WM.Cells.Avatar.Avatar
        task.spawn(function()
            local ok, img = pcall(function()
                return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            end)
            if ok and avatar.Parent then avatar.Image = img end
        end)

        -- данные
        local pings, frames, fpsT, fps = {}, 0, 0, 0
        local function ping()
            local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
            if ok and type(v) == "number" then return v end
            ok, v = pcall(function() return LP:GetNetworkPing() * 1000 end)
            return ok and type(v) == "number" and v or 0
        end
        local function values()
            local v = {}
            local p = ping()
            table.insert(pings, p)
            if #pings > 8 then table.remove(pings, 1) end
            local mean = 0
            for _, x in ipairs(pings) do mean += x end
            mean /= #pings
            local dev = 0
            for _, x in ipairs(pings) do dev += math.abs(x - mean) end
            -- до первого полного окна 0.5s считаем по уже набранным кадрам, чтобы не показывать 0
            v.Latency, v.Var = p, dev / #pings
            v.Framerate = fps > 0 and fps or (fpsT > 0 and frames / fpsT or 0)
            local okM, mem = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
            v.Memory = okM and mem or 0
            -- [v45] скорость по реальному смещению (AssemblyLinearVelocity у игры бывает ~16 на месте, напр. у генератора)
            local okS, spd = pcall(function()
                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if not hrp then return 0 end
                local now, pos = os.clock(), hrp.Position
                local tr = Library._SpeedTrack
                if not tr or tr.Root ~= hrp or now - tr.T > 1 then
                    Library._SpeedTrack = { Root = hrp, Pos = pos, T = now, V = 0 }
                    return 0
                end
                local dt = now - tr.T
                if dt >= 0.05 then
                    local d = pos - tr.Pos
                    tr.V = Vector3.new(d.X, 0, d.Z).Magnitude / dt
                    tr.Pos, tr.T = pos, now
                end
                return tr.V
            end)
            v.Speed = okS and spd or 0
            return v
        end
        local function fmt(key, v)
            if key == "Speed" then return string.format("%d SPEED", math.floor(v.Speed + 0.5)) end
            if key == "Framerate" then return string.format("%d FPS", math.floor(v.Framerate + 0.5)) end
            if key == "Memory" then return string.format("%d MB", math.floor(v.Memory + 0.5)) end
            if key == "Latency" then return string.format("%d MS", math.floor(v.Latency + 0.5)) end
            if key == "Var" then return string.format("%d VAR", math.floor(v.Var + 0.5)) end
            if key == "Server" then
                local id = tostring(game.JobId or "")
                return id ~= "" and string.upper(string.sub(id, 1, 8)) or "LOCAL"
            end
            if key == "Preset" then return tostring(Library.ConfigName or "default") end
            if key == "Username" then return LP.Name end
            if key == "Time" then return os.date("%H:%M") end
            return ""
        end

        -- ширина пункта: иконка 12 + 5 + ширина текста
        local function textW(lbl)
            local ok, b = pcall(function() return lbl.TextBounds end)
            if ok and typeof(b) == "Vector2" and b.X > 0 then return b.X end
            return #tostring(lbl.Text) * 7 -- шрифт ещё не загрузился
        end
        -- ширина по «линейке» (цифры -> 0) + запас: растёт сразу, а уменьшается только если
        -- значение 2 секунды подряд короче (100 -> 99 FPS не дёргает плашку туда-сюда)
        local function cellW(C)
            if C.Fixed then return C.Fixed end
            if C.W then return C.W end
            return math.ceil((C.Icon and ICON_W or 0) + (C.Pre or 0) + textW(C.Label))
        end
        local function measure(C)
            if C.Fixed then C.W = C.Fixed return end
            if C.BadgeText and Library.LogoText and C.BadgeText.Text ~= Library.LogoText then C.BadgeText.Text = Library.LogoText end
            C.Measure.Text = (string.gsub(tostring(C.Label.Text), "%d", "0"))
            local want = math.ceil((C.Icon and ICON_W or 0) + (C.Pre or 0) + math.max(textW(C.Label), textW(C.Measure)))
            local now = os.clock()
            if not C.W or want >= C.W then
                C.W, C.ShrinkAt = want, nil
            else
                C.ShrinkAt = C.ShrinkAt or (now + 2)
                if now >= C.ShrinkAt then C.W, C.ShrinkAt = want, nil end
            end
        end
        local function alpha(C, t, instant)
            local now = instant or not Library.Animations
            if C.Avatar then
                if now then C.Avatar.ImageTransparency, C.Avatar.BackgroundTransparency = t, t
                else Anim(C.Avatar, 0.15, { ImageTransparency = t, BackgroundTransparency = t }) end
                return
            end
            local props = { TextTransparency = t }
            if now then C.Label.TextTransparency = t else Anim(C.Label, 0.15, props) end
            if C.Icon and C.Icon:IsA("ImageLabel") then
                if instant or not Library.Animations then C.Icon.ImageTransparency = t else Anim(C.Icon, 0.15, { ImageTransparency = t }) end
            end
            if C.Badge then
                if now then C.Badge.BackgroundTransparency, C.BadgeText.TextTransparency, C.BadgeStroke.Transparency = t, t, t
                else
                    Anim(C.Badge, 0.15, { BackgroundTransparency = t })
                    Anim(C.BadgeText, 0.15, { TextTransparency = t })
                    Anim(C.BadgeStroke, 0.15, { Transparency = t })
                end
            end
        end

        -- АНИМАЦИЯ перестановки (замер с видео 4:35-4:37): пункт едет за курсором полупрозрачным,
        -- остальные плавно раздвигаются, освобождая место; отпустил - встаёт в щель.
        local drag = nil -- { Key, Gap, Grab }
        local function visibleOrder()
            local vis = {}
            for _, k in ipairs(WM.Order) do
                if WM.Items[k] and (not drag or k ~= drag.Key) then table.insert(vis, k) end
            end
            return vis
        end
        local function move(inst, x, instant)
            local pos = UDim2.fromOffset(x, 0)
            if instant or not Library.Animations then inst.Position = pos else Anim(inst, 0.15, { Position = pos }) end
        end
        local function layout(instant)
            local x = PADL
            local vis = visibleOrder()
            local gapW = drag and (cellW(WM.Cells[drag.Key]) + GAP) or 0
            for i, k in ipairs(vis) do
                if drag and drag.Gap == i - 1 then x += gapW end
                local C = WM.Cells[k]
                measure(C)
                local w = cellW(C)
                C.Cell.Size = UDim2.fromOffset(w, 24)
                move(C.Cell, x, instant or not C.Placed)
                C.Placed = true
                x += w + GAP
            end
            if drag and drag.Gap >= #vis then x += gapW end
            -- справа поле 9, а если последним стоит аватар - 4 (как у NL)
            local last = (drag and drag.Gap >= #vis) and drag.Key or vis[#vis]
            x += (last == "Avatar" and 4 or 9) - GAP
            local width = math.max(x, 24)
            if instant or not Library.Animations then bar.Size = UDim2.fromOffset(width, 24)
            else Anim(bar, 0.15, { Size = UDim2.fromOffset(width, 24) }) end
        end
        WM.Layout = layout

        function WM:Refresh(instant)
            bar.Visible = self.Enabled
            if not self.Enabled then return end
            local v = values()
            for _, it in ipairs(WM_ITEMS) do
                local C = self.Cells[it.Key]
                local on = self.Items[it.Key] == true
                -- АНИМАЦИЯ: пункт появляется/исчезает плавно (как на видео при включении пунктов)
                if on and not C.Shown then
                    C.Shown, C.Placed = true, false
                    C.Cell.Visible = true
                    alpha(C, 1, true)
                    alpha(C, 0, instant)
                elseif not on and C.Shown then
                    C.Shown = false
                    if instant or not Library.Animations then
                        C.Cell.Visible = false
                    else
                        alpha(C, 1)
                        task.delay(0.15, function() if not C.Shown then C.Cell.Visible = false end end)
                    end
                end
                if on and it.Key ~= "Avatar" then
                    if it.Key == "Logo" then
                        C.Label.Text = self.Title
                        C.Label.TextColor3 = Scheme.FontColor
                    else
                        local warn = WM_WARN[it.Key] and WM_WARN[it.Key](v[it.Key] or 0)
                        C.Label.Text = fmt(it.Key, v)
                        C.Label.TextColor3 = warn and self.AltColor or Scheme.ValueColor
                        local ic = warn and self.AltColor or Scheme.AccentColor
                        if C.Icon then
                            if C.Icon:IsA("ImageLabel") then C.Icon.ImageColor3 = ic else C.Icon.BackgroundColor3 = ic end
                        end
                    end
                end
            end
            layout(instant)
        end

        -- перетаскивание пунктов
        for _, it in ipairs(WM_ITEMS) do
            local C = WM.Cells[it.Key]
            C.Hit.MouseButton2Click:Connect(function() WM:OpenSettings() end)
            C.Hit.InputBegan:Connect(function(input)
                if not IsClick(input) or drag then return end
                local start = V2(input.Position)
                local started = false
                BeginDrag(input, function(pos)
                    if not started then
                        if (pos - start).Magnitude < 4 then return end -- это просто клик
                        started = true
                        drag = { Key = it.Key, Gap = 0, Grab = start.X - C.Cell.AbsolutePosition.X }
                        for i, k in ipairs(visibleOrder()) do
                            if WM.Cells[k].Cell.AbsolutePosition.X < C.Cell.AbsolutePosition.X then drag.Gap = i end
                        end
                        C.Cell.ZIndex = 5
                        alpha(C, 0.45) -- «призрак» полупрозрачный, как на видео
                        HideTip()
                        Anim(C.Cell, 0.01, { Position = C.Cell.Position }) -- гасим твин раскладки на этом пункте
                        layout(false) -- щель на исходном месте сразу
                    end
                    -- пункт едет за курсором в пределах плашки
                    local w = cellW(C)
                    local bx = bar.AbsolutePosition.X
                    local x = math.clamp(pos.X - bx - drag.Grab, PADL, math.max(PADL, bar.AbsoluteSize.X - w - PADL))
                    C.Cell.Position = UDim2.fromOffset(x, 0)
                    -- щель туда, где центр «призрака» относительно центров остальных
                    local center, gap = x + w / 2, 0
                    local cx = PADL
                    for i, k in ipairs(visibleOrder()) do
                        local kw = cellW(WM.Cells[k])
                        if center > cx + kw / 2 then gap = i end
                        cx += kw + GAP
                    end
                    if gap ~= drag.Gap then
                        drag.Gap = gap
                        layout(false)
                    end
                end, function()
                    if not started or not drag then return end
                    local vis = visibleOrder()
                    local key, gap = drag.Key, drag.Gap
                    -- вставляем в полный порядок перед следующим видимым пунктом
                    local order = {}
                    for _, k in ipairs(WM.Order) do if k ~= key then table.insert(order, k) end end
                    local before = vis[gap + 1]
                    local pos = #order + 1
                    if before then for i, k in ipairs(order) do if k == before then pos = i break end end
                    elseif vis[#vis] then for i, k in ipairs(order) do if k == vis[#vis] then pos = i + 1 break end end end
                    table.insert(order, pos, key)
                    WM.Order = order
                    drag = nil
                    C.Cell.ZIndex = 1
                    alpha(C, 0)
                    layout(false)
                    WM:Changed()
                end)
            end)
        end

        local acc = 0
        Connect(RunService.Heartbeat, function(dt)
            frames += 1
            fpsT += dt
            if fpsT >= 0.5 then fps = frames / fpsT frames, fpsT = 0, 0 end
            acc += dt
            if acc >= 0.25 then acc = 0 Safe(function() WM:Refresh() end) end
        end)

        function WM:Changed()
            self:Refresh()
            if Library._ThemeSave then Library._ThemeSave() end
        end
        function WM:Serialize()
            local items = {}
            for _, it in ipairs(WM_ITEMS) do if self.Items[it.Key] then table.insert(items, it.Key) end end
            return { enabled = self.Enabled, avatar = self.Items.Avatar == true, color = self.AltColor:ToHex(), items = items, order = table.clone(self.Order) }
        end
        function WM:Load(d)
            if type(d) ~= "table" then return end
            if type(d.enabled) == "boolean" then self.Enabled = d.enabled end

            if type(d.color) == "string" then pcall(function() self.AltColor = Color3.fromHex(d.color) end) end
            if type(d.items) == "table" then
                self.Items = {}
                for _, k in ipairs(d.items) do self.Items[k] = true end
            end
            -- старые сохранения: аватар хранился отдельным флагом
            if type(d.avatar) == "boolean" and not (type(d.items) == "table" and table.find(d.items, "Avatar")) then
                self.Items.Avatar = d.avatar or nil
            end
            if type(d.order) == "table" then
                -- сохранённый порядок + новые пункты, которых в нём ещё нет
                local known, order = {}, {}
                for _, it in ipairs(WM_ITEMS) do known[it.Key] = true end
                for _, k in ipairs(d.order) do if known[k] and not table.find(order, k) then table.insert(order, k) end end
                for _, it in ipairs(WM_ITEMS) do if not table.find(order, it.Key) then table.insert(order, it.Key) end end
                self.Order = order
            end
            self:Refresh()
        end

        -- панель настроек (правый клик), как у NL: слева «Watermark», справа список Items
        local SET_W, LIST_W, ROW, OVER, M = 170, 168, 26, 18, 10
        function WM:OpenSettings()
            local listH = #WM_ITEMS * ROW + 10
            local setH = 32 + ROW * 2 + 9 + ROW + 8
            local W, H = SET_W + LIST_W - OVER + M * 2, math.max(listH, setH) + M * 2
            OpenPopup(bar, W, H, function(frame, close)
                local function panel(x, w, h)
                    local f = Button({ BackgroundTransparency = Library.Transparency, Position = UDim2.fromOffset(x, M), Size = UDim2.fromOffset(w, h), Parent = frame })
                    Theme(f, { BackgroundColor3 = "GroupColor" })
                    Corner(f, 10)
                    Stroke(f)
                    Shadow(f, 10)
                    return f
                end
                local function row(parent, y, icon, text, x0)
                    local r = Button({ Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, ROW), Parent = parent })
                    Corner(r, 6)
                    Theme(r, { BackgroundColor3 = "ItemColor" })
                    r.MouseEnter:Connect(function() Tween(r, 0.12, { BackgroundTransparency = 0.5 }) end)
                    r.MouseLeave:Connect(function() Tween(r, 0.12, { BackgroundTransparency = 1 }) end)
                    local holder = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, x0, 0.5, 0), Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Parent = r })
                    local ic = Icon(holder, icon, nil, 13, true)
                    local lb = Text({ Text = text, TextSize = 13, ColorKey = false, Position = UDim2.fromOffset(x0 + 12, 0), Size = UDim2.new(1, -(x0 + 14), 1, 0), ClipsDescendants = true, Parent = r })
                    return r, ic, lb
                end
                local function paint(ic, lb, col)
                    lb.TextColor3 = col
                    if ic then if ic:IsA("ImageLabel") then ic.ImageColor3 = col else ic.BackgroundColor3 = col end end
                end

                -- левая панель
                local set = panel(M, SET_W, setH)
                Text({ Text = "Watermark", TextSize = 14, FontFace = F(W_BOLD), Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 22), Parent = set })
                local list
                local itemsRow, ic1, lb1 = row(set, 32, "wm_items", "Items", 14)
                paint(ic1, lb1, Scheme.ValueColor)
                local colRow, ic2, lb2 = row(set, 32 + ROW, "wm_color", "Additional Color", 14)
                paint(ic2, lb2, Scheme.ValueColor)
                lb2.Size = UDim2.new(1, -(26 + 30), 1, 0)
                local swHolder = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, Parent = colRow })
                NewColorPicker(nil, { Default = WM.AltColor, Title = "Additional Color", Callback = function(c)
                    WM.AltColor = c
                    WM:Changed()
                end }, swHolder, 1):Display()
                local sep = Create("Frame", { Position = UDim2.fromOffset(12, 32 + ROW * 2 + 4), Size = UDim2.new(1, -24, 0, 1), BorderSizePixel = 0, Parent = set })
                Theme(sep, { BackgroundColor3 = "SeparatorColor" })
                local avRow, ic3, lb3 = row(set, 32 + ROW * 2 + 9, "wm_user", "Display Avatar", 14)
                local listPaint = {}
                local function paintAv() paint(ic3, lb3, WM.Items.Avatar and Scheme.FontColor or Scheme.SubColor) end
                paintAv()
                local avCheck = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Parent = avRow })
                local avIc = Icon(avCheck, "wm_check", "AccentColor", 11, false)
                if avIc then avIc.Visible = WM.Items.Avatar == true end
                local function syncAv()
                    if avIc then avIc.Visible = WM.Items.Avatar == true end
                    paintAv()
                    if listPaint.Avatar then listPaint.Avatar() end
                end
                avRow.MouseButton1Click:Connect(function()
                    WM.Items.Avatar = (not WM.Items.Avatar) or nil
                    syncAv()
                    WM:Changed()
                end)

                -- правая панель: список пунктов с галочками
                local function openList()
                    if list then list.Visible = not list.Visible return end
                    list = panel(M + SET_W - OVER, LIST_W, listH)
                    list.ZIndex = 3
                    for i, it in ipairs(WM_ITEMS) do
                        local r, ic, lb = row(list, 5 + (i - 1) * ROW, it.Icon, it.Text, 30)
                        local ch = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 11, 0.5, 0), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1, Parent = r })
                        local chIc = Icon(ch, "wm_check", "FontColor", 11, false)
                        local function p()
                            local on = WM.Items[it.Key] == true
                            if chIc then chIc.Visible = on end
                            paint(ic, lb, on and Scheme.FontColor or Scheme.SubColor)
                        end
                        p()
                        listPaint[it.Key] = p
                        r.MouseButton1Click:Connect(function()
                            WM.Items[it.Key] = not WM.Items[it.Key] or nil
                            p()
                            if it.Key == "Avatar" then syncAv() end
                            WM:Changed()
                        end)
                    end
                end
                itemsRow.MouseButton1Click:Connect(openList)
                return nil
            end, false, true)
        end
        bar.MouseButton2Click:Connect(function() WM:OpenSettings() end)

        WM:Refresh(true)
        return WM
    end

    --------------------------------------------------------
    -- unload
    --------------------------------------------------------
    function Library:OnUnload(fn) table.insert(self._UnloadCb, fn) end

    function Library:Unload()
        if self.Unloaded then return end
        self.Unloaded = true
        for _, fn in ipairs(self._UnloadCb) do Safe(fn) end
        pcall(function() Acrylic:Destroy() end) -- ЭФФЕКТ: вернуть DepthOfField игры, убрать стекло
        for _, c in ipairs(self._Conns) do pcall(function() c:Disconnect() end) end
        table.clear(self._Conns)
        pcall(function() ScreenGui:Destroy() end)
    end

    --------------------------------------------------------
    -- SaveManager (формат файлов совместим с Obsidian/Linoria)
    --------------------------------------------------------
    local SaveManager = { Folder = "NeverUI", Ignore = {}, IgnoreTheme = false, Current = nil }

    local function HasFS()
        return writefile and readfile and isfile and isfolder and makefolder and listfiles and true or false
    end

    function SaveManager:SetLibrary(lib) self.Library = lib end
    function SaveManager:IgnoreThemeSettings() self.IgnoreTheme = true end
    function SaveManager:SetIgnoreIndexes(list)
        for _, idx in ipairs(list or {}) do self.Ignore[idx] = true end
    end
    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end
    function SaveManager:BuildFolderTree()
        if not HasFS() then return end
        local path = ""
        for part in string.gmatch(self.Folder .. "/settings", "[^/]+") do
            path = path == "" and part or (path .. "/" .. part)
            if not isfolder(path) then pcall(makefolder, path) end
        end
    end
    function SaveManager:_Path(name) return self.Folder .. "/settings/" .. name .. ".json" end
    function SaveManager:_Ignored(idx)
        if self.Ignore[idx] then return true end
        if string.sub(idx, 1, 12) == "SaveManager_" then return true end
        return self.IgnoreTheme and string.sub(idx, 1, 13) == "ThemeManager_"
    end

    function SaveManager:Save(name)
        if not HasFS() then return false, "executor has no file functions" end
        name = tostring(name or "")
        if name:gsub("%s", "") == "" then return false, "empty config name" end
        local objects = {}
        for idx, t in pairs(Toggles) do
            if not self:_Ignored(idx) then table.insert(objects, { type = "Toggle", idx = idx, value = t.Value }) end
        end
        for idx, b in pairs(Library.Binds) do -- БИНДЫ
            if not self:_Ignored(idx) then table.insert(objects, { type = "Bind", idx = idx, key = b.Key, mode = b.Mode }) end
        end
        for idx, o in pairs(Options) do
            if not self:_Ignored(idx) then
                if o.Type == "Slider" then
                    table.insert(objects, { type = "Slider", idx = idx, value = tostring(o.Value) })
                elseif o.Type == "ColorPicker" then
                    table.insert(objects, { type = "ColorPicker", idx = idx, value = o.Value:ToHex(), transparency = o.Transparency })
                elseif o.Type == "KeyPicker" then
                    table.insert(objects, { type = "KeyPicker", idx = idx, key = o.Value, mode = o.Mode })
                elseif o.Type == "Dropdown" then
                    table.insert(objects, { type = "Dropdown", idx = idx, value = o.Value })
                elseif o.Type == "Input" then
                    table.insert(objects, { type = "Input", idx = idx, text = o.Value })
                end
            end
        end
        -- [v94] + значения UI выгруженных Lua-скриптов (SaveManager.Pending), как в SkeetUI
        for idx, o in pairs(self.Pending or {}) do
            if not Toggles[idx] and not Options[idx] then table.insert(objects, o) end
        end
        self.LastObjects = objects
        local ok, encoded = pcall(function() return HttpService:JSONEncode({ objects = objects }) end)
        if not ok then return false, "failed to encode data" end
        self:BuildFolderTree()
        local wok, werr = pcall(writefile, self:_Path(name), encoded)
        if not wok then return false, tostring(werr) end
        self.Current = name
        if Library.Window then Library.Window:SetConfigName(name) end
        return true
    end

    function SaveManager:Load(name)
        if not HasFS() then return false, "executor has no file functions" end
        name = tostring(name or "")
        local path = self:_Path(name)
        if not isfile(path) then return false, "invalid file" end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
        if not ok or type(data) ~= "table" then return false, "decode error" end
        Library:ClearBinds() -- БИНДЫ: у каждого конфига свои
        local binds = {}
        for _, o in ipairs(data.objects or {}) do
            local idx = o.idx
            if idx and not self:_Ignored(idx) then
                if o.type == "Bind" then
                    table.insert(binds, o)
                elseif o.type == "Toggle" then
                    if Toggles[idx] then Toggles[idx]:SetValue(o.value)
                    elseif string.sub(idx, 1, 4) == "Lua_" and self.Pending then self.Pending[idx] = o end -- [v94]
                else
                    if not Options[idx] and string.sub(idx, 1, 4) == "Lua_" and self.Pending then self.Pending[idx] = o end -- [v94]
                    local el = Options[idx]
                    if el then
                        if o.type == "Slider" then
                            el:SetValue(tonumber(o.value))
                        elseif o.type == "ColorPicker" and el.SetValueRGB then
                            pcall(function() el:SetValueRGB(Color3.fromHex(o.value), o.transparency) end)
                        elseif o.type == "KeyPicker" then
                            el:SetValue({ o.key, o.mode })
                        elseif o.type == "Dropdown" then
                            el:SetValue(o.value)
                        elseif o.type == "Input" then
                            el:SetValue(o.text)
                        end
                    end
                end
            end
        end
        -- после значений: режим Always сам включает свой переключатель
        for _, o in ipairs(binds) do Library:SetBind(o.idx, o.key, o.mode) end
        self.Current = name
        if Library.Window then Library.Window:SetConfigName(name) end
        return true
    end

    function SaveManager:Delete(name)
        if not (HasFS() and delfile) then return false, "executor has no delfile" end
        local path = self:_Path(tostring(name or ""))
        if not isfile(path) then return false, "invalid file" end
        local ok, err = pcall(delfile, path)
        if not ok then return false, tostring(err) end
        return true
    end

    function SaveManager:List()
        local out = {}
        if not HasFS() then return out end
        self:BuildFolderTree()
        local ok, files = pcall(listfiles, self.Folder .. "/settings")
        if not ok then return out end
        for _, f in ipairs(files) do
            local n = string.match(f, "([^/\\]+)%.json$")
            if n then table.insert(out, n) end
        end
        table.sort(out)
        return out
    end

    function SaveManager:_AutoloadPath() return self.Folder .. "/settings/autoload.txt" end

    function SaveManager:GetAutoload()
        if HasFS() and isfile(self:_AutoloadPath()) then
            local ok, n = pcall(readfile, self:_AutoloadPath())
            if ok and n ~= "" then return n end
        end
        return nil
    end

    function SaveManager:LoadAutoloadConfig()
        local n = self:GetAutoload()
        if not n then return end
        local ok, err = self:Load(n)
        if ok then
            Library:Notify({ Title = "Config", Description = "Auto loaded config " .. n, Time = 4 })
        else
            Library:Notify({ Title = "Config", Description = "Failed to autoload " .. n .. ": " .. tostring(err), Time = 5 })
        end
    end

    function SaveManager:BuildConfigSection(tab)
        local box = tab:AddRightGroupbox("Configs")
        local function notify(text) Library:Notify({ Title = "Config", Description = text, Time = 4 }) end

        box:AddInput("SaveManager_ConfigName", { Text = "Config name", Placeholder = "name..." })
        box:AddButton({ Text = "Create config", Func = function()
            local n = Options.SaveManager_ConfigName.Value
            local ok, err = self:Save(n)
            if not ok then return notify("Failed to save: " .. tostring(err)) end
            notify("Created config " .. n)
            Options.SaveManager_ConfigList:SetValues(self:List())
            Options.SaveManager_ConfigList:SetValue(n)
        end })
        box:AddDivider()
        box:AddDropdown("SaveManager_ConfigList", { Text = "Config list", Values = self:List() })
        box:AddButton({ Text = "Load config", Func = function()
            local n = Options.SaveManager_ConfigList.Value
            local ok, err = self:Load(n)
            notify(ok and ("Loaded config " .. tostring(n)) or ("Failed to load: " .. tostring(err)))
        end })
        box:AddButton({ Text = "Overwrite config", Func = function()
            local n = Options.SaveManager_ConfigList.Value
            local ok, err = self:Save(n)
            notify(ok and ("Overwrote config " .. tostring(n)) or ("Failed to save: " .. tostring(err)))
        end })
        box:AddButton({ Text = "Delete config", Func = function()
            local n = Options.SaveManager_ConfigList.Value
            local ok, err = self:Delete(n)
            if not ok then return notify("Failed to delete: " .. tostring(err)) end
            notify("Deleted config " .. tostring(n))
            Options.SaveManager_ConfigList:SetValues(self:List())
            Options.SaveManager_ConfigList:SetValue(nil)
        end })
        box:AddButton({ Text = "Refresh list", Func = function()
            Options.SaveManager_ConfigList:SetValues(self:List())
        end })
        box:AddDivider()
        local autoLabel
        box:AddButton({ Text = "Set as autoload", Func = function()
            local n = Options.SaveManager_ConfigList.Value
            if not n or not HasFS() then return end
            pcall(writefile, self:_AutoloadPath(), n)
            autoLabel:SetText("Autoload: " .. n)
            notify("Set " .. n .. " to auto load")
        end })
        box:AddButton({ Text = "Reset autoload", Func = function()
            if HasFS() and delfile and isfile(self:_AutoloadPath()) then pcall(delfile, self:_AutoloadPath()) end
            autoLabel:SetText("Autoload: none")
            notify("Autoload reset")
        end })
        autoLabel = box:AddLabel("Autoload: " .. (self:GetAutoload() or "none"), true)

        if Library.Window then
            Library.Window:SetConfigProvider({
                List = function() return self:List() end,
                Current = function() return self.Current end,
                Load = function(n)
                    local ok, err = self:Load(n)
                    notify(ok and ("Loaded config " .. n) or ("Failed to load: " .. tostring(err)))
                end,
                Save = function()
                    local n = self.Current or "default"
                    local ok, err = self:Save(n)
                    notify(ok and ("Saved config " .. n) or ("Failed to save: " .. tostring(err)))
                    if ok then Options.SaveManager_ConfigList:SetValues(self:List()) end
                end,
            })
        end
    end

    --------------------------------------------------------
    -- ThemeManager (акцент + фон, сохраняется отдельно от конфигов)
    --------------------------------------------------------
    local ThemeManager = { Folder = "NeverUI" }
    function ThemeManager:SetLibrary(lib) self.Library = lib end
    function ThemeManager:SetFolder(folder) self.Folder = folder end
    function ThemeManager:_Path() return self.Folder .. "/theme.json" end

    function ThemeManager:Save()
        if not HasFS() then return end
        pcall(function()
            if not isfolder(self.Folder) then makefolder(self.Folder) end
            writefile(self:_Path(), HttpService:JSONEncode({
                accent = Scheme.AccentColor:ToHex(), main = Scheme.MainColor:ToHex(),
                anim = Library.Animations, theme = Library.ThemeName,
                menuScale = Library.MenuScale, espScale = Library.ESPScale, units = Library.Units,
                transparency = Library.Transparency, blur = Library.Blur, glow = Library.Glow,
                wm = Library.WatermarkObj and Library.WatermarkObj:Serialize() or nil,
                kb = Library.KeybindList and Library.KeybindList:Serialize() or nil,
            }))
        end)
    end

    function ThemeManager:ApplyToTab(tab)
        local box = tab:AddLeftGroupbox("Theme")
        local names = {}
        for _, t in ipairs(Library.Themes) do names[#names + 1] = t.Name end
        box:AddDropdown("ThemeManager_Theme", { Text = "Theme", Values = names, Default = Library.ThemeName,
            Tooltip = "Menu color theme. Accent / background below can still be tweaked on top of it.",
            Callback = function(v)
                if Library._ApplyingTheme or not v then return end
                Library:ApplyTheme(v)
            end })
        box:AddLabel("Accent color"):AddColorPicker("ThemeManager_Accent", { Default = Scheme.AccentColor, Title = "Accent color" })
        box:AddLabel("Background"):AddColorPicker("ThemeManager_Main", { Default = Scheme.MainColor, Title = "Background" })
        local loading = false
        -- АНИМАЦИЯ: выключатель всех анимаций меню (сохраняется в theme.json)
        box:AddToggle("ThemeManager_Animations", { Text = "Animations", Default = Library.Animations, Callback = function(v)
            Library.Animations = v and true or false
            if not loading then self:Save() end
        end })
        -- ЭФФЕКТЫ (по умолчанию - как замерено на видео)
        box:AddSlider("ThemeManager_Transparency", {
            Text = "Transparency", Default = math.floor(Library.Transparency * 100 + 0.5), Min = 0, Max = 40,
            Rounding = 0, Suffix = "%", Callback = function(v)
                Library.Transparency = v / 100
                Library:UpdateColors()
                if not loading then self:Save() end
            end,
        })
        box:AddToggle("ThemeManager_Blur", { Text = "Background blur", Default = Library.Blur,
            Tooltip = "Frosted glass behind the menu. Needs high Roblox graphics quality.", Callback = function(v)
                Library.Blur = v and true or false
                Library.UpdateBlur()
                if not loading then self:Save() end
            end })
        box:AddToggle("ThemeManager_Glow", { Text = "Glow", Default = Library.Glow, Callback = function(v)
            Library.Glow = v and true or false
            Library:UpdateColors()
            if not loading then self:Save() end
        end })
        -- ВАТЕРМАРКА: вкл/выкл тут, остальное - правым кликом по ней (или кнопкой, для телефона)
        Library._ThemeSave = function() if not loading then self:Save() end end
        local wm = Library.WatermarkObj
        if wm then
            box:AddToggle("ThemeManager_Watermark", { Text = "Watermark", Default = wm.Enabled,
                Tooltip = "Right-click the watermark for its settings", Callback = function(v)
                    wm.Enabled = v and true or false
                    wm:Changed()
                end })
            box:AddButton({ Text = "Watermark settings", Func = function() wm:OpenSettings() end })
        end
        -- БИНДЫ: окно со списком биндов (ПКМ по любому переключателю - назначить клавишу)
        local kl = Library:CreateKeybindList()
        box:AddToggle("ThemeManager_KeybindList", { Text = "Hotkeys List", Default = Library.HotkeyList.Enabled, NoBind = true,
            Tooltip = "Window with the binds that are on now. Right-click any toggle to bind a key (Toggle / Hold / Always). Drag it while the menu is open.", Callback = function(v)
                Library.HotkeyList.Enabled = v and true or false
                Library.HotkeyList:Refresh()
                if not loading then self:Save() end
            end })
        box:AddToggle("ThemeManager_Indicators", { Text = "Bind Indicators", Default = kl.Enabled, NoBind = true,
            Tooltip = "Big indicators on the left (like HC / MD in NL) for the binds that are on now.", Callback = function(v)
                kl.Enabled = v and true or false
                kl:Refresh()
                if not loading then self:Save() end
            end }):AddColorPicker("ThemeManager_KeybindColor", { Default = Library.KeybindColor, Title = "Indicator color", Callback = function(c)
                Library.KeybindColor = c
                kl:Refresh()
                if not loading then self:Save() end
            end })

        -- фон задаёт всю тёмную гамму; остальные оттенки - сдвиг яркости, как в исходной палитре
        local SHIFT = {
            BackgroundColor = -0.005, GroupColor = 0.024, OutlineColor = 0.055, SeparatorColor = 0.055,
            ItemColor = 0.098, InputColor = 0.067, InputBorder = 0.086, TrackColor = 0.07,
        }
        -- [v45] акцент меняет только акцент; фон пересчитывает тёмную гамму (как раньше).
        -- При применении темы (Library._ApplyingTheme) пикеры просто показывают её цвета.
        local function applyAccent()
            if Library._ApplyingTheme then return end
            Scheme.AccentColor = Options.ThemeManager_Accent.Value
            Library:UpdateColors()
            if not loading then self:Save() end
        end
        local function applyMain()
            if Library._ApplyingTheme then return end
            local m = Options.ThemeManager_Main.Value
            local h, s, v = m:ToHSV()
            Scheme.MainColor = m
            for key, dv in pairs(SHIFT) do
                Scheme[key] = Color3.fromHSV(h, s, math.clamp(v + dv, 0, 1))
            end
            Library:UpdateColors()
            if not loading then self:Save() end
        end
        Options.ThemeManager_Accent:OnChanged(applyAccent)
        Options.ThemeManager_Main:OnChanged(applyMain)

        box:AddButton({ Text = "Reset theme", Func = function()
            Library:ApplyTheme(Library.ThemeName or "Default") -- сброс правок акцента/фона к выбранной теме
            self:Save()
        end })

        if HasFS() and isfile(self:_Path()) then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(self:_Path())) end)
            if ok and type(data) == "table" then
                loading = true
                -- [v45] сначала тема, поверх - свои правки акцента / фона (если отличаются от темы)
                local th = type(data.theme) == "string" and Library:GetTheme(data.theme)
                if th then pcall(function() Library:ApplyTheme(th.Name) end) end
                local themeMain = th and th.Scheme.MainColor:ToHex() or nil
                local themeAccent = th and th.Scheme.AccentColor:ToHex() or nil
                if type(data.accent) == "string" and string.lower(data.accent) ~= string.lower(themeAccent or "") then
                    pcall(function() Options.ThemeManager_Accent:SetValueRGB(Color3.fromHex(data.accent)) end)
                end
                if type(data.main) == "string" and string.lower(data.main) ~= string.lower(themeMain or "") then
                    pcall(function() Options.ThemeManager_Main:SetValueRGB(Color3.fromHex(data.main)) end)
                end
                if type(data.anim) == "boolean" then pcall(function() Toggles.ThemeManager_Animations:SetValue(data.anim) end) end
                if type(data.transparency) == "number" then pcall(function() Options.ThemeManager_Transparency:SetValue(data.transparency * 100) end) end
                if type(data.blur) == "boolean" then pcall(function() Toggles.ThemeManager_Blur:SetValue(data.blur) end) end
                if type(data.glow) == "boolean" then pcall(function() Toggles.ThemeManager_Glow:SetValue(data.glow) end) end
                if type(data.menuScale) == "number" and Library.SetMenuScale then pcall(function() Library:SetMenuScale(data.menuScale) end) end
                if type(data.espScale) == "number" then Library.ESPScale = math.clamp(data.espScale, 0.5, 2) end
                if data.units == "studs" or data.units == "meters" then Library.Units = data.units end
                if type(data.kb) == "table" then
                    pcall(function() kl:Load(data.kb) end)
                    pcall(function() Toggles.ThemeManager_KeybindList:SetValue(Library.HotkeyList.Enabled) end)
                    pcall(function() Toggles.ThemeManager_Indicators:SetValue(kl.Enabled) end)
                    pcall(function() Options.ThemeManager_KeybindColor:SetValueRGB(Library.KeybindColor) end)
                end
                if wm and type(data.wm) == "table" then
                    pcall(function() wm:Load(data.wm) end)
                    pcall(function() Toggles.ThemeManager_Watermark:SetValue(wm.Enabled) end)
                end
                loading = false
            end
        end
    end

    --------------------------------------------------------------------------------------------
    -- [v94] Совместимость со скриптом ветки SkeetUI (тот же rest.lua запускается и с NeverUI).
    -- Всё, чего в NeverUI не было, но скрипт вызывает: значения по умолчанию, хит-логи, HUD-панели,
    -- Listbox, Group:Destroy, Pending-значения Lua-скриптов, Autoload, настройки меню.
    --------------------------------------------------------------------------------------------
    Library.Theme = "Neverlose"
    Library.ESPTextK = Library.ESPTextK or 1
    Library.StreamerMode = Library.StreamerMode or false
    Library.Confirmations = Library.Confirmations ~= false
    Library.AnimSpeed = Library.AnimSpeed or 1
    Library.ShortNames = Library.ShortNames or {}
    Library.B64Decode = Library.B64Decode or B64Decode
    -- иконки вкладок / подвкладок скрипта ветки skeet -> ближайшие иконки NL
    local NL_ALIAS = { visuals = "world", cat_team = "sub_survivor", cat_enemy = "sub_killer", cat_eye = "sub_spectator",
        cat_bot = "sub_bot", cat_world = "world", cat_fx = "kb_bolt" }
    local origGetIcon = Library.GetIcon
    function Library:GetIcon(name) return origGetIcon(self, NL_ALIAS[name] or name) end
    function Library:GetESPFont() return nil end
    function Library:ApplyESPFont(label) return label end -- у NL ESP-надписи шрифтом скрипта (CONFIG.TagFont)
    function Library:GetSmallFont() return nil end
    function Library:ApplySmallFont(label) return label end
    function Library:ShortName(text) return tostring(text or "") end

    function Group:Destroy()
        pcall(function() self.Holder:Destroy() end)
        local list = self.Page and self.Page.Groups
        if list then for i, g in ipairs(list) do if g == self then table.remove(list, i) break end end end
    end

    -- список строк (Lua-менеджер): { Value, Values, SetValues, SetValue, OnChanged, Refresh }
    function Group:AddListbox(idx, info)
        info = info or {}
        local rows = tonumber(info.Rows) or 6
        local row = self:_Row(rows * 22 + 12, info.Tooltip, info.Text, false)
        local box = Create("ScrollingFrame", { Position = UDim2.fromOffset(ROW_PAD, 6), Size = UDim2.new(1, -ROW_PAD * 2, 1, -12),
            BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = row })
        Theme(box, { BackgroundColor3 = "InputColor", ScrollBarImageColor3 = "AccentColor" })
        Corner(box, 6)
        List(box, nil, 0)
        local LB = { Type = "Listbox", Value = nil, Values = {}, Changed = {}, Callback = info.Callback }
        local buttons = {}
        function LB:Refresh()
            for _, b in ipairs(buttons) do b:Destroy() end
            table.clear(buttons)
            for i, v in ipairs(self.Values) do
                local b = Button({ Size = UDim2.new(1, 0, 0, 22), LayoutOrder = i, Parent = box })
                local t = Text({ Text = tostring(v), TextSize = 13, ColorKey = false, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Parent = b })
                t.TextColor3 = (v == self.Value) and Scheme.AccentColor or Scheme.FontColor
                b.MouseButton1Click:Connect(function() LB:SetValue(v) end)
                buttons[#buttons + 1] = b
            end
        end
        function LB:OnChanged(fn) table.insert(self.Changed, fn) end
        function LB:SetValues(v)
            self.Values = type(v) == "table" and v or {}
            if self.Value ~= nil and not table.find(self.Values, self.Value) then self.Value = nil end
            self:Refresh()
        end
        function LB:SetValue(v)
            if v ~= nil and not table.find(self.Values, v) then return end
            self.Value = v
            self:Refresh()
            Fire(self)
        end
        local vals = info.Values
        if type(vals) == "function" then vals = vals() end
        LB:SetValues(vals or {})
        if idx then Options[idx] = LB end
        return LB
    end

    -- хит-логи слева сверху (плашки как у индикаторов NL)
    function Library:CreateHitLog()
        if self.HitLogObj then return self.HitLogObj end
        self:LoadBindFonts()
        local HL = { Lines = {}, Enabled = true, Time = 5, Max = 6 }
        local holder = Create("Frame", { Name = "HitLog", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(420, 20),
            BackgroundTransparency = 1, Active = true, ZIndex = 40, Parent = ScreenGui })
        local function esc(t) return (tostring(t):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
        local function layout()
            local y = 0
            for _, ln in ipairs(HL.Lines) do
                if ln.Y ~= y then ln.Y = y Tween(ln.Row, 0.12, { Position = UDim2.fromOffset(0, y) }) end
                y += 24
            end
            holder.Size = UDim2.fromOffset(420, math.max(y, 20))
        end
        local function remove(ln)
            for i, l in ipairs(HL.Lines) do if l == ln then table.remove(HL.Lines, i) break end end
            Tween(ln.Text, 0.25, { TextTransparency = 1, TextStrokeTransparency = 1 })
            Tween(ln.Row, 0.25, { BackgroundTransparency = 1 })
            task.delay(0.3, function() pcall(function() ln.Row:Destroy() end) end)
            layout()
        end
        function HL:Push(parts)
            if not self.Enabled or Library.Unloaded then return end
            local acc = Scheme.AccentColor
            local hex = string.format("#%02X%02X%02X", math.floor(acc.R * 255 + 0.5), math.floor(acc.G * 255 + 0.5), math.floor(acc.B * 255 + 0.5))
            local out = {}
            for _, p in ipairs(type(parts) == "table" and parts or { tostring(parts) }) do
                out[#out + 1] = type(p) == "table" and ('<font color="' .. hex .. '">' .. esc(p[1]) .. "</font>") or esc(p)
            end
            local row = Create("Frame", { Position = UDim2.fromOffset(-12, #self.Lines * 24), Size = UDim2.fromOffset(0, 22), AutomaticSize = AX,
                BackgroundColor3 = Color3.fromRGB(14, 12, 16), BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = 40, Parent = holder })
            Corner(row, 6)
            Pad(row, 10, 10, 0, 0)
            local txt = Text({ Text = table.concat(out), RichText = true, TextSize = 14, FontFace = BindFont(W_SEMI), ColorKey = false,
                TextColor3 = Color3.fromRGB(232, 232, 238), TextStrokeTransparency = 0.7, Size = UDim2.fromOffset(0, 22), AutomaticSize = AX,
                ZIndex = 41, Parent = row })
            local ln = { Row = row, Text = txt, Y = #self.Lines * 24 }
            table.insert(self.Lines, ln)
            Tween(row, 0.15, { Position = UDim2.fromOffset(0, ln.Y) })
            while #self.Lines > self.Max do remove(self.Lines[1]) end
            task.delay(self.Time, function() if table.find(HL.Lines, ln) then remove(ln) end end)
            layout()
        end
        function HL:Clear() for i = #self.Lines, 1, -1 do remove(self.Lines[i]) end end
        function HL:Serialize() return { pos = PosOf(holder), enabled = self.Enabled } end
        function HL:Load(d) if type(d) == "table" then SetPos(holder, d.pos) end end
        DragWhenMenuOpen(holder)
        self.HitLogObj = HL
        return HL
    end

    pcall(function() Library:CreateHitLog() end) -- скрипт берёт готовый Library.HitLogObj

    -- HUD-панель (радар, статистика, перки) в стиле секции NL
    Library.HudPanels = Library.HudPanels or {}
    function Library:CreateHudPanel(key, title, w, h, pos)
        if self.HudPanels[key] then return self.HudPanels[key] end
        self:LoadBindFonts()
        local P = { Key = key }
        local holder = Create("Frame", { Name = "Hud_" .. tostring(key), Position = pos or UDim2.fromOffset(20, 200), Size = UDim2.fromOffset(w, h),
            BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 30, ClipsDescendants = true, Parent = ScreenGui })
        Theme(holder, { BackgroundColor3 = "GroupColor" })
        holder.BackgroundTransparency = 0.08
        Corner(holder, 8)
        Stroke(holder, "OutlineColor")
        local top = 4
        if title and title ~= "" then
            P.Title = Text({ Text = tostring(title), TextSize = 12, FontFace = BindFont(W_SEMI), ColorKey = "AccentColor",
                Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0, 15), ZIndex = 33, Parent = holder })
            top = 19
        end
        P.Body = Create("Frame", { Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1, ZIndex = 31, Parent = holder })
        P.Frame, P.Inner = holder, holder
        function P:SetVisible(v) holder.Visible = v and not Library.Unloaded end
        function P:SetSize(nw, nh) holder.Size = UDim2.fromOffset(nw, nh) end
        function P:Serialize() return PosOf(holder) end
        function P:Load(d) SetPos(holder, d) end
        DragWhenMenuOpen(holder)
        self.HudPanels[key] = P
        return P
    end

    -- значения UI ещё не загруженных Lua-скриптов (как в SkeetUI)
    SaveManager.Pending = SaveManager.Pending or {}
    function SaveManager:ApplyPending(idx)
        local o = self.Pending[idx]
        if not o then return end
        self.Pending[idx] = nil
        local el = Toggles[idx] or Options[idx]
        if not el then return end
        pcall(function()
            if o.type == "Toggle" then el:SetValue(o.value)
            elseif o.type == "Slider" then el:SetValue(tonumber(o.value))
            elseif o.type == "ColorPicker" and el.SetValueRGB then el:SetValueRGB(Color3.fromHex(o.value), o.transparency)
            elseif o.type == "Dropdown" then el:SetValue(o.value)
            elseif o.type == "Input" then el:SetValue(o.text) end
        end)
    end
    function SaveManager:AutoValues()
        local v = { "None" }
        for _, n in ipairs(self:List()) do v[#v + 1] = n end
        return v
    end
    function SaveManager:BuildAutoload(box)
        local dd = box:AddDropdown("SaveManager_Autoload", { Text = "Autoload preset", Values = self:AutoValues(),
            Default = self:GetAutoload() or "None", Tooltip = "Preset loaded automatically when the script starts." })
        self.AutoDD = dd
        dd:OnChanged(function()
            local v = dd.Value
            if not HasFS() then return end
            if v == nil or v == "None" then
                if delfile and isfile(self:_AutoloadPath()) then pcall(delfile, self:_AutoloadPath()) end
            else
                pcall(writefile, self:_AutoloadPath(), tostring(v))
            end
        end)
        return dd
    end
    -- Settings меню у NL: Streamer mode и подтверждения (цвет / анимации - в ThemeManager:ApplyToTab)
    function ThemeManager:BuildMenuSettings(box)
        box:AddCheckbox("ThemeManager_Streamer", { Text = "Streamer mode", Default = Library.StreamerMode == true,
            Tooltip = "Hides player names in ESP and your name in the watermark.", Callback = function(v)
                Library.StreamerMode = v and true or false
            end })
        box:AddCheckbox("ThemeManager_Confirm", { Text = "Menu confirmations", Default = Library.Confirmations ~= false,
            Tooltip = "Buttons like Unload ask 'Are you sure?' first (click again to confirm).", Callback = function(v)
                Library.Confirmations = v and true or false
            end })
    end

    return Library, ThemeManager, SaveManager
end)()
