------------------------------------------------------------
-- [v48] SkeetUI — UI-библиотека в стиле skeet / gamesense (форк NeverUI).
-- API тот же, что у NeverUI (скрипт его не замечает):
--   Library.Toggles / Library.Options, :OnChanged, .Value, :SetValue
--   Window:AddTab / AddCategory / AddOverlay, Tab:AddSubTab, Tab:AddLeft/RightGroupbox,
--   Groupbox:AddCheckbox/AddSlider/AddLabel/AddButton/AddDivider/AddInput/AddDropdown/AddChips/
--   AddImage/AddSubmenu/AddSelectList, :AddColorPicker, :AddKeyPicker, :AddSettings
--   Library:Notify, Library.Scheme, Library:Unload/OnUnload, ThemeManager, SaveManager
-- Вид снят с видео / скриншотов skeet: окно 660x560, слоистая рамка, радужная полоска сверху,
-- колонка вкладок-иконок слева, групбоксы с заголовком в рамке, чекбоксы-квадраты, тонкие слайдеры.
------------------------------------------------------------
-- Загрузка: local Library, ThemeManager, SaveManager = loadstring(game:HttpGet(<raw url>))()
return (function()
    local Players      = game:GetService("Players")
    local UIS          = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")
    local HttpService  = game:GetService("HttpService")
    local RunService   = game:GetService("RunService")
    local GuiService   = game:GetService("GuiService")
    local LP = Players.LocalPlayer

    -- [v48] у skeet Verdana 12px; в Roblox её нет, ближе всего по виду Arimo (метрики Arial).
    -- Свой шрифт: положи <папка скрипта>/fonts/menu.ttf (и menu-bold.ttf) - подхватится через getcustomasset.
    local FONT = "rbxasset://fonts/families/Arimo.json"
    local W_REG, W_MED, W_SEMI, W_BOLD = Enum.FontWeight.Regular, Enum.FontWeight.Medium, Enum.FontWeight.SemiBold, Enum.FontWeight.Bold
    local MenuFamily = nil -- [v48] семейство из menu.ttf, если загрузилось
    local function F(w)
        w = w or W_REG
        -- у Arimo / своего шрифта только Regular и Bold: Medium -> Regular, SemiBold -> Bold
        if w == W_MED then w = W_REG elseif w == W_SEMI then w = W_BOLD end
        return Font.new(MenuFamily or FONT, w)
    end

    local MB1, MB2 = Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2
    local TOUCH, MOVE, KB = Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement, Enum.UserInputType.Keyboard
    local AX, AY, AXY = Enum.AutomaticSize.X, Enum.AutomaticSize.Y, Enum.AutomaticSize.XY

    local function RGB(r, g, b) return Color3.fromRGB(r, g, b) end
    local Library = {
        Toggles = {}, Options = {},
        Unloaded = false, ForceCheckbox = true, ToggleKeybind = nil,
        Animations = true, -- false = всё мгновенно
        -- [v48] у skeet окно непрозрачное, без тени и свечения; блюр можно включить в Config
        Transparency = 0, Blur = false, Glow = false,
        -- палитра снята пипеткой с кадров видео (720p) и скриншотов skeet
        -- [v49] палитра снята пипеткой с твоих скриншотов skeet (1:1, без сжатия):
        --   фон контента - узор 4x4 (21 / 13-14), колонка вкладок 12, групбокс 17, рамка групбокса 10 + 48,
        --   чекбокс 135,181,53 -> 97,128,42 (выкл 71 -> 56), слайдер 136,180,57 -> 110,137,61 (пустой 55 -> 65),
        --   поле dropdown 31 -> 36, текст поля 175, заголовок групбокса 213, иконка вкладки 100 / активная 185
        Scheme = {
            MainColor       = RGB(19, 19, 19),    -- [v54] фон контента под узором (среднее плитки 21/14/13)
            BackgroundColor = RGB(12, 12, 12),    -- колонка вкладок
            GroupColor      = RGB(23, 23, 23),    -- [v50] заливка групбокса (оригинал: 23)
            OutlineColor    = RGB(45, 45, 45),    -- [v50] внутренняя линия рамки групбокса (оригинал: 0 + 45)
            SeparatorColor  = RGB(40, 40, 40),
            ItemColor       = RGB(28, 28, 28),    -- hover / выбранная строка в списках
            -- [v50] список (listbox / popup) у оригинала 35
            InputColor      = RGB(31, 31, 31),    -- поле dropdown (сверху; книзу светлее до 36)
            InputBorder     = RGB(10, 10, 10),    -- чёрная обводка элементов и рамок
            TrackColor      = RGB(52, 52, 52),    -- [v57] пустой слайдер 52 -> 67 (скрин 1:1; imgui-клон 52 -> 68)
            OffTrack        = RGB(71, 71, 71),    -- выключенный чекбокс (сверху; книзу 56)
            OffKnob         = RGB(56, 56, 56),
            FontColor       = RGB(213, 213, 213), -- [v57] подписи (скрин 1:1: пик 212; imgui-клон Text 213)
            ValueColor      = RGB(175, 175, 175), -- текст в полях
            SubColor        = RGB(150, 150, 150), -- неактивные пункты
            DimColor        = RGB(110, 110, 110), -- метки клавиш, подсказки
            AccentColor     = RGB(147, 197, 57),  -- [v57] зелёный skeet, верх градиента (скрин 1:1 + imgui-клон MenuTheme)
            Font            = F(W_REG),
        },
        _Themed = {}, _Refresh = {}, _Conns = {}, _UnloadCb = {},
    }
    local Scheme = Library.Scheme
    local DEFAULT_SCHEME = table.clone(Scheme)

    -- [v48] ТЕМЫ: та же серая гамма skeet, разный акцент
    local function HEX(h)
        h = h:gsub("#", "")
        return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
    end
    local function Variant(accent)
        local t = table.clone(DEFAULT_SCHEME)
        t.Font = nil
        t.AccentColor = HEX(accent)
        return t
    end
    Library.Themes = {
        { Name = "Default", Scheme = (function() local t = table.clone(DEFAULT_SCHEME) t.Font = nil return t end)(), Style = { Round = 0 } },
        { Name = "Ocean", Scheme = Variant("3E9FD0"), Style = { Round = 0 } },
        { Name = "Sakura", Scheme = Variant("D0628F"), Style = { Round = 0 } },
    }
    Library.ThemeName = "Default"
    Library.Style = { Round = 0 }
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
        Library.Style = table.clone(t.Style or { Round = 0 })
        Library._ApplyingTheme = true
        local Opt = Library.Options
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
        if not ok then warn("[SkeetUI] callback error: " .. tostring(err)) end
    end

    local function Fire(obj)
        Safe(obj.Callback, obj.Value)
        for _, fn in ipairs(obj.Changed) do Safe(fn, obj.Value) end
    end

    local function Tween(inst, t, props)
        local tw = TweenService:Create(inst, TweenInfo.new(t / (Library.AnimSpeed or 1), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props) -- [v71] Menu animation speed
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
    -- [v48] тайминги skeet (видео 30 fps): открытие / закрытие - только прозрачность за ~3 кадра (0.10s),
    -- без масштаба; смена вкладки - перетекание ~3 кадра. Hover / popup на видео нет - сделаны так же быстро.
    local QUAD = Enum.EasingStyle.Quad
    local T_OPEN, T_CLOSE, ZOOM_FROM = 0.10, 0.10, 1
    local T_PAGE_OUT, T_PAGE_GAP, T_PAGE_IN = 0.05, 0, 0.07
    local T_NAV, T_EXPAND, T_POP_IN, T_POP_OUT = 0.08, 0.10, 0.08, 0.06

    -- твин Quad Out; onDone подключается ДО Play, поэтому срабатывает всегда
    local function Anim(inst, t, props, delay, onDone)
        local tw = TweenService:Create(inst, TweenInfo.new(t / (Library.AnimSpeed or 1), QUAD, Enum.EasingDirection.Out, 0, false, (delay or 0) / (Library.AnimSpeed or 1)), props) -- [v71]
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

    -- [v48] у skeet углы прямые: скругления нет нигде. Возвращаем пустышку с тем же полем,
    -- чтобы старый код (panelCorner.CornerRadius = ...) не падал.
    local function Corner(p, r)
        return { CornerRadius = UDim.new(0, 0) }
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
        props.FontFace = props.FontFace or F(W_REG)
        props.TextSize = props.TextSize or 10 -- [v50] замер по видео: ~4.7px на символ, как Verdana у skeet
        -- [v50] у текста skeet тёмная тень по краю букв
        if props.TextStrokeTransparency == nil then
            props.TextStrokeTransparency = 1 -- [v57] на скрине 1:1 у подписей обводки нет (0.72 был артефакт сжатия видео)
            props.TextStrokeColor3 = Color3.new(0, 0, 0)
        end
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
    -- [v85] подсказка как у skeet (скрин оригинала, пипетка): заливка 30, тёмная рамка 1px (16), текст 10 цветом ~150
    -- тем же шрифтом, что меню, без переноса (строки во всю длину), поля 4 / 2 px, <b>жирный</b> через RichText
    local Tip = Create("Frame", {
        Visible = false, Size = UDim2.fromOffset(0, 0), AutomaticSize = AXY,
        BorderSizePixel = 0, ZIndex = 60, BackgroundColor3 = Color3.fromRGB(30, 30, 30), Parent = ScreenGui,
    })
    Create("UIStroke", { Color = Color3.fromRGB(16, 16, 16), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = Tip })
    local TipText = Text({
        Text = "", TextSize = 10, ColorKey = false, TextColor3 = Color3.fromRGB(152, 152, 152), RichText = true,
        TextWrapped = false, Size = UDim2.fromOffset(0, 0), AutomaticSize = AXY, ZIndex = 61, Parent = Tip,
    })
    pcall(function() TipText.LineHeight = 1.05 end)
    Pad(Tip, 5, 6, 2, 3)
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
                    -- [v85] RichText: экранируем < > &, **текст** -> жирный (как «- No shake:» у skeet)
                    TipText.Text = (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("%*%*(.-)%*%*", "<b>%1</b>"))
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
    -- [v48] skeet: popup - тёмная плашка с чёрной обводкой и внутренней рамкой, без тени,
    -- открывается вплотную под полем (как список у dropdown)
    local POP_BG = Color3.fromRGB(35, 35, 35) -- список у оригинала 35
    local function OpenPopup(anchor, w, h, build, alignLeft, bare, placeFn)
        Library:ClosePopup()
        HideTip()
        local blocker = Button({ Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = PopupLayer })
        local frame = Button({ BackgroundTransparency = bare and 1 or 0, Size = UDim2.fromOffset(w, h), ZIndex = 2, Parent = PopupLayer })
        if not bare then
            frame.BackgroundColor3 = POP_BG
            Stroke(frame, "InputBorder")
        end

        local ap, as, vp = anchor.AbsolutePosition, anchor.AbsoluteSize, ScreenGui.AbsoluteSize
        local x, y
        if placeFn then
            x, y = placeFn(ap, as, vp, w, h)
        else
            x = alignLeft and ap.X or (ap.X + as.X - w)
            x = math.clamp(x, 6, math.max(6, vp.X - w - 6))
            y = ap.Y + as.Y + 1
            if y + h > vp.Y - 6 then y = math.max(6, ap.Y - h - 1) end
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
        Fade(frame, POP_PAD, 1, 0, T_POP_IN)
        return frame
    end

    -- [v48] строка списка skeet: 18px, текст 12, выбранная - акцентом и жирным, hover - подложка
    local LIST_H = 18
    local function ListRow(parent, i, text, selected)
        local b = Button({ Size = UDim2.new(1, 0, 0, LIST_H), LayoutOrder = i, Parent = parent })
        Theme(b, { BackgroundColor3 = "ItemColor" })
        local lbl = Text({
            Text = tostring(text), TextSize = 10, FontFace = F(selected and W_BOLD or W_REG), Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -16, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, ColorKey = selected and "AccentColor" or "FontColor",
            Parent = b,
        })
        b.MouseEnter:Connect(function() b.BackgroundTransparency = 0 end)
        b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
        return b, lbl
    end
    local function ListScroll(frame)
        local scroll = Create("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, Parent = frame,
        })
        Theme(scroll, { ScrollBarImageColor3 = "TrackColor" })
        Pad(scroll, 0, 0, 2, 2)
        List(scroll, nil, 0)
        return scroll
    end

    -- список значений (dropdown / выбор конфига)
    local function OpenList(anchor, values, current, onPick, alignLeft)
        local n = #values
        local w = math.max(anchor.AbsoluteSize.X, 120)
        local h = math.clamp(n * LIST_H + 4, LIST_H + 4, 12 * LIST_H + 4)
        OpenPopup(anchor, w, h, function(frame, close)
            local scroll = ListScroll(frame)
            if n == 0 then
                Text({ Text = "Empty", TextSize = 12, ColorKey = "SubColor", Size = UDim2.new(1, 0, 0, LIST_H),
                    TextXAlignment = Enum.TextXAlignment.Center, Parent = scroll })
            end
            for i, v in ipairs(values) do
                local b = ListRow(scroll, i, v, v == current)
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
    -- [v48] skeet: плашка в цветах меню с чёрной обводкой и акцентной полоской слева,
    -- заголовок жирным, описание серым, справа оставшиеся секунды. Стопка справа сверху.
    local NOTE_W, NOTE_H = 250, 40
    local noteInset = 0
    pcall(function() noteInset = GuiService:GetGuiInset().Y end)
    local NotifyHolder = Create("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6 + 24 + 10 - noteInset),
        Size = UDim2.fromOffset(NOTE_W, 0), AutomaticSize = AY, BackgroundTransparency = 1, ZIndex = 70, Parent = ScreenGui,
    })
    List(NotifyHolder, nil, 6, Enum.HorizontalAlignment.Right)
    local NotifyCount = 0

    function Library:Notify(info, time)
        if self.Unloaded then return end
        if type(info) ~= "table" then info = { Title = "", Description = tostring(info), Time = time } end
        local duration = tonumber(info.Time) or tonumber(time) or 5
        NotifyCount += 1
        local title = tostring(info.Title or "")
        local desc = tostring(info.Description or info.Content or "")
        if title == "" then title, desc = desc, "" end
        local h = desc == "" and 24 or ((#desc > 44) and (NOTE_H + 12) or NOTE_H)

        local wrap = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), BackgroundTransparency = 1, LayoutOrder = NotifyCount, Parent = NotifyHolder })
        local slider = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), Position = UDim2.fromOffset(24, 0), BackgroundTransparency = 1, Parent = wrap })
        local card = Create("Frame", { Size = UDim2.fromOffset(NOTE_W, h), BorderSizePixel = 0, Parent = slider })
        Theme(card, { BackgroundColor3 = "GroupColor" })
        Stroke(card, "InputBorder")
        local bar = Create("Frame", { Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0, Parent = card })
        Theme(bar, { BackgroundColor3 = "AccentColor" })
        local tx = 10
        Text({ Text = title, TextSize = 12, FontFace = F(W_BOLD), Position = UDim2.fromOffset(tx, desc == "" and 0 or 5), Size = UDim2.new(1, -tx - 34, 0, desc == "" and h or 15),
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
        if desc ~= "" then
            Text({ Text = desc, TextSize = 12, ColorKey = "SubColor", TextWrapped = h > NOTE_H, TextYAlignment = Enum.TextYAlignment.Top,
                TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(tx, 21), Size = UDim2.new(1, -tx - 8, 0, h - 24), Parent = card })
        end
        local counter = Text({ Text = "", TextSize = 11, ColorKey = "DimColor", TextXAlignment = Enum.TextXAlignment.Right,
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, desc == "" and 0 or 5), Size = UDim2.fromOffset(30, desc == "" and h or 15), Parent = card })

        if Library.Animations then
            Anim(slider, T_OPEN, { Position = UDim2.fromOffset(0, 0) })
            Fade(card, 2, 1, 0, T_OPEN)
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
                Fade(card, 2, nil, 1, T_CLOSE, 0, function()
                    card.Visible = false
                    Anim(wrap, 0.1, { Size = UDim2.fromOffset(NOTE_W, 0) }, 0, function() wrap:Destroy() end)
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
        -- [v72] иконки индикаторов слева, вырезанные со скринов gamesense (белая маска 48x48)
        ind_timer = "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",
        ind_hc = "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",
        ind_shoe = "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",
        -- [v73] иконки категорий Visuals: враг / тиммейт / глобус / глаз - вырезаны со скрина skeet, бот и эффекты - тот же человек с шестерёнкой / звездой
        cat_enemy = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADQklEQVR4Xs2Y3YtNURjGfzOMzxTyVYiaMD5uhJrccCUpI3GhXCgzN0z+AW7EjRvjL6AouZkblz4uKAojxphCUlxRJsmoyfh49ZzepTXnrH3OXseMPLVae/Z+93qf/X48a51pMTP+J7T+T2SEZgltAa4Cwz7OTNqHKWWZ46qZjRaM3sy1anznRkiR6KoTjXNA799EqyWjqJWmOyWcvQM2lbBLIidC+0o6WQV0l7StQQ6h9gwn6zNsJyCHUA46coxj5BB606yTHOQQeuwLS9o1pvlI4WUOiRg5XSY8ADb4AtN9/uFzixMdB5ZB5b5swvNSyImQ0AP8gorznz50Pc/J6N7FiEQWmQqaUNaNZvbJzMZ96PqzX/c3sd4EDrkpC1BkDwDHgUXAEHAaeF0qL3XQLKEpQ5ka0jbQD4z5aKTC6zxioz7vzGLfIOeqibHE6Ct4r7vgFDBoZp1l6qteyqQ7G6Ovi4+W6izp0G3gFrAV2Au0RVqljhNuegd+Aw43ilYRoYPAJXcQWlcEAoKzgPBMaVoAPAP6gGuNCFQjiFs19keiJkKKSD2IoEjN8LrZljAO9SodK0SqqOdCpRCluHIwy+dGEKm3nr6Ao8CAC+VXj9yJegulUrYaeOLp0lfHW0M9qMbmu5ILV4A9vt3o/P0e2AEc8+vNycUSld9V1SlfzCqj6Byt+3p+NlpL5251p7or5eOumQ2YWVv181TKlKYYqp9GNaS6kFYJ6kx13ElX8Yd+P17jFLASOFIdpRQhCVsM2Sh1mlP2ggips4RDwEfggjtdATz3NQKpey4Xu8oQik97QXs0y6kKN/VTN+4c2WhvE2S7HFgCFV2L330FzCxDKBzAUtEI6QtRC/oT235PRFLno6XAIDDbSeiMHoT0D1JO10Y1E395OCGqxsJ7IWL6O0T2BdBZ9eX6SNXMYuCRk1I3P62OUHXbi/ENqGhRCG+s0ELYNjQHYtKs85Ey3wdGoOank4RYWiX7hS4TE1Fmw2vCZo2ZfTCzITPb7u+3mlm7mV02sxEz60mt24yzsu90mNl116+gY5qHnVhynak6oCmVoTmE3cAc3wGUskJMFaGaWi2QixoUCd1ko/S/6f4VodL4De86VHnGk3ixAAAAAElFTkSuQmCC",
        cat_team = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADLklEQVR4Xs2XzatNYRTGfxcRpQyUIooopYhSilKKkZQ5xYAy8B8Y+hwoJmZSCt2iDEwQYyFMhCJFSBERIjr67d512/bdn+dcp/PU7tR+3/b7rGc9a633jPV6PUYJ00aJjJjRJ6GtwDZgLbAIuAZcAe70+b0JjHVM2XTgOLC9cPBv4AdwETg1CKmuKdsDmTp5SOYPMBfYAOwaFqGZwG5gQeFA0/4dsvU1kJFe3C+pLgodBJYCz0oUmgP8giylEi6Sbo0uhNZDlp6ywyTi2s+Uvs2tGZTI3RZv02EeXFah+mhgdFHoVSI0SLtoRJc+9D6lJVBUaugKXQUeJjZ6pgz66zNwslGKCnRJmY3vBPA156FZSbVP6f1z4Ea/ZEQXQuIxsC/9LkxVpdmFqt0Djg5CqOvoyGM1cDg1RUkdAT4OQka0IWTkU2LYNmiTsiXAeeAF4OWpblY5Pkzl9bT/QroRtEaTQqfTbHJcOJ8sfR+NvTdn8IC3gGOQBWG1fUl7TOkZ4HYTsypCRjoO2QiwIZo255UecapLyD2a/AGwEliRSEd6JTQbmJ989hI4C1yqI1XVGCWyHHgDE6XtRPcAG6K/Yl16AkHYPfOSSrYCSdoiDKYWVYQ2pchep8PdF505D9+5poISjvIXqreziUARVYQ2po2mpanCYsqbRju1HhOmsTOqqkw/CGUWTaRUR5W8X+sZ06XnAvuBJ8DlVIWR8lYKeQkrS08dJCIpx4apKiIIq+CHug+VpcwOrCLeAL1wiaphGjAA55nd+n7JgXGOivvdSpSlzOrqCn1jEJZ6GUyh6xLPBzep6soILUvKqI5SG5EfKz55hF/Cc3bzu8C71LG9j0vG1N4CHgHfgHPFVlCWMkl4uJHEuqSsuEBEGev+SiZSrE/cr3LRDlTDdX0kORuuiPUMVR4y4ujOUWH5SnMtSPneg/yWFWYjlNDNRMpgtIGEnuZIusc+908FFwnFncY2LymfiCzMmG+GecPHnFMZjZ039wFgS/p3u6POoEVCsj3U1dEtoHJxkQtIfFLFlaXsf8G2UFvyoun6MVVYlcysJfRWJYZFqDXa3BiHipEj9Bc6Y8umQf/fSAAAAABJRU5ErkJggg==",
        cat_bot = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADW0lEQVR4Xs2XzW+NQRTGf62vIASxIPGV+FY0wkKshB1BRP+DWmn8D2JlJcSaXXdd2yCxEhERXxGJEEViV6WJRtGR53XONZm+9+3MvSqeZPLOnTlz5pnzNXN7Qgj8T+jtgMx+YBh4bu1iBzraQxYqaMMhhIk2bahAT9s9SywkS5xsONslYKhba/VkxpDcdDdjs1Fgd4ZcW+Ra6FTmJhuBwUzZWuQS2lywyc4C2RnIJVSCHSXCKXIJve5mkxLkEnpoSlVF1eZZq8PLEgIpcrNMuA/sMgXz7fvDvj1GdApYA9W4ZHw+G7kWEs4C01Bt/tOa+suMjMauRySKyVQorK59IYSxEMKUNfXHrT9SqKt27xKXOWTVM8A5YDXwFLgAvMr2SwM6ITSnmC2GdA2MAJPWZqvC281iE/Y9XMy+we+KicmadrnNmsHkFZDqljcqjzS1di5T3emLThe/4pRZqkO3gVvAAeAEsCCqVUuitRpXBipDBXlF67/XWa+O0ABwwzbw1JUCh5TH8Dm5aSWw0DbUIdYDd4B3wDFbdBPYABwF3kdlpIIXuBino6ImQrJIE0RQpERETXDS48A6qC7nBza3B/gG1ZxbrYWU0FKoAlEVd7ER00lTq6TQ/NtocLmRPGibSp+ICOqLyCGr/lr7xdemLtsEPDJ36dTx1dAEkV5hGyl+ntlvudAtLLcJcpegNZ/MUiL7VYNp2u+NgnM2qzik+KqRkT4R+Aisiix7Dap3kpr67lbJSPZPWCQpONDwiG/3uNfV0W96PK0XhRAehxCmQwijIYTeaB/1NaY5yUi2xSONIRW2GH5iT/sZQWiWedLo0AKkLotfe05CXxGRC+v+VcYkZXolhlK939YoZq5AFVtq6mtM+iQjWa2pkFoofoClMeR+dqt5HMSHEjnpWAuMWV0SzkPrj4IHtZJGMpJtHTS10LYowOKT+wtRdcbXuMX0O7assmUfsAU4bnegUl1E1NTX3ag5yUi2yrDUQirxmngRMY4rtODXhr5OTBtIafx09bpyz+R0EJUCwQuj5j6n4RW7THfLkVSgA2wF3tihVJs+tLk6NKfrxl+gv0+c+c+1FHKhW6zry7VbyJWeHDE8KeoytYW5slBKpJFEjNlejH8D2WSEf0GoCP8doV/JCZa8O3KJ7wAAAABJRU5ErkJggg==",
        cat_eye = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADA0lEQVR4Xu2WX4RVURTGf9NkMjEpxWSYh5iIHjL0MBQxTIoheojoISIVMVRET2UkSm9ReiiRXlKkh6iHSEVF/6REUqmk/0X/lC/fae0ce+69ZxLp4Xxs95x99t7rW99aa6/bJon/CRP+JzJGTagKtUJVqBWqQq1QFSZWLQh0AF3A63gfhmLMAnqAGcBk4B3wELgX4xjwYpw2CrSNs3VMB6YBu4Ah4EcY+ggF2W/x2w5MAr7GGpO8AxwAzoyHWBUhG1gKjADzgO9BxEbtuZXYVlKuG9gILASmhqqJrH+3AKeDmM+2Y8mhSoV6ga3AYHj8GJgJdALPgHURnjKSEYf3ENAXa6yUw2tcBfYA10vpYLK/4JA1GKslPZD0JsYaST2Sbse8n5vtTfNecyXGgKRhSeckPZJ0XirOTGs703OjQzdJuiTphqTR0qa9cfjKcZBJ566Pc3aX9mwPp+5LWhvz7VIxxhDyAVbhS+aBDRwJD+dmhIaCqBVdln3rDUVOZfNW527YGpHUnSvUJWl5LLAy+cEmZIMXGqhj+R0Gh8fKOlQ+z3vstQ37Wx4N2/A320tKjbmHPkclOQkTUqK6xP2cJ/GHmHAFep8TPsEV5PlP2ZzhCvOZvlKaJrWT2d44vrlKR0PBwczbJaGcE9bhKyvRJ+m5pJPZvBWx4h5Ok997GiW1Q2cZ30vaX1p8MCRe9YdJbaNO5GTLhfIynC5XWvG9Wena6+NBzJ6bZH+o55xxGae9HVIx0ntRLZLmR265SFwIVjY5ms7M97S8qX25+YZeHO3AF2PqWc4L37oXs5xKWADsi8vQve0VMCVu5bPAjsifMoobO28dJlFOXifeADAKzI7kNBk35afALeBw/Bq+mVfEcO97G4XgZH8CbAauNXGiQKNelqoqRz+wAVgUH0zWTdTeu8/ZGfc4v3v4m0ldBnaWSLdEVXM13LtcliZQDomVcDOdEyr4yrAiDq1L/yZwooH1Zg43VagKLQ9sQcCOmfRfK/RPUf+nrkKtUBVqhapQK1SFn7rCtEtk+JfDAAAAAElFTkSuQmCC",
        cat_world = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAD5UlEQVR4Xu2XTahWVRSGHzMMFIPAMAgUBKXAUBCEBKOBYkQICkJgIDgzmhkUVjgIIgfZQCQSSyKISKQEqYlYGkWFQkEkFYW/lCCFhYFSrHgOa8Ph3PP3XSjuwBcOH/ecvfZ+97vXu9a+syKCmYTbZhIZcYvQEG4fGjCA+cDdwA1gbj4/A38OBXZhOoQksQV4DrgELIFqnj+AO4C/gM+BA8BXSdJ3ozBrApfNBl4FtgM3geP594+5qKTuAlYAG4H7gV+Bd4E3MsY5/ullJqERz6qI+CIifoqIHSPGO+e2iLiWMU9FxMIxcWNctgl4AbgKrM/dLW3Z5ZzGO4/w4zzWJ/KIFw6eWw/ruRGxPJU5ERGbcux7+e6XiNjZEX8wldmY31Xrsxw/PyJmd607lEPvAKtSHRP2B2AZVIn9TSauuVSHShljrqjqOuBhYHG6cR/wfqdSPQq9HFGpIMwfYQ79FhEfRMSGnlgVMH9O53hjVEilj0VUKrWu3WV7z3p1WlnLqs7R3Ll2frYnF1TvGagctSDn0G33QKWeDl0LfNg2R1dSP5RByv53Tuw7j0nr9+ERqJLYcnA5j0lIxoIpUb+3oksha8m3qcxh4K3coeSu9LBxMRe+Mwukdcl3pTCq0vXMp1Z0KbQmi5zW3Z27/bLREmwVTaioi3pEEhFlAxeA3zPRjW0tAX2tQzfYo16Hqu48lqotz4k9DuHEddWM04n3AfOSmCRVt1RplfPdFLX7CPntldqiJuprScaEl9DXOWm9JZi0T0KlsiTsZ1p+bxJVHRXUKFPRYT/tuaXl26NpXS19LiL2thS5OS1xC7IMaP+LEfFdRKxtW7srh2T/eI1+yRclVm5zwV1uBk4AH2VJ0PIqpGIlh4QF0ttBSXjjVXcKugjZg+qSFpdsyxIgnNRFzQVJvp2lQpgrJV8KMeuOznVzxrbemboIeWUweZtN1NYhOZ+VOam795ImMfOsGVOI2T6M0W2qO5Ht3cl54OmMKru0Sp9JQn5XRYmrkItoBAtiE8ZrgqL0S5MSEi/mEWytyW9+fJKTubi3RRcqdadsoAlV+jSb8ymorrntGLg07cqGuqQ2bkW+s1nqGB+b8NBchyLi+4jKcZ1jhy5oe/KIvKB5pSgojdOdq5pua6JeyffnNeTNdFw3RuzMMSfzCmId2po1yCuJ9aptjnIBU1ljVfDBMWuNJeS4I0nAomZR9HddzyISl4jjPOZRaw3dGJvw9mfB9PdsJqcJal3R+ovSdbaKe4HnoTr20ZiUUB3m1QNZd7S9lpZcKRn2vYkxXUK2iGn/d9qH6RL6zzBk+/8dtwgNYcYp9C/C6d2flUAK/QAAAABJRU5ErkJggg==",
        cat_fx = "iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAADRUlEQVR4Xs2Yy6tNURzHP8f7Lc+MGMjzSoSZkFJKXnlMyOQqde8/ISMjxUAZYOKO3GKoPJIkAxOSFIoylrpxcz22vrvf77Sss88+a53T0f3Wap2991rr9/091+/eRlEUTCZM6YLMNmAEeG3jQhdntIcslDFGiqIYazOGM85pKzPHQrLEoRrdLgLDvVqrkRhDctPjBGGfgE0J69oi1UKHE4WsAgYT11YildDqDCEbMta2IJVQDtbnLI6RSuhDL0JykErohR2qKqox1UYV3uYQiJGaZcJzYKMdMM3mXzY3jOgEsALK91rj35ORaiHhLPAHSuG/bej3fCOjd9cDEtlkSmRW14GiKL4URTFhQ7+/2u/RzLMqZee4zCGrHgOGgKXAK+A88C7ZLzXohlBf0SmGdA2MAuM2OlXhdWaxMZv3ZLOv8btiYrxiXGqzZzDqAnLjs1zfzmWqOwOBdmEXp8xSHXoA3Ae2AweB6UGtmhPslReUnTuABcAjKN8pK5Pq0HHghgnw1BUBR3yQf5ObFgEzIilej64By4GjdTXKC1yIcIMIySJ1EEGREpGYjNcsWW8/MA+YC3yzc1v65ziotViBqIqrw2dVCKmCSH2s+CAikrEbWAksBvaZAvrWomxMaBkw2zZIyM/E8i9N1cQJOtMtL8V0zukgvk7YO33TPq1t8ogJbQ6CszLoKqBDL1vgCgpgj72dwBXgpAkXjgBXgV2muNZqT4k4yxTQNzvETAwRl0temqZbgFPAASjrUh3eW6beAp5pYRzU8QGyoN/krn0MaScyDqX8EgvgTlAZUJhoLhETCrs9zwDNEurPcSA2zW3rnkI5lBR7zUVnLEEEVX1Z5A7wBPgeso4JhQ1YHENOxK0maE0ch3rWUNDes6FsFSnhLnAuIKGS4Uq3HLY2SMVQc+8QpbUTEBkdpOfQsh7UUkDrtVd/6epZ47Z5ZmbQWzVlhRZSXZD53gTuCSu04NeGZicmS2yFltZVZFU2BLnmM7AQeGhZ6Ar9g5CQNsvnvWJN0Bt5nflhd5jaW10xUrSyrFRdHb1CjZpc6M2+J4PuR911tVdRPxo0udKTIxudGrRuEJYIj7tk9INQjKz/iP0PQlmYdIT+Ap6cDlCFbzpYAAAAAElFTkSuQmCC",
        ind_warn = "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",
        ind_md = "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", -- [v85] вырезано со скрина gamesense: MD - прицел в круге
        ind_lethal = "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", -- [v85] вырезано со скрина gamesense: Lethal - череп в прицеле
        ind_hc2 = "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", -- [v85] вырезано со скрина gamesense: HC - перечёркнутый прицел (белый)
        -- [v66] бесшовные текстуры для бегущих узоров чамсов (белая маска 128x128, цвет задаёт меню)
        fx_galaxy = "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",
        fx_grid = "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",
        fx_stripes = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAB2ElEQVR42u3csU0AQAwEweWqov+Irp4eIEDI4wZOWufz8d776uf32e/P/h/uT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Ev70/8W/vT/zb+xP/9v7Hey/x7+5P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9P/Nv7E//2/sS/vT/xb+9PfD6A+PEBxI8PIH58APHjA4gfH0D8+ADixwcQPz6A+PEBxI8PIH58APHjA4gfH0D8+ADixwcQnw8gfnwA8eMDiB8fQPz4AOLHBxA/PoD48QHEjw8gfnwA8eMDiB8fQPz4AOLHBxA/PoD48QE8Pz6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT6AfT5AfADx4wOIHx9A/PgA4scHED8+gPjxAcSPDyB+fADx4wOIHx9A/PgA4scHED8+gPjxAcSPDyB+fADx4wOIHx9A/PgA4v+3/W8k0Q8rRLkkbAAAAABJRU5ErkJggg==",
        fx_matrix = "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",
        fx_petal = "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", -- [v81] лепесток сакуры (Air particles: Sakura), нарисован скриптом (PIL)
        -- [v56] иконки вкладок, вырезанные со скриншота gamesense (белая маска 48x48, 1:1 к оригиналу)
        sk_gs_config = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADUUlEQVR4Xu2Zv4oUQRDGv/NERVAxOkFRFISLDTQxMRUMjEQ0MTFRMDbWyBdQfAJfwcxIIzNFMDAwEwTlBDnljpHf0nXW9s5cdc/Ourt4HzS7sztTU1/966qZlaZptMzYt8zKg/+KwKo0WguFlWXPgf0F5jws6bSkz+5c88QPSccLZEQ4II10Qe4vSV/TBdvRhSUE1iXdl3RZ0tEkkBseTGvIsHos6Y2kV4kIQH4nkSiErkl6Io1IYO0jziJ3Jb2NLJTBG2zL/XdR0tN0jKevSPoUKT8CObDLetH8xZb7/jK4LpKb/7+WZG82TbOR1nrTNKtpdcqLyujVlrjHneTFELDw++KE4WXWB0nX0++dYRoR8CFjIMl+9tR+Uxpbt1IegTzOOX7oSLQiIpArilCs4eO3Bu+TolYAiHcMArxM7sPxWUkPJJ1xnrD9aOSViEBX9pdUr1p4mSgHSareBUn3usI2ImCxB5GwJg8Efx+z9g3nqTGUEDB3mquxFPvAEDA5WBu0eZbfTnYZMAoFEzw0LJdAW0Xz/5MLnTkXEfDVwchME0oogietZfieLNvboyUEwFDtwqVsd6WPghAEuloG740JRDmQw6xvPVENUJBwOeEu2kjfe3u11AM+lAgDkuq5pGc1DBzW0nfksDfQc31zzWIxomaOgdlcaNXIV4uhQsuQl1DAZsp9DrWE8naNB9oqQeT6UoJmnBp9xixZg3zHnBa06eSCz6tiIsUnJtyU9C5NTExpXU2deaatz2mD6YHHqEx82qyxaxWqyQGUOdaxpZeGShfyUETeR0nn0iBFmZ06B4BZlE2NnLAbtyngK1cNQc7FI0XRUXRSB2quzQnmMILWZ/FZ9LCgRgkPq0hc33c22C2cIFzUXvQlYBhaeR92kdd6l9FZo8ootb3QwmGPwLyx54F5Y9oyWlTqZom9EJoh2rw78dsie6BoQ4ty4FR6SsxDXjrQO5nFh84BZmVmZN4X/E7zBvdecfcdmw+ieQCcl/QovaFhCJ8lUI7XS7TtGOy1pNstg9POI88SAoDHIWZtPwfMCzsEohxgbER5Gx2xzNBh4+EHHzzgjwmliVe9pR4ACLSJbF7IJ7vQAx5FVeFfIwohj1mGTm/UEFhILD2BPxuURSAC1IUHAAAAAElFTkSuQmCC", -- [v57]
        sk_gs_players = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEAklEQVR4Xu2ZX4hVVRTGf6MxIMqAMiBMCAPKEISTI0ogCEPBMGkogTGijQ+R0IOvEkz00kP4JIwYAz0UEYWhKMkERQ8SMZAoI0j//1AYClEUE4EkxRffZV84c+f83efcuQl94INz9157rb3WXutb6/RJ4n7GmvtZeWM1DNgArOvWRa2GAc8Cx7tlwAPdEgwMAWPADDAA/AR8Avza5Jl9DT5ih8ljwCFgPCj5ezDC+BIYAf4A5oA3gW/qGtOEAQeAl4D1wGXgEnAd+CcodwoYBJ4L/98aDJ0ARoF3gVeBn6OMsQci/w1IOifplqTJHBmbJQ1n/D4k6bykvyUdiNEjVvlxSd9Jmpa0Nubgjj1jkhYlzUrqryKvqgEWfjbc+tYqB5VY64uYk/RZjsdWyCkjOLnGN/ShpA0lFKoqu71+RtKS1AqvQhmFCxJCjkhakLSujOCaaxyaV8qcVTYLOVu8B+xuOo/nwPVjI3AyNzuVuKmNkn6QWg+tzPqm1tjTfti52amMB84B94BjUXm6Hh4GPgW2ZdWJIgNcgG4B24Hv6+kSjZdD2J5Jk1BE5p4MlbVXyhuvA9PA2hgDzCRfib67ZvAj8GfgUSuQ5wFzlmHg22b0qAUTv2eqemAKuBoecK9hGn4E6O9UJM8DpsUfNKD5/gS9jsWd0NU5KpYhywCHzkPAb7EnBvjhnYBWKrbMWNwNmchhtPwxpxSn41oOU4iY4mS67ULUxu0qJC1x5h5JvyTkvJZkwFmKjUj6S9LeSOXbcs0w54MhdWi3934h6VSnPlk9sVs9p6+lWJ8HuCtzt7Yp0aHFwHLcU3/UuTmvqXcGegS4GXNiAjdq7m/jwTQ2kJeF3gcmGzq8LjxbcjTYC6WykGEPPJqWe3uAPcDnaWGY5wFb69jb0gOFO+H0OZ+mR54BVv7j4IVewuHzeBjVrEARG7XVphS9xC5oDchcjVeiIM+7eXcB2l+zHhSdk/W7pyDXJB3KOr/IA6axR4F3gM09cIOHwr55T/tSUdSRtTEbuNG+mgWpCkzcFkItyh47lgwNh5Ibe/OksnvqrDN18Fhlqui8sh4w/JiuATuhseqaBk+53w7152CRx4veQBKeOHvCvNjFDxb+jnAlKH+4SPkWilyU8vtooLcXGx4xepT4taQXqgyMYwzwHr8JG2CeXnfg5cGZabLnoRNVLzTWgPa+50Oj8UaoFWlD38GMQa3/fjrsd67P+oaQq2OVR5wFzy+fCBXb/e9XwIXAXTzR80zVzfjT0KIFZrhtlutpw1uZVbYEmjAgCfer/rD3FLQyiEeDnYnAn6FcGBsZljVtQBqcVVzFd3RjRNPNz6xtvBgMcDg1jtXwQFdRpZD9J/G/Ab3Gv1oLCcfh9N45AAAAAElFTkSuQmCC",
        sk_gs_world = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAEVElEQVR4XtWZbcieYxjHf8/GmFk2ZrO8rJUlb620kHmLlqKpkS8oraSUWvFFKL6oRaSUmnygJB+p+SIM+UDCGNMWwtiMeVuz2Zi//lfHNaer+77O87qf53rq/tfd03Nf53kc//91nC/HcdwTkhhnzOiZ/GJgHXB0X376FnAH8ASwcFwFzAnis8dVQI2Z4yrgz3GPwM8h4OC4RmDLFBCf1WYjdwptAJ4F5o1I5A1gAvh8hPlLgI+AfcCCYfOPyhheCqwCbgCuBD7MjPfbuh24EDgdOAPYC2yLj4VsBzZn7FwBvAqVvd3QsgR9E7d8Fkr6Xf9h+ZCxp0namIzLYaekW4fYWplMPiDpnDaOOQF+btIHw+ghSUsTgzMk3Z1j24K9ktYm9mZLlThjT458lQZlIlA/XyzphzB8X8yZL+mDQvJfS5opaYGkdY2oGo/Hc/t7W9ILkuaVcCsV4HEmsCL+WtCOQvLG1gaZWZIeaMx/uYRwc0wXAfVYr/efOpA3PhlCbo6kLYmtV6RqWRbzyh2jTTir3Nh2rA3BP0O+/wO4HPg2nl8L3NzlyO0qwKnx8i4OAm1Fx6/ABVD9NZ4G5pf66CJgEfBwqeEGfJm1wSnHTTHAmetzmfFH0EXAjXGxjIKSsm8TsDWMr4bqhWXRRcCdWWuTg/fJ/YmJa0rMlQpwaXheicFJ4iXg+7DhlCSLUgFnZy1NHb4LUxdDvpJLk7lj44Q5EzgBOAB8Ggmck7rpgn1eFI2AU4AfgeviO9fW/jhKTvZeTAX4fL96AMt7gJOniz38r4ZwSr0GeGyA/7XAW6mA/Y1BLged9r4HVXo7XfgrcbQzODit9h78G6ojt07Jd6UCro+J3hfNm/PESbLP3QMpzop/DgE7YimvH+Z/0CYedO27MpoMSg8L49xw5PTC+7AVpYZ3Ab/ljLWgNALOtZaFHS+TLEoFHIZKxKgo9XNZlKHG+yXOSg0bj5YYHILSCDwU872Mnynx10XA87H7+8IKqCJg+NisL7R2dCkeJF3VsZCpsS3jx4XN7hi8X6pq4yJuXSJguM/z5gghaPPjjft60sF+sOT0OYJSpcm4JSOUlF8O8ePGwDtJVL+SqmgU8+oaAeObOCm+6BCJQZv4NmAPsDLsvAvVJeYysxwd1LrYvkXSIzHHb2pT4Z6o2yrnS1o/IIIbJJ0qVX0iF/ZzS3mVCnBL5bWE7EmJg6cKRQzCYUl3hS2/oLpD8UtJU6u0seV16jdYw42ppnALcsMrbUO2wet+zQA7aSvTp5H3W+tLLonA5gz5po1VsQyacKvwXqki2ebXy2xfTPbR2rqccgIWJX3R1bm3MeD5k0Hkko5z3YL8LOa2Nndz7XW3ti8FPoYqve2KOgGsez6l8OlUZ6WtyAkwipKqIZgb3x9TyrwrRrkHuuD4GDy2v5EdFwKcjveCviPgn5eMtM6dUvQtoP5NrTcBE9Vt1i+c3/hHvl4wHQJ6xb/bSvrzm0bj9QAAAABJRU5ErkJggg==",
        sk_gs_skin = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACsklEQVR4Xu2YP2gUQRTGf2cgEhAloFgFhIBYCbERBFFUNKIokYCgpaQQWwsbQe0kYiXYB4VAxNJOLUSxkNiESNRKERRFidr4j0/esQfH3szO7O1d5g7uB8sd3Myb77uZN292apLoZ9b1s3hjYCA1gxlITdEMTADbUgsMUWTgCrAzFCA1PgObgQPA9tQCQ/gM7AI2AHtDAVLjM3AsE7YjtcAQNc9RYiVbPr+B9aEgKXHNwAiwJRM1DIynFBjCZWAj1J8GF0JBUuIyYMk71CTqTEqBIVwG/uU6bQV2hwKlwmXgC/A9J2g2lcAQLgM/gY+5jlYPpkPBUuCrA28cYuagviv1FD4Diw6Vtr0u95T6gjeyRx6hVhOsyPUMvhl4ArzyqLQD3ttcrUiGz4BtpZcKVNlMrPZEYttZyPMMSVpRmOeSThTEKRqj8m++w1yD/cDjEuvjIXCoRPvKhAwYl4FrJUaqlWhbmRgDdi56AByOHG2To5J3jZhrFUvos8CnSBUnI9t1hBgDhp2PjkPLQc/Fmp5eYw0YL4AjEX/bJDAD9crddWJyIM9BYAEYjVBnxfAOcA94HdG+NO0YMCyxp4CbwFjkqN+AG8AS8BJ47+hns7YvW64W9xlwvTB+xQJkxW5a0udwvWthUdI5SWOSZiQ99cRYLtJY1UCj/4ikhTZM5PkhaSoTbJ8fsgYXfSY6ZcDiDEu6XdHEZE7ouKS/2WPxW/SW2YVC2B3SeeBUwUk2xJ9cg69ZUbScc7/WVsyBov4Tku6WnJGlJj22LO839f/l0tpNA835YUvjlqR3EYZM6Hy2bJqxRG/RuxYG8mOMSjotaU7SaoShWam+2zm1tlsHOont91a9jwJ7oH4PZfl0Nasb9t1LLxjI07gVzF+wOelFA6Xo5DaahIGB1AxmIDV9PwP/AcGdswNG2MvCAAAAAElFTkSuQmCC",
        sk_gs_survivor = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAACgElEQVR4Xu2Zz6tNURTHP9eTevkVERNlpKSIlCKllISSMjIUpTBQ6o3ewJ+glIk/QBnIy8RMiRIlIj8mjJSIyARp63scPS/v7rvOWvuc69b91OtNztlrffdae6+z1u2llBhlFoyy82IsYNiMIzBsFrbkwASwHtgK/ATuAe9asaVrtODfZErpYurPlYK2Kr97BevATuAGsGrATn8B9gIPS0Sk1CE+Btw1OC+WAQ+A7SUElIjAGuBV7VgTPgCrm7wwHyUicNnhvFCqXYsKiEZgE/A04MRXYGng/XAENkaMA0ugSkE30RTa7LY8i24vN1EBP9yWZ1kZWSMqQBU2yp3IAlEBuj71qeBFRU1ruIkKeAu8cVv/XdBCRAVo908EPDgbeLciKkDcBi44HDkDPHe8N4doIfvDIuAWsMfo0Axw2PhslhIREN+BA2C6Ua6Xcr5UColJ4Byww7Cr+4HThudsBBuMiZTSqZTSt0wTk+Nk0H7oDGwArtZtYwQd5F3AJ88i3jNwHnhZwHmhD8L3xvT7F0cIp53pYqFxSjUVMGXxIoiGAma/zA/Wh7UrdltFWAvZujrndV12gWZIay2GrIdYfW9Xzgt1aZcsAiwROAjctCzWAluAJ7l1LQIeQ5HW0cMjYFtEgOabrz2WC9LLrTXoDBwt6IiXbNM/SMBxr9WCZDcxJ2BFPSIfNvu8KaS5ZZdXZz+y0+5cBNSsh1u+AnyO3EJqFVUHjgCHoEqrttGoRfOm+3W/rblR39GNpQ78jQRpoKsCo7GiZvy6apcDi6H6aSmHHNF3v4a6+v8ReFH/2KERy7Omu9NUQBM0uFWKakdbo00BnTCoDvz3jAUMm5GPwC8zcpw3HdbLKgAAAABJRU5ErkJggg==",
        sk_gs_killer = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAADB0lEQVR4Xu2YTYhOURjHf6/RaGrQSI3URKmxkJ2aUhYikRqRUspC7CyspJSUshopMntlQ4rsfOyIEhGhiCxE+YjGx4jo0f913nq97r3n3HvPO9fU/dWtmd5zn3Oe7+fchpkxnZkxnQ8vagWqpvZA1dQeqJoyHpgDLAb6qlQijwI9wB7gFaDuNwG8ACaB78Bt4BjQP6UKqRMHPAvN7IaFczBAZtK+B8xsjZn1m9m6EBkhHlCoyLornWV3Ag1gHrAJeJ9g8cPOQ8M5vfEBeA08ARaFvNsImIXOAVuBb8By4HmH4F7gIrA+ZcMLwI+O3yTrq5P5BrgD3HL/r3DGOhGigC98trdFzbYMlw6Z2WR4hCXy04WPzrTKzE6a2REzG84KJV8IyfJCFjubYZGXzopluAc8dQIUtnoGgflZQmd6dlzmflepVFwuTVmvCjXkkfURmmHxBZp/t+JdMa/nV9teyq3dCaH3LxnuUSX43OHs/Qnre8yaVcfH/YCqMmJmx134XA5Yn5kDAyknGjWzXjPrM7ONZnbXd3LHs4ADDZrZGbduzO2TmadZVUgN6W3ETqtqs6BMkiSRlcQqfSp1oWwAZgGzgfGEl26GCsqDTwElWgingUsu6ZSkV9pe+uSU2hIiKC++KvQAgrrpDteR1bRUjcbaDvLOVZ7u4EksVZ0YTPgaUkCCJ67xNTK1+BioKR2KIagTnwKdc08ZdHeIjk8BdUiVvxg8iiEkrwdUSlVVYnA9hpC8CgjNOUVQKVV5bRkgaxgsjK+MqhvPzSn9KLCv7R0ZYEnQYFYAXw4MuLE2D7uAzc5zOrwuPK0xOTq+G5luR7pOlkF5pBGjK/g8EIOrMYSk4fOA3P/YxXBRlEOah7qCzwNy/+oSvWBvNw8vfB5oobvptcDBroWsnreC5cbngRbqxvqkEvap4w8Pc5+mAKEKCIWTQmJtYFgkffCKT8ExVvdl3V3TOB9yny2491/vheZAGmpUI8Co+1J9yt3MpoyyClROnhz4L6kVqJraA1VTe6Bqpr0HfgMSUTHwSXqt0wAAAABJRU5ErkJggg==",
        sk_gs_misc = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAERElEQVR4Xu1ZW4RWURT+ajIaxhAREUMMiZgMUSJShiEi0mUSiTLpqV6Gkkn0FFGi13ShREQiSplI6amiC6WUUiali26+fL9zpn3W7Mv5/zPT39DHMLPP2muvtfZe315rzxSSmMyYOpmNF/470Gz86zswJxWgZjvQBuAAgG8AhgC0OAb3A3gO4CKAmUFHxEJN/DnDIoZJziY5aMYvhmycltqiCcYtAGudNRYDeOlZc3rIjmYfoRshwwzeTKQDOrddQO0814uvJSeEdVc4/x0kr5izerakvi6SR0h+cebr92UkW0guJ/na6D5PcgvJTneNKg70mwVyzEs40ROYJ+Nde/S3D7dduTI50ApgIDsmLlYFtn+jGV8GYLNDkYsC8x6ZceXH/YDsHySiNZPkPScMx0jOIDmX5IdAhJ6TnENyFVmLVo7D2fHoC8zbZWzRER3xyBZ2IOZAG8m7gcUaxUGypldnWZzvQgFRbsgmyQyZ729JHiBrR3DU7pgDVsF4odcxoNuj9AnJn2b8ZCMX2efk+WsMP5xp7z0q5nrGGroHjgJ44VFWBTcBXHMU9JVUtrSRi+wTgN2JBU4A2ARgCYD9AJ4l5PcC+OXIbDfy7wAsBHDKjHcANTYciwQL6bz6oEtncWDuykiyLDVzdCldzuQvZQyX27QtG9eFNj9kp88B0ZeMEGXaZMqRuqzWRBwXk4iG3bVnBQyULdEg24/i7xQOpZRmfO/eHz5cz+SiBqbWsjex/5wVcc57FovQOVdOxKDE7EzIJNGIA2WZ6V5y9WIH1hCsA2KeFMLtXREqsWP4DmAkIZOEdUAXxqvErFAxZqEiLobHQI02q8GTJCrW1ptCzIUKLMnEEkwsFcJTkluNDulrNTrVF6jUqIuFrHDOxRbi7PaAcjGZKlIfVMTJMHedvOZSw+I6kTf2F2JslaKpUPMhaCe0U7qMZJS4fWfk7lC1aXld8i60O4q6Sm8XA/VcZK5TivR4QpeYq39PSeW6rb3BjnVkPQB6q2XYGAwChWrzQkn9d0JyMQdWl1ReL1y9H01xF0J78Esky9VOviy5xWXxIEt+nXNfraUjppzSg4FtJ49nNVqBBFJJLEZxnzf0uwo1LRSCklWVquTUBuYQMykoejLxweaHdPhQ6M5SDui73irFDvscmlPPqtbPB7fYk5wirf5XxkufGMUHW6Eq0lrXQmOju1DGgZCMON0HRTimNxRZ218ocL5yXo9ppZr6lHOKmF1AjU4e6dB8RU9PK1eN98q3fBdkvF75XKg81+VW0D9F3lSA2GE2UGv59AigSrVMQZhDr9HDJdZXi7nBJ1f1eV3G2he1ehB8bTBQ4edF7B74G1hRcpHuf9UB2zPouX2HZ1fDu5wqVyf4u5r5/P1UVJuX6apKxffCw0jlWzmJxwP6B8mC7CVaXVoOEcQ6AKdjxFCVhZqOZidxZfx3oNmY9DvwG45XbM+IZTb4AAAAAElFTkSuQmCC",
        -- [v53] иконки вкладок как у skeet - из открытых наборов (те же, что у skeet, где совпадают):
        --   Font Awesome Free (CC BY 4.0, fontawesome.com): crosshairs, user, gears, floppy-disk, circle-half-stroke
        --     (+ 8 лучей дорисованы - World как «Visuals» у skeet);
        --   game-icons.net (CC BY 3.0): curvy-knife - Lorc, headshot - Skoll (у skeet там свои рисунки, взяты ближайшие открытые).
        -- Свою картинку можно подложить: <папка скрипта>/icons/sk_icon_<вкладка>.png - файл не перезаписывается.
        sk_icon_players = "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",
        sk_icon_world = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAFhUlEQVR42u1bPWwcRRT+Zm+t2A44CWADSQGIggqRIhRAB4gKCSGoQAoBCYMowKaiB1EighQHmyCHBikUICEqS1ARkQKJmI4CJUQyP1FsfhwS2+fbj8LfiKfRnm9/5nwH55FGu7c3O+//zZv3Zh1JDHJLewjbBb85aAzgoGvADQCGdH8dwFovkEh6CPNjAD+qT/VKIL3UgH0ADuh+dBBNYNP4gdagrgKuzYrwv/YBfdWSiu8kfUpL0m0TSABkgdpWXc8zMxcjBFRZDo5RNcBPPAVgXki7Gva710htT00/QuE0JRyT2BrgJ5wG8I7uNwC8BKAhoEWl6Me9AmC/7i9WWA2c8GoBmAVwzDw/XlQT0pIA79P9NQCTejZZkgl+zHc1wmNL/ByAF4XTqHB0heciWaQ7konu57jVruk6p+eJxhWds0EyVU9KvBcVF+wgYGeIdm3+TzXG7ZQgyjDAEmER+FvX0/ov2eYd24dJ7lcfbqMhISGJnp8OYM9t8862Pa2whc1k85P6Pan/FnPsriE7bSn2fwTAowAOAzgI4EaNWwXws/zCl+p/BnNYHBbNHmKuojMu5QO2U8V5klNGQqHUJ0i+RfISi7dLJN/Uu6FkPYwpwa7ifyqbQMgEF6hn+Pw5kkuGsE2STV1bOYSvq/u2pDnCeZNt8NgxBljCQ+ITkjOGkCbJLIfgJsmvSS6S/Ms8zwJGzBgpuxy46CUDQmeXkPzEEJgnac+MZeMAD5J8iuSnZtyG5qDmTKo4up1igLf59w3y7ZpnwArJm3PmepDkN4aJXhtOBrD6hgEeoWcLEB8y4IAxm4aZa4jkB4YJfs5nYjIhlg9wJG8heVkq3yrJAARqbdX8lGFqRvI3wXIxfEASaR9O7cTGy+7G2rSW4vkGgJcBfKsMchPABIDXBLM2/q5mZchvOsYA/ADg1oKI+a307wDu1tVtE0gdAXDOMPxXAPcogHJ18gl1OdjQ9WEAt0WSfqgJDWnAF7pvArhdMC0O0RiQduh5CZDHJAV2MXk6b7SHgom6+Kdt0tVlJATF9nWyQ51SZ5QJrJr9w+E2SZTNKjlBb0cjAF7VlQFB/vdHAC4Y+xzWxgZdZAAAXFbm6F79PqRU2rrJ/pTBPwGQhRowAuDtDnZ8VhP4yYeNVFwXM74ZgJWgtjgiBlTGP2/gRkGJ9GsrhX+oAU0AC5JoqELewy8H+bs12eZNOe/ENAMnGL5dxVZVuRb+aUDMKoAnSgYra0pm3NGlVcCr/wSAO83zJam/M1Itg3/WzgSSDt3lxAHnu7gMepgPSLLrgnO+TRxQBv9cBmQdeh6RC11cBj1jjwVxwUKHilMh/GPE7FAO75eyZamCkWYLwP0AHtf9kGB9FaO0nkSQTirb+zCwx1iF2xTAjGGGA3BKMNO6ZpdE9NDHFazE0IKGCPNlryPy8EOC8V4sZsdiQALgCoDXTcmqSrzfMJJOJekXTHjrVJ+8Es3cupASOxkhJfYQyXM52aCZfk2JhUnRMxWSoodIPk3yszZJ0TMGRl8lReukxTeUFv8+SIu3grT4iX5MixcpjBwtWRhZyymMHO3HwkiZ0ti4ylxlSmM/6Z3xfiyNWeJmDdLTOWppndUYySelzmdJXpQPWCZ5Qc9OaMxYmzn8/NMG7mzVyvBueXz3gAR7ekTGGZXu+yMy0VUvUsxRxhRrnxCJezJjK5c4YjI5V7t4UiVKKBxr+Ul1fUOh8ArJz3PW9xjLcVQN8Jued4NUetXt6Cj+/V5gX83PbhyA56sclU0r7vxiZIdbhoDNCN8eVcIrrVGo6LfvBbLd7wV2GYD/3HeDWa+rTb1kwB6jgXt7hUTdEyJ1TpXcZSo9f2DrmKzDDn9R2gsG7PqAoOQV+oOBYUBflNn/AQeT3Bibw37UAAAAAElFTkSuQmCC",
        sk_icon_skin = "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",
        sk_icon_survivor = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAEsElEQVR42u2bz4scVRDHP69nCPmlQUiMJLoB40WFsBKRrOKi6MEfiO5RyMkgycHoP5CjuZgcchXxpOQYFH8cVBAREfyFpwhZDCYxiklAEiUbsjtdHlJFimbGeTP7uuf1bgqant2d7npVr6q+9eNtEBFWMxWscupOiG+o3KVyX5EKCM7iegME7ui9bEoZoaEY0HFC289bgE3682XgYp/v9NpuAYXuZA/YADwPvAA8DGwH1un3FoDzwA/AR8DHwFW1mqAWUQ+JSF1Xx30+ICLzEk/zIrJ/wLuSXnW5gJnvFPAu8HTF94MLgLh4IJVY8DmwDzhXl0vUoYBCTfZB4FNVwpL+PhZ2S726wBngOeCke3e2CjCf3wZ8C9yjwo8ba+zZs8CjwB+pY0JRE7a/n0B4C9JLakXv9ckfslKAmec+4IkEwleV8CTwivIocnMB25F16qtT6gqpFloqj7PAAwqbSTLHImHUF8X5Hal3yVnXDg2I4pAiCwXYTsxV4CxpyqLXXMq6oUhk/j311d2VnD81wgTl0VWeIRcFAGxW+Esapfvw2a68yEUBRpuAtQ0UVmuB2281RDJUwGXgWgNrXgCu5ASDtohLmqpSIwqgPC7lZAGGyUtaz0tN9bt1iX5UXp2cEiGLxh8MKHVT8QjAiZRI07ZU+IymwtdyS4VN2KvA4RraWKaAwxoEi1RxJmU/wJv+F1q9pagI7R1fAk+lVm6bGiIzwJ85N0S8qZ4HnlGftXq+HPE9JvxvwLN1dIPqygRLhaiTwOPcaGx2lVdPr9JVd+Kg0/5e6DOfAbP6rk4t8NpQW3y/iJwaoS1+qtIWL9rWFq/GBAHWVwYjd1cGI7+7wcgnTQ1GJj0as6ruChMajYUGzwf0G46yWoajt8bjAyo7WekHJILr5cUK7a1D6naHOlwguOhfJm6IJldG6lqgqAS4bcBDwDRwL7BVoS/8j2ssAH8Bp4GfgZ80BfaBssytGPJT243AS8DLwGPcPAWynFbbN8Bx4EPg3z48J6oAy/XXAAeAN3S3q6PuUZoY4oT06fqvwDHgbWAxSa6QKN2dEZHvXSq7pFcpy6fSvc/oOxHZk+L0yLgPBsf4dRFZ1IUtikhP6qOe43VdRA46JYSmFOCFP1LZpabIW9dby1HCOAro6v2o2/VSmqfSWcORytpqU4Dt/EFnhpMQ3ivhun5+bZyYMAoKWMR9RGHJZ3mTJJ8tzmhJHY0OxQhJjijUveNS6EkL79fQ1bWt0bWGlAqw7OtVYJebzORCNpma5sYZpTJ2fTEuYJpcD/yinRzJcLJsDdlzwP2x54iKEc7/zGmbu8x0rG6p8ZQ7qtNJ4QKWxu7NoX6PDIp7K2sf2wVMq3cB81roSCbBb5DwAfgHuA+4MKxoKiL9f7cKX2YsPK5ncJt2nociVawCpmNNKpNg6NccUsDgTtpHO1OggD18Z0aJTyxsb0mRCJkCNrQEAfy6N8ZYQDdSmxfdidDcj9b1FP8vxFjtMBi0omIW+KplMWAW+HpYYRSTChuOvggc0n5fznnAaeBNbaAObZzGlsP+RXc4vwoZCW7r+XuUrvE4/YA2UPRax2mLhxYgAHXOBlfU/9v/B6KpU+2q9UbfAAAAAElFTkSuQmCC",
        sk_icon_killer = "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",
        sk_icon_misc = "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",
        sk_icon_config = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAEMElEQVR42u2bTYgURxTHf/3hLuxGxNXLxr3kEvCgEBDdQ0ASRQzJwYuQQ3KIgh4F41lE8LYKkosi2Uu8rwdBETeXRFY3EkiEhMTcIp78QERxd2fmeehXWIw7090zVTU9HwVFMx/d/d6/3ne9ikSEYR4xQz5GAIwAGPKRdnBPAkQ9oreh09mISniBBKhXYNESBUFCSoDN/CywC9hiQPTIrOjza8B/wB3gf0t9u5cGEcmbiV73ichd6e14ISI/iMimJto6nnkqYFb+OHDJWpVeqEKk9AD8AXwFPOpWNdsBYB78GfCzpXdJD/VfVB02AH8DB7oFoR0Asc5l4BN9QUI1Rk3tV9cgtALAPGwWWNLVjwuuUN1DrBL7AiFto28Ae5SpIgAYi53ix//H69BeA7YDtzoFIY/YzQXdnGH+DbAA/OuI8UllbKc3EFq4h1SvZ9T9rLVxTXURaYjIYxHZ1a1bakHLRetd6w1D318iMlPGRcYOg5VTwH1gTFfGxdygK3wC+LNN8NMsCTMqAbHvZMi4xVfAbX1ezeFcUxAAblr2gAIgbCtiu1xlgytKrLMYfR0Je13QphkQbgCb8sL12GGURoCcoKhhXwN2AOfypCAe4DS/AXynqtDSHgwqAJFKzQSwtx2vg1wREp0fDXNJLLK8iFcAJJBIU9Wi6LgiHXvwCLY+Vw6ASC3sJLBfLW+K20hwTd/1hQ+1TR2u0BzwEPjNg0u7oH69UUUAYgVgGvhFs8F/HNH3gWZ4XpjHYe5upGAc+DpQPaBSANgguM4HYp/uOsVf5ZbR3uCA7g260mmxVCXSGQ86AMZGtFKTuqdgqhIAiGUjHgO/8q54+jHwKfBhB/l/XwBgV3VOA/PAc96vQB8BzmrYGwSENBDzAE+BL4F7vN9nIArIebId4OvAVAgQ4oAAfKPMj1k5hCl+1vW7MeAu8G2gLNM7AMaoLZBVdVNgtQVjor+lZAXNa3pvfRDigPkSOb0R+x/7PRAyewYrwIMmv1+klPVA7018qkIICXgNvCyh0+Y/LwvuBVQegAlgY4n9A/Ofjb6qQKEAMJZ+XPP5qAQAEdmO8LjlIfraCB4t4dONsTwyCNmg6ek7BBxUnz/WAggTB9TI6n+HcvKGvpEAw+xVspabVctDmOJnYsUBs8BPgfYcgwKwBVgEvtcwtzkSnCLrMVgM1IQZNBmya/tzCsJ62eB01bLBZw6DELtmOA0cDlAPEE3CSgNgmF52XKmJLH1vNFWEYscGzwC53C4Iy2uUjMg2OqrWKFkkCUuA34HdFuCljKAJZE42fe4H5o0KncwLpIo2Sx8DLve4WbrsYY5jwJXcnsES7fKfi8iSVH8sKa2FegWLnhix+/P2kB2Y2BrKVxfMHp+Q9SneK3Ogoh+PzDilNerg5GhSgVV31q0ejY7OMjo4OQJgBMAQj7d6981gmCyHUgAAAABJRU5ErkJggg==",
        -- [v52] плоская заливка для бегунка скроллбара (вместо стандартного скруглённого Roblox)
        sk_white = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFUlEQVR4XmP8////fwYGBgYmEAECAD34BADjxVnCAAAAAElFTkSuQmCC",
        -- [v54] фон skeet - точная плитка 4x8 из MenuBackground.h (21 / 14 / 13), весь фон 648x548 - её повтор
        sk_pattern_3 = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAICAIAAABRUclSAAAAOklEQVR42jWKMRIAQQjCIo00/v+rWrmFdzQMCVFVtrvbtmwDEQGou4HdBQQA53WHmQGUmfzRsW9cnX/Dig9qGI8KvwAAAABJRU5ErkJggg==",
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
        camera = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAJKElEQVR42u1aa0yTWRo+39fbV2gqFBuuW2QQXWrYMSggiMq2uomOUkSiEEcJySZkg/wwootoXKOJGZjoRuOqDMzEIe76Q1eK0RgJKjs6paTAxksGym4NSFHCpYjY0tv3nf2xvuT40WJbcebPnITQ0HPe87znPO973gsI/Tp+2UEFvYCiEEVRiOM4hBBCAoEAyWQyKjU1NXzt2rW/TU9Pz0pJSclQKBSqiIiIBIwxfv369ZDNZnthNps7u7u7Ow0Gw3/6+vocdrsdgxyK+j8UjPGn05am6dnP4eHhKCsrS3bmzBnd4OBgBw5yPH/+/F91dXVfZGRkhMvlcsrXHgs6BAIBQgghhmHQ+vXrF129erWSBMSyrIfjOJbjONYfaPieZVkP+fdbt279RaPRREokkvf2WhiOUdTsqSxbtkx88eLFEtjY6/W6vF6vC0BzHMd6PJ4ZX0rwv+M4joX1MOfChQvFqampErgJoNVHUQbAFxYWxj19+rQZY4w9Hs8MubHX63W53W57oPRxu912/nqPxzODMcZ9fX13tm/fHsffP+STp2ka7d+/P93lck3D5nCKLMt6SOBut9v+4MGDv05OTg7wQU9OTg60t7efBaAwH+jEcRwLshwOx8S+fft+B3QK+iYoikICgQCJRCJ04sQJDcuyHpZlPfzN4XNnZ+d31dXVa/Lz82Pi4+MFJpOpCRQEgCaTqSkhIUGg0+liampqcrq7u//uSxbQzOPxzNTU1OTQNB2cEiTnq6qqMoCn5JUDqCdPnvyzpKQkMSkpSUjKMBgM3/AVMBgM35BzkpOTRaWlpcn9/f2tQCOSUnC7lZWVnwdsE+DjEUKouLhYZbfbx0gQ5Dh16tQfVCqVkLSX8PBwRNM06ujoaOAr0NHR0UDOgZGUlCQ8e/ZsIdCI79Wmp6dHCgsL4wJyseC+VqxYIbFarV38k8EYY6fTOVVSUpIIc0lDAzfoTwFyDrlOLBaj8vJyNd97AWUHBgZ+BO/k18XCyctkMqqpqamcz00Ar9VqFf4eHQBnNBq/5StgNBq/Jef4klFQUBDry2NhjHFjY2OpVCp9D6tPBTZv3qwktSfd3M6dO38z3w2KxWKEEEJ6vf4wX4Hm5uZqco6/UV5ermZZ1kPePGCBw/NrC3K5nGptbf2KpA4sPnbs2PpAX+uioqKE8fHxfgAwOjraq9PpYubjMYASCoXo3LlzRSQG+H379u3jMpnMvyXn5eVF+FpoMpmaoqOj6UAMCb7fsWNH/M2bN4/q9frDHwLPX6tSqYQWi6UdXmsSS25urtzv6TU0NOyFWAV8scvlmi4oKIgNJtDyNS+QtaQXLC0tTSZtAOh4/vz5nT5lRUVFUSMjI0/BE8CL29bW9rVSqaTJ9yHQ4E8sFiOxWBxUcAaP1pIlS4SPHz++xveEVqu1S6FQzKWRVqtVkI8UcL+ioiLtk4a588RgR44cWUveAhzuhg0bImbnwofs7Gw1xpijKIrmOM4rFAoZm81m6e3ttTIMgxiGQWKxGEkkkqBPNdDbAtkMwyCRSISePXtmmZmZsQmFQgZjzCGEEMdx3pycnNQ5QsD1AfcxxrilpeXIhzi7kEkSfyxatIh6+PDh38gYCWOMb9y48WeYMxsKLF26NOsdKFogEIgRQignJ2ev0Wj8DLSHMTQ09FN9ff339+7ds9E0PZtehgKe4zik0+liysrKyqKjoz8jvxcKhZLk5OTcd7ckpiiKRgihlJSUNXOEvXz58t/BpIQvXrwwrlu3blGoGRScvE6nixkdHe0NZu/h4eGeOQKdTueUrywK3Bf5A1fZ0NCwFyGERCJR0ArAi9zS0nKEdJP+9uKHNHOMOMSkh0K/wOBTOiQKWa3WLo1GExkqhfyFHcFSaNaIJycnh2JjY1eChhRF0ePj4/0Wi+URX2Or1drX2Nj4/f379ydpmkYsywatAMuyiKZpdP36dSvG+Pd79uzZ68+IIyMjkwATQgjZbLbBOQKBi8G40YV43EJxoxDZvmcDXV1dP8BJ0zQtRAih3NzcMo1GE8kwDAoLC5vzkIXqPsnBcdychywsLAxJJBKUl5cXvWrVqmKMMQeuHWPMmUymH+YoYDQaf6IoisYYczRNC71er1OhUCQvX748zul0IqfTidxuN3K5XMjtdodEm/noRMqGvdRqdZJUKlV4vV4nYKMoijYajb1zhCiVSnp0dLSXH8zdvXv3lFKppIOlzMcGc4mJicKenp5/kMEcx3Hsq1evHi9evJj2ufDy5ct/5IfTTqdzatu2bdE/RzhNhie7d+9eQtaKAFN9ff2Xfg9k06ZNUb4SmkePHl0MNKQmX1i9Xn9Yr9cf3rJlizKYhCY+Pl7Q29t72xcWMhL1afXt7e1nfaWUVVVVGaGGByMjI0+3bt0aHUhKKRAIUG1t7RZyb8DS2tr6FVnJ9ikgPz8/hl+RgCJTfn5+TKhJPUSQH0rqd+3apeIX0gAL3OS8VQm5XE5du3btAL8ygTHGU1NT1qysLJm/cDqUsgopQ6vVKvilHMBw5cqVP0FC7zeCAeNYuXKlFCjAr8q9efPmJRg1rAm1sEUWx4qKihIcDscEuRfcwvDwcE9aWhrzwbCFn1Q7HI4JqFPyo9SDBw9mxsfHC0hFAi0tkiDi4uIEx48fz+PHO7DWbrePlZSUJPLxBVTcPXr0aC5UpUklSFrodLoYKLnAmO8GYMTGxtI6nS6GLAST8sEODh06lBV0wwOuVyqVorq6ui9AqL/y+p07d05WVFSkabVahVwup/zZgFwupzZu3KiorKz8vK2t7Wt/5XVYd/LkSa1IJAqtRwAai0QiVF1dvQbAkw0OsrOCMcbj4+P9zc3N1WNjY2ayJ4YxxmNjY2a9Xn/YZrM999WpIR8tl8s1feDAgdVgXyGnHeTi4uJiFdTyyRYTvNjBtph81V4xxthsNt+FGmywtagP2oRarZbU19d/6a/JBzSbr8lHtpT4/v7SpUu71Wr1wjX5+C2nT91mZRgGhdwXC6XRnZmZGX769On8gYGBH4NtdFsslvba2totq1ev/qhG94L+q0F2dvay9PT0zJSUlIyoqKjEyMhI1bsO5eDExMSg2Wzu7OnpMRkMhv/29/c73r59+/P+q8Gv4xOM/wHJC+txy1TZBwAAAABJRU5ErkJggg==",
        config = "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",
        killer = "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",
        players = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAErUlEQVR42u1YT0gjVxh/b5KsJmY0tRr/VN0S3SWWanNoKgahe6g9KBEvHkSiCQErgshSxC6UPWzpob0V9raC4EkixmAgBkToRtrsQVARRMpqJLbENVgNZphk/rzXS59kbRYnkzFJYX8QJsnMvO/7ve977/2+D4D3+J8DQnj93Wg0UqOjo63Ly8szx8fHv6VSqQTLsheRSGRzaWnp2+Hh4fvV1dUw27tFdZ6maTgxMfFJLBbbxbcgGo2+Ghsba9VqtcUlQVEUAACAlpYWtc/ne4IxxqIo8gghMZvjCCFRFEWe/F5YWPimtraWKiqJxsZGVSgUeo4xxul0+gpLAEJIJM/6/f6nBoMBFiV1NBoNWFlZ+Q5jjHmeZ3GO4DiOwRjjubm5MRLNgsLpdLZhjLEgCGksE4S43W6vK0gaESNarRYcHR29zMd5AlEU+e3t7cWCLly73V73rsUqB4IgpLu6uvRyFjQlJwJ2u/1rhSNL9fX1We+cAEFnZ+cjCCGFMUYKRVZtsVhsBYuA0WhsUzo96+rqTLLIl5AkgQUjEI/HD5UmcHZ2dnznBDDGAAAA9vb2XmKMEYRQkQhijNHu7u7vmTbudBsdHBxswApCFEXeZrPRd66LyOA6nQ5EIpFNpQ6ynZ0dT8EXncvlepCvlCDvFkxK3BRzq6ur3+cr5ubn591Fk9PNzc2qcDj8Ihc5nflsMBj8MbNCK0pBYzKZNIFA4FlmQZNNJ5GChtxbXFycrq+vL25BQwxXVlbC6elpy/n5+evbZj8Wi+2Oj4+3V1RUlFZd/K8coJxOZ5vX652NRCKbDMPEk8nkm8PDw189Hs/jkZGRj2tqaigli3qoFImbB1BmlYUx/s/9bO8UlQCZTeJUNoczr9lIFZQARVHXsywIgqwx1Go1wBgDhJBsMlCO4yqVCvA8/9Z/VVVVsKysTNJ4qVQKX15evuWxRqMBgiDkTATmOmNktmmahlar1WA2mz8ym83mpqamVr1e/4EU4XZ1dfX3ycnJ64ODgz/29/f/2traSrAsCwAAQKVSAVEUld9t7t27BwAAQK/XQ7fb/dDr9c5K2TZvw+np6Z7H43nscDhMxAa5KrZNqtVqAAAAvb29H66trf1w81TlOI7heZ7N5cNxHEPkBNFFPp/vSU9PTyVJqby3WQjh9UKdnJz8lPQ+EUIix3FMZqswHzWaSSQajb5yuVwPyNqSTSJza5yZmfkilUoliHBTsqWSKTWIKGQYJj41NfXZTT9kna5ut/shx3EMQkhUQv9LldjpdPrK4XCYZJ3YJG1sNhvNsuwFCTUuEIitRCLxp9Vqrbh5skuCwWCA6+vrP+VbtOQbCb/f/5SmaZhzCg0NDTXJLVaUArE9MDBQn1MaabVaEA6HX7xL2xcKxH4oFHpeXl4unYDFYtGSAXCRQXzo6Ogol9wXstvtnyOEBFAiQAgJ/f39FskEuru7eymKUivVuFKi+Wuz2b6STMBsNn9ZQj1TCgAA2tvbH0lWowzDxHU6XQ0oISSTyTc0TddLioCSvX+leqcURakkp9DGxsYvpUKCNJGDweDPOTWsAoHAs0yVWCywLHvh9XpnGxoaKPAeJYh/AIMCouBCLR7LAAAAAElFTkSuQmCC",
        save = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAFjUlEQVR42u1ZX0hbVxj/zrn3plkUK842FdvasKajYIelY+tARGn3YKdPc9Nbpa0UygaF0vkQCqUPAzukD3to0YcxfNDBZvakxT/4tIexPaQ1UBbZkKyK2mi8GVYTc/+cc/Ywj6TXJN7oTeOgHwQ0f+75fuf7vt/3D+CN7CPBGANCCDo6OjyTk5M9sVgsTCklLA/CnxuPx6NTU1M/3rlz56MjR45gAABBEHJXHiEEJSUlaGRk5F48Ho/qur6RL+XNQFRVXdvY2PgnFAo9vnTp0iEAAEmScgcxMjJyjxVYFhYWnsqyXAUAcODAAevKX758+UQikVAKpTillHCLz8/PB9rb208AADidzqx6i/yPa9eufeFwOIrTfYlSahiGkWSMUZtjThRF0YkQwggh/B8OalRWVp7r6en5GSH02eDg4N9OpxOSyWT2hymKMkMI0c03YxiG+jpuP50lFhcXpzo7O73ZLIFSbpkghHDqh4QQTRAERzAY/Km/v/+b6enpeUIIRQghxhjbza3z3xYVFTlqa2vP3bhxo7e0tLSKUmpgjLc8gjFGEUL4xYsXQZ/P9+nAwEA4qyXS3TyllDx58uSHCxculOWDtouKiqCrq+v9SCTyjFJKUj0g9f+FhYWnPCYcDoc1AKqqrjHG2K1bt2r4dyRJAlEUbXlxmnS5XFvsp2la3OxaqSCuXLnyTsY8YQaQTCZXGWPs4sWLZQAAoijabgHu1729vW2pZ2YCEYlEnvE8sUUEOx1CKWUIobxlf4QQZIsnhBDGGIuEEM3tdlc/ePDg+4qKCmwZwGbQ5Q2A1WdjjEVKqXH69OlPrl69+oFlACyf2udmKYwxFnVdT7S1tX1lGcB+E4fDUez1ehtysUC+bzZnK7tcrnLLADDGKJ8AGGOAMcY5/oZuq4XS+RwAgMfjOQQAMcMwIMdzdrz5ZDIJoijC4cOHj/JAtRoPljPxxMTE/TNnzjjzcfuiKIIsy1XhcPgXxhhLV4tlkm21UDo/5LXQ5ORkz8OHD78NhUIxwzDYpt/uxeehuLhYqK+vP+Xz+b47duzYh+ZayAq97wiAl9K5PHiXcUDTuoUdAPgBlFIjH9zOX7upai0D2I/CAfzvElnGltJun051ub24yo6WsNOFuOKCIKTtOgghGsZYtAOI7S7EmUQQBMfQ0NDtlpaWozU1Na6zZ8+6Wltbjw8PD9/lwPJBCGBHUz47O/tbY2PjobKyMmTm/vLyctza2np8eXl52o5BgG0AePacm5v7va6u7qBZcXMz1Nzc7I5EIs9yzbx5AcBHIOvr60vd3d0f8/mquWZCCL3yfl9fn6xpWjx1hFIQAHxmFAqFHnu9XokDyFb7AADU1dUdfP78+a97sYItDQ0vaxVFmZ2ZmdElSQJKMw/vCCGAMYZgMPhyZWUlbEdA28JCuq6rm3W9pRH+2toa03U9act40qY27y2MMRBCwMKUA0pKSpAkSc6CA+AJye12e6urq52EkKzLCUEQgFIK58+ff9vtdr+bsTl5XXmAs0gikVAePXr0OVdSEIRX6BMhBIIgbLnY4ODgl3yBUlAWSmWRlZWVv1paWo6a/d0cF9evXz8Vi8XC+yIPmDPx0tLSH52dnV6PxyOmWgBjDCdPnpRu3rz53urq6rydmTjreH23XdXExMT9sbEx/9zc3PLmYKCiqampvaGh4fZuOzDzWRhjwdKCI1d30nV9I9PnPPvu9YxoNPrnNhYKBAJDe10h8ZURIUTTNG1dVdWXqqq+1DRtnRCiSZLksoN1AoHA0LY3ZVmuKuSSL5e9spksYD+tWXcC4ff7u7IuuoeHh+++zkW3FaV1Xd+Ix+NRv9/f5XK5IOO+gnO2LMtV4+Pj3YqizBQSBKWUKIoyMzo6+jV3GzvHm2/EDvkXTEn7rbON78sAAAAASUVORK5CYII=",
        search = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAIiUlEQVR42u1ZfUxU2RU/930MzDAzFHaHxRFYlMqH7CKJhJXRrRqtVKNrIWkaP5rYphoX+ViNX9AaNY1/2JQmhlTExo9U3ASX7aI18Y+qlBVqJdENM29jm5CRsIbCwIgMw8y8N+/e1z/WO7l9wi7MDC1/7EkmPObed+/5nXN+5557BuA7+f8KmtUk9PU0TdMAAMBoNEJ2dnbCpk2bChwOx7rly5evtdvt71qt1sUYY8Xn8w253e6/u1yurs7Ozs+7urq+Gh0dxYqiAAAAx3FACPnfIOQ4LvJss9m4Xbt2ZT948OAP2hxEUZSp69evH1i/fn1KUlLSa4aZN+F5PmLxiooKe19f3ydUKYxxmBCCCSF4JsXpOMY4TL+7cePGwZKSkqTpDDQvymdmZvIXL178GVUgHA4HqdKEEKyqqqwoypQsy5P0oyjKVDgcDrKKY4zDsixPapqmTUxMPK+trV2RkJAwPyCo8vn5+Ybu7u5mqriqqjJVnP3/28KHnacoyhQ1QHNz8w6z2YziSmKe5wFjDLm5uYa2trY/FRcX/1RRFL8oiiaEEEcIUTVNIzzPGwAAXC7Xn58+ffpgeHh40OfzTXAcx6WkpLyRlZWVV1RUtDkzM/M9AIBwOBwQBCGRroExVkRRNLW2tn64d+/eC4qixE5sSiq73c4/fPjwj9Ri1HqsJdva2j7asWPH24WFhQlGo/G1tVJSUtCqVavMtbW1K3p7e6+yvKFepGs3NTX9JGZSI4QAIQRJSUnQ0tKyeyblJUnqqKiosFutVqT3nMFgAFEUX4vpJUuWCA0NDY5AIOClQNhQ1DRN27Nnz/fjEv/bt29Pp6Sk1qIb3rp169dLly4V6VxBEIDn+Qh41hgcxwHP8xE+AQBs3br1rYGBgR7WIHQPr9fbn5GRwcekfGpqKnK5XJ+xStONbt68+au0tDSOWnsu7uY4LuKVDRs2pA4ODv5jOhBXr179ZUyhtHPnzmyacdgNnE7np9Ty0aY8hBAIggAAALt3714SDAbHWeUJIXhqamq0oKAgISoQiYmJQE9YSjZVVWVVVeVt27a9FY98jRCKhBTlmT4Vnzt3rpJN5bOW/Px8A2sR6oXW1tYPzWYz0sd5tEK9sHLlStOzZ88e6LNTf3//fcqtWYUnfSgvL1+uaRp5VbQRhBAXDocDHR0df/H7/RrP85FiLhZRVRUMBgM8fvw40NPT8/E0PMxevXr19zDGswIRAeBwONYhhDgAAEKIyvO8QZKkm06n08NWovEQQggghODu3bt/DQQCYxzHCXTMYrEsKi0tzZ0tDyIACgoK3n/1EkcIUQEAJEnqGhgYUBBCcQegaRr09vZ+5fF4/km9/irEEnNzc/PnDGDx4sUr6DNdbHh4+LmiKCAIQtzrd4QQuN1u2e/3jzHAVACARYsWLZkzAIvFsohZnAMAmJyc9M1H3U4IAZ7nIRQKgSzLfv24xWJ5Y9ZnjB496wFunop13anN6Z8VRQnOGYDP5xvSD1qt1mSWdPEEgDEGs9mMEhMTLXoAXq93aLaJIwJgYGDgEXP0C68uMzlJSUmgqmrcAWiaBnl5ecbk5GS7fnxsbOzfc/aAJEmfs2cAAEBRUdGmnJycxHjzgEamw+FYZrPZ8ljrh0Khl06n0zVnD3R2dv6N9YCqqqG8vLwflZSUZM0HkRFCUF5e/mODwWDGGCv0e7/f7+nu7nbT0J21ZGRk8Ox9l5YS9+7d+53NZuPiBUIUv67GN2/ebBsZGfmSXvrpvpIkdURVCxkMBmhvbz+sL+Y0TdMOHDjwLlvHxHLX5jgOTCYT3L59+6S+mCOE4GPHjq2KCsCreuhN1voY47CqqvLQ0NAXa9assVILRuMJjuMi7548eXKtvt2CMQ57vd7+9PR0LurC0WQywZ07d37DWob+ffLkycfFxcVGCmIuRwQ7f//+/ctfvnw5qKqqzALQNE07c+bMD6MOVfpSWVmZ5cWLF25Zlif1t7K+vr5PtmzZYmPDThAE4Dhu2iulKIqRmBcEAerr68smJiaeszc+Ko8ePbqckpKCouYZu2lDQ4Njpkv96Ojov86ePbslJydHnO2lfuPGjamUX3rlKXlbWlp2x8wzGnsmkwmuXbu2X9+IYgnncrk+a25u3lFZWWnPysoS9AmhsLAwYd++fQXt7e2Hh4aGvqDK6i1Pxev19tfW1q6YK4HRdGQjhIDVakVXrlw5XFlZ+VuMscJxnMCW2vS0Hh8ff+b1et1+v39MluUphBAyGo3JVqs1PS0tLd9oNKYCALBr0FqLrYMAAGRZ9h05cuQHTU1NfbTBFtNJaTab0aVLl36ud7c+d3+TTEfWmRrBmqZpoVBooq6urjjqVKontSAIUF1dXeTz+YZm6jzP9KFz9EDv37//+8uXL/9C35mgQGVZnqThFFNBzGaEnJwcsa2t7SO/3z8ykwWp4tON0zx/6tSpdbShe+LEiff1yrOeqKmpiYCIWylTXFxsvHDhwi632901Pj4+8E0d6lAoNOHxeJ5KktRx/PjxVbQkYS3b0NDg0De4WE/QKmCmZhqKpgymC65duzaltLQ0b9myZQXp6elvWyyWNxVFCY6Ojg56vd4Rl8sl9fT0uCVJCs20BsYY6uvry06fPn1XFEUTrYYJISrtjBw8eLDs/PnzEs/zkft0zM2pucQm7ZFOZ0Ga948ePfoePXdYT2CMw+FwOFhdXV0UTVvzW4EIggCiKILBYPivjyiKkVN6ts2uQ4cOrQwGg+PsecGCoJyIKTvNl1AQNTU1K+jPU3oQiqJMVVVVvbMwf+9lmr91dXXF04EghOBAIOCtqKiwL1gQNDyqq6uLpgNBu+WwUIUFUVVV9U4oFJrQc2JkZORLWMgyHQjWA42NjR/AQhf2VlZZWWl3Op2fejyep42NjR+YTCb4ThaK/Ac9WEnTU22PhQAAAABJRU5ErkJggg==",
        sub_bot = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAIn0lEQVR42u1aXUwb2RU+c+fPrsHgBC/GXhwHAkUBKeojW9VKIvGCUoJAQalaiGSiEKkvkcJLUKTVSihSlYeqFauN8pCHvOxbIq3al1UiQiA/itqkq4QESP3PmPFPSMD2wvzcO30o1xobQm1CSFfaI115PHPuPefMPffc75w7AD/TT5C6urr2x+PxJ4lE4tmZM2eaGYYBjuMAAAAhBAAAAwMDjZIkPY3H4096e3sbzM84jgOGYWB4eLg1mUzOhsPh6aNHj9buifIMw0AwGLxnbNDs7Ox3TU1NPAAAy7KAEAKLxQLRaPQR5QmHw9OCIABCCFiWBQCAlpYW/tWrV3+nPAsLC98zDFOxPqjiDgiBz+f7Nf1fU1Pj9nq9NvqMEAKNjY28KIpVlMdqtdb6fD6BEFKYBY/HY6uqqnJSnubm5mP0WSXEVaI4y7LAcRwQQnSEEAcAYBgGYVkWCYIAPM/Dhjtt0oRlWcbMw7JsEQ8hRBcEAXRdB4wxEEJ2zwCO40DXdSCEgKZpwDBMQTjGWJNlOa+qKqiqCgAAkiSphBDdrJwkSaqZR5blPMZYM7kmWltb2yTzgw3geR40TQOXy4WOHz/u9fl8bvr2AQAcDseB0dHRP0Sj0SBCCBFCyL59++rsdrub8tjtdvf4+Hj/8vJyhvIcOHCg2eFwHDDNMDc2NvZFKBRavHPnzmImkyFU9o6J+mRvb2/D/fv3J1RVzRsfmdbX11cmJyf/fOLEiXqzDpUvjo2w2NPT43rz5s2/qYBSIwghWFXVvKIoWdpUVc0TQnAlPKVjp9Pp+e7ubqdZl4rePMMw4PF42JmZmW8MwzAURclijLWPPQMYY01RlKxhGMa9e/f+0tDQgBiGqWwmaKw+ffq0V9O0NUIILn1bH5OoPEVRsqdOnfrcrNO2i5hayvM8AAA0NTV9znGcRdO0H3me/0VpZ0KIbhgG+cCNEZmDAr2nadqPgiBUHTp0qJFl2UWqEyEEDMPYGh6EQqEpXdcV2t731peXl0OBQKDV4XAwPM8Dje+VNNrH4XAwIyMjh1dWVhbfNxtmnRYWFr7fEnbEYrHH5U5xIBBo3W2IMjIycrhc+aFQaKowW/Qik8ks7N+/v+V/CSKE6HV1dcK7d++MqqoqpqOjo4oQYiCEKgIytM+LFy9yuVzOqK2tZTKZjFrqTltRKpV6WV9f31508/z584dfvnz5t0Qi8WxpaemHWCz2OJvNynQaqfW6rivUH/1+f82HLli/319DN0xd1xWz6xiGYWSzWTkWiz1eWlr6IZFIPJudnf1ueHi4ddMivnbt2svJyck+r9dbzXEcymazyrlz5343ODh4Tdf1dfMipqhRVVWsKMqqqqp5QRBslcwA7aOqKjaPSYnKvH379pfXr1//trq6WtR1nUQikdXXr19rmwzgOA7m5+fV+fn5N/Se3+9/TgGbeXAaBRiGYURRtAMA0N9KSBRFO7OheWlkoTLn5uaez8zMrG6FzYoM0HUdWJYFlmWB53lQVRWsVqv1UydPVqvVSqOWpmmAMS4CeZx59yWEAMa40PRy4OBHJl3XdU3TCrohhAq6FhlACAFRFOHgwYMCx3Eok8moTqez/lMb4HQ6610uF6qrqxMwxkYwGFQoJC+igYGBxmg0+kiW5efJZHJWkqSnuVwuuV0U6uzsrKYIcieo0zAMo7Ozs3q7KJTL5ZKSJD1NJpOzsiw/j0QiD2iOXUSJROJZOYL3yoDtKB6PP9mUE5ezgfy/kFnXwsXFixd/e+XKlW9FUaxiGAbpuq7U1NR4bDbbZ4ZhEHMauRdEZebz+dTKyorEcZxoGAZRFCU3Ojp6astOFosF2trahI6ODovL5UITExMDNBfYaxeiMicmJgZcLhfq6OiwtLW1CaIobg2nEUKgKArMzc2pLMsCxhjS6XTyU7tLOp1OyrJM0un0Osa4APlpGEXmMEpzAYvFAhzHAVdxLrf7xP2XwGKxAM/zRcpvghK0JkMrAYqiKJ/aAEVRFF3Xi3ff90GJlpYW3ul0WliWRaurq6rP52umGVJp5rax0AwK5ipVjPYxNkBQKZijMn0+X/ORI0f+abfbBYwxkWV5PRQKbQZzZ8+e/eWFCxf+RMt9qqrmnU5n64bFlq3AnCAIrCiK9p0COTrGVmCOyuzv7//K7/f/nqLdbDabunr16ujNmzeDRQlNKpV65XQ6234KCc3S0tK/3G73r4puSpL0tNwQODg42LTbvh4IBFrLlR+NRh9tGqC7u9sZDoeny0nqM5nMwtDQUHNtbe2uJPWBQKB1eXk5VE5SHwwG73V1de3ftgJtsViAZVkYGxv7YqtqnLkIZR58J+19xTIq89KlS51mnUoXO1fil2CqOkM4HJYwxirHcZat4MTHwk+GYRBajwqFQhLGuKBTRaVFr9fLPXz48PqnKi1OT09/7Xa72YpLi+aCal9fn/vt27eRvS7uZjKZhZ6eHteOirulNdL+/n7PzMzMN3tRXlcUJTs1NfXXkydPusoprzPlHnA0NDSgY8eOeX0+n3t8fHyarofV1VXp1q1bX5YecAQCga9tNttnAAD5fD5148aNP5YecPT19X1lt9s91O8vX778m3A4LN29ezeeSqU+/ICj1J1MsKMAeyORyIP29vYijGu32xlzhpdIJJ7Z7fail9Xe3i5GIpEHZpi+ncwPOqXUdb2AVK1Wa1GdiGVZ3uVy2QRBAJvNBoIggMfjEcwRCiHEeTwewczjcrlsLMvy5shjtVoLiLPcgghXwdZfaGblGIZBGGOiqioYhgGapoGu65tK7hhjw8yDMSalIVlV1fJD5U7PiQkhEIlEHtD/KysriVgsljfnFPF4XFMUJUd51tbW3oXDYdWM5RcXF/O5XC5NeYLB4GS5R6u78qlBNBp9lEgkng0NDb33U4PFxcV/xGKxx9t9aiDL8vNQKDS1Z58a/Ey7TP8BRRfY7mNAJOIAAAAASUVORK5CYII=",
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
    Library.B64Decode = B64Decode -- [v75] для встроенных скайбоксов (rest)

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
    -- [v49] шрифт меню: DejaVu Sans (свободный, лицензия Bitstream Vera; рисунок почти как Verdana у skeet),
    -- урезан до латиницы + кириллицы. Свой шрифт: положи <папка скрипта>/fonts/menu.ttf (+ menu-bold.ttf).
    local MENU_FONT_B64 = {
        Regular = "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AosAAAM1ATUDrgDFBrQAngUXAKoHmgBxBj0AgQIzAMUDHwCwAx8ApAQAAD0GtADZAosAngLjAGQCiwDbArIAAAUXAIcFFwDhBRcAlgUXAJwFFwBkBRcAngUXAI8FFwCoBRcAiwUXAIECsgDwArIAnga0ANkGtADZBrQA2QQ/AJMIAACHBXkAEAV9AMkFlgBzBikAyQUOAMkEmgDJBjMAcwYEAMkCXADJAlz/lgU/AMkEdQDJBucAyQX8AMkGTABzBNMAyQZMAHMFjwDJBRQAhwTj//oF2wCyBXkAEAfpAEQFewA9BOP//AV7AFwDHwCwArIAAAMfAMcGtADZBAD/7AQAAKoE5wB7BRQAugRmAHEFFABxBOwAcQLRAC8FFABxBRIAugI5AMECOf/bBKIAugI5AMEHywC6BRIAugTlAHEFFAC6BRQAcQNKALoEKwBvAyMANwUSAK4EvAA9BosAVgS8ADsEvAA9BDMAWAUXAQACsgEEBRcBAAa0ANkCiwAAAzUBNQUXAKwFFwCBBRcAXgUXAFICsgEEBAAAXAQAANcIAAEbA8UAcwTlAJ4GtADZAuMAZAgAARsEAADVBAAAwwa0ANkDNQBeAzUAYgQAAXMFFwCuBRcAngKLANsEAAEjAzUAiQPFAGAE5QDBB8EAiQfBAIkHwQBiBD8AjwV5ABAFeQAQBXkAEAV5ABAFeQAQBXkAEAfLAAgFlgBzBQ4AyQUOAMkFDgDJBQ4AyQJcADsCXACiAlz//gJcAAYGMwAKBfwAyQZMAHMGTABzBkwAcwZMAHMGTABzBrQBGQZMAGYF2wCyBdsAsgXbALIF2wCyBOP//ATXAMkFCgC6BOcAewTnAHsE5wB7BOcAewTnAHsE5wB7B9sAewRmAHEE7ABxBOwAcQTsAHEE7ABxAjn/xwI5AJACOf/eAjn/9ATlAHEFEgC6BOUAcQTlAHEE5QBxBOUAcQTlAHEGtADZBOUASAUSAK4FEgCuBRIArgUSAK4EvAA9BRQAugS8AD0COQDBBAAAwQQAAMcEAADuBAAAtgUOAMkFDgDJBkr/+gThAMkFlgBzBRQAhwJcAMkCXAAGAlz/lgjAAFQIXADJBkr/+gWuAMkF/ADJBOAAIwYEAMkFeQAQBX0AyQV9AMkE4QDJBkAAZQUOAMkIngAoBSEAhwX8AMkF/ADJBa4AyQYEAFQG5wDJ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AAAAAAAAAAAAAAAA/9z/3P/cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/kP9r/7cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9wAAAAA/9wAAP/c/7f/3AAAAAAAAAAAAAAAAAAAAEEAAP8VAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9wAAAAA/7cAAAAAAAAAAAAA/7cAAAAAAAD/wQAAAAAAAP+3AAAAAAAAAAD/3P+3AAD/t//BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/2v/kP+kAAAAJv/cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/wQAAAAAAAAAAAAAAAAAAAAAAAAAA/2v/t/99AAD/ff9E/9wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/0//c/9MAAP/cAAAAAP/c/9P/3AAAAAAAAAAAAAD/yQAA/7cAAAAAAAAAAP/TAAD/0wAAAAAAVv7JAAD/yf9h/5AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9z/3AAAAAAAAAAAAAAAAAAAAAD/3P7wAAAAAP9E/5AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9z/3AAAAAAAAAAAAAAAAAAAAAAAAP8pAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/3AAA/8EAAAAAAAAAAAAA/8EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/BAAD/wQAAAAAAAAAAAAD/3P7c/2sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9z/3AAAAAAAAAAAAAAAAAAAAAAAAP7TAAAAAAAAAAAAAP/c/9z/3AAA/9z/3AAAAAAAAP+QAAD/kP/cAAD/awAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/c/9wAAP/cAAAAAACX/9wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/t/+3/9z/3AAAAAD/3P/cAAAAAP9EAAD/Tv+Q/5D/HwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/c/9wAAP/cAAAAAAAA/9wAAAAAAAAAAAAAAAAAAAAAAAD/0//c/9wAOQAA/9wAAAAA/9wAAP/c/9wAAP9hAAD/ff+QAAD/YQAAAAD/3P/c/9z/twAAAAAAAAAA/9wAAAAA/9wAAP+I/60AAP91/7cAAAAA/9wAAP/cAAD/3AAA/vj/AwAvAAD/0//c/9wAOQAA/9wAAAAA/9wAAP/c/9wAAP9hAAD/ff+QAAD/YQAAAAD/3P/c/9z/twAAAAAAAAAA/9wAAAAA/9wAAP+I/60AAP91/7cAAAAA/9wAAP/cAAD/3AAA/vj/AwAvAAD/0//c/9wAOQAA/9wAAAAA/9wAAP/c/9wAAP9hAAD/ff+QAAD/YQAAAAD/3P/c/9z/twAAAAAAAAAA/9wAAAAA/9wAAP+I/60AAP91/7cAAAAA/9wAAP/cAAD/3AAA/vj/AwAvAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/63/pP+QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/3AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9z/3AAAAAAAAAAAAAAAAAAAAAAAJgAAAAAAAP9r/7cAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA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",
        Bold = "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AEcARwAWAEwATAAXAFMAUwAYAFcAVwAZAFgAWAAaAFoAWgAbAIAAhAABAIYAhgAUAIcAhwADAJAAkAAEAJIAlgAJAJgAmAAcAJkAnAAPAJ0AnQATAKAApQAVAL0AvQAbAL8AvwAbAScBJwAdASkBKQAeASsBKwAfAS0BLQAeAAIANwANAA0AAQAOAA4AAgAPAA8AAwAbABwABAAiACIABQAkACQABgArACsABwAwADAACAA0ADQACQA1ADUACgA2ADYACwA3ADcADAA4ADgADQA5ADkADgA6ADoADwBCAEIAEABEAEQAEQBGAEYAEgBKAEoAEwBNAE0AFABQAFAAFQBTAFMAFgBUAFQAFwBWAFYAGABXAFcAGQBYAFgAGgBaAFoAGwCAAIQABQCGAIYAHACHAIcABgCSAJYACACYAJgAHQCZAJwACwCdAJ0ADwCgAKAAHgChAKEAEACiAKUAHgCmAKYAHwCnAKcAEQCoAKgAIACpAKkAEgCqAKsAIACyALIAIQCzALMAFQC0ALYAIQC4ALgAIgC5ALkAIwC6ALoAGAC7ALwAIwC9AL0AGwC/AL8AGwEoASgAJAEpASkAJQEsASwAJgEtAS0AJwABAAAACgCSAJQAFERGTFQAemFyYWIAhGFybW4AhGJyYWkAhGNhbnMAhGNoZXIAhGN5cmwAhGdlb3IAhGdyZWsAhGhhbmkAhGhlYnIAhGthbmEAhGxhbyAAhGxhdG4AhG1hdGgAhG5rbyAAhG9nYW0AhHJ1bnIAhHRmbmcAhHRoYWkAhAAEAAAAAP//AAAAAAAAAAAAAAAA",
    }
    local function LoadMenuFontNow()
        local loadAsset = getcustomasset or getsynasset
        if not (loadAsset and writefile and isfile and isfolder and makefolder) then return end
        pcall(function()
            local root = (tostring(Library.IconFolder or "SkeetUI/icons"):match("^(.-)/[^/]*$")) or "SkeetUI"
            local dir = root .. "/fonts"
            local acc = ""
            for part in string.gmatch(dir, "[^/]+") do
                acc = acc == "" and part or (acc .. "/" .. part)
                if not isfolder(acc) then makefolder(acc) end
            end
            local faces = {}
            for _, w in ipairs({ { "Regular", 400, "menu.ttf" }, { "Bold", 700, "menu-bold.ttf" } }) do
                local path = dir .. "/" .. w[3]
                if not isfile(path) then
                    path = dir .. "/skeetui-" .. string.lower(w[1]) .. ".ttf"
                    if not isfile(path) then writefile(path, B64Decode(MENU_FONT_B64[w[1]])) end
                end
                local ok, id = pcall(loadAsset, path)
                if ok and type(id) == "string" and id ~= "" then table.insert(faces, { name = w[1], weight = w[2], style = "normal", assetId = id }) end
            end
            if #faces == 0 then return end
            local json = dir .. "/skeetui.json"
            writefile(json, HttpService:JSONEncode({ name = "SkeetUI", faces = faces }))
            local ok, fam = pcall(loadAsset, json)
            if ok and type(fam) == "string" and fam ~= "" then MenuFamily = fam end
        end)
    end
    Library._LoadMenuFontNow = LoadMenuFontNow

    -- [v62] свой шрифт ESP; [v63] ProggyTiny; [v64] Segoe UI Semilight -> вшит Selawik Semilight
    -- (Microsoft, SIL OFL 1.1 - открытая замена Segoe UI с теми же метриками; собран из исходников).
    -- Настоящий Segoe UI - шрифт Windows, вшивать нельзя: положи C:/Windows/Fonts/segoeuisl.ttf как fonts/esp.ttf.
    -- Семейство из ttf + json через getcustomasset; нет - остаётся GothamBold.
    Library.ESPTextK = 0.75 -- [v64] все надписи ESP мельче (x0.75 к Text Size)
    Library._ESPFontB64 = "AAEAAAANAIAAAwBQR0RFRg7cDowAAHGYAAAAeEdQT1M9YEb0AAByEAAADkxHU1VCMv4vgAAAgFwAAAMgT1MvMkEPJ3wAAAFYAAAAYGNtYXDMTqKWAAAHRAAAA/xnbHlmPzJBxQAADggAAFe2aGVhZCAH9FUAAADcAAAANmhoZWEQjgvyAAABFAAAACRobXR4ay+O3gAAAbgAAAWMbG9jYe28BK4AAAtAAAACyG1heHABcgChAAABOAAAACBuYW1lgbuinAAAZcAAAATGcG9zdD83b1QAAGqIAAAHDgABAAAAAQBCoEh3Al8PPPUAAwgAAAAAANFEvFMAAAAA5wrtav9V/aMJTAe4AAAABgACAAAAAAAAAAEAAAfq/lEAAAme/1X6oAlMCAAAAAAAAAAAAAAAAAAAAAFjAAEAAAFjAFgABwBGAAQAAQAAAAAAAAAAAAAAAAADAAIABAQeASwABQAIBTMEzQAAAJoFMwTNAAACzQAyAkgAAAAAAAAAAAAAAACgAABvAAAACgAAAAAAAAAATVMgIABAAA0hIgXT/lECFwfqAa8AAACTAAAAAAPOBZoAAAAgAAMFKgAABRkAKgUZACoFGQAqBRkAKgUZACoFGQAqBRkAKgUZACoFGQAqBRkAKgbGABQEeAC6BPYAZQT2AGUE9gBlBPYAZQT2AGUFgAC6BYAAagWAALoFgABqBAYAugQGALoEBgC6BAYAugQGALoEBgC6BAYAugQGALoEBgC6A9AAugVrAGYFawBmBWsAZgVrAGYFjAC6BYwALQH6ALwEvgC8AfoAuwH6/80B+v/nAfoAlAH6/9MB+v/DAfoAOQK6AEoEbgC7BG4AuwO3ALoDtwC3A7cAugO3ALoDtwC6A7cANAbtALoF1AC6BdQAugXUALoF1AC6BdAAugXUALoGEABlBhAAZQYQAGUGEABlBhAAZQYQAGUGEABlBhAAWQYQAGUHgQBlBGsAuwRrALsGCABlBJ0AuwSdALsEnQC7BJ0AuwQdAF8EHQBfBB0AXwQdAF8EHQBfBCQAMwQkADMEJAAzBCQAMwQkADMFVwCoBVcAqAVXAKgFVwCoBVcAqAVXAKgFVwCoBVcAqAVXAKgE5wAdB1EAJgdRACYHUQAmB1EAJgdRACYEnQArBF8AJwRfACcEXwAnBF8AJwRfACcEkAA8BJAAPASQADwEkAA8BAMAXgQDAF4EAwBeBAMAXgQDAF4EAwBeBAMAXgQDAF4EAwBeBAMAXgavAFwEmACmA6AAXQOgAF0DoABdA6AAXQOgAF0EmQBfBF4AXQTwAF8EmQBfBB0AXQQdAF0EHQBdBB0AXQQdAF0EHQBdBB0AXQQdAF0EHQBdAlsALASZAF8EmQBfBJkAXwSZAF8EaAClBGgAKQHKAIwBygClAcoAmAHK/98Byv/OAcoAewHK/8ADnwCMAcr/bgHKAC8Byv9VAcr/VQPEAKUDxAClAcoApQHKAJkCWwClAcoAKgJQAKUCFAAYBrwApQRoAKUEaAClBGgApQRoAKUEaAClBGgApQSXAF0ElwBdBJcAXQSXAF0ElwBdBJcAXQSXAF0ElwBYBJcAXQdlAFwEmACmBJgApgSZAF8CtgCmArYApgK2AFYCtgAnA0AAVgNAAFYDQABWA0AAVgNAAFYEQAClAosAIQKLACEC8wAhAosAIQKLACEEaACQBGgAkARoAJAEaACQBGgAkARoAJAEaACQBGgAkARoAJADuwASBZkAHwWZAB8FmQAfBZkAHwWZAB8DhQAeA8AAEgPAABIDwAASA8AAEgPAABIDqgA6A6oAOgOqADoDqgA6BDgAWgOVAJsEOABlBDgAiwRIACAEOACCBDgAdAQnAF0EOABjBDgAYAbkAHEGlQBsBsQAagK5AH0CyABYAsgAZQNLAFUC+//mAcIAgAM2AK4BwgB3AcIAMQWZAIwCRgDCAkYAwgTIACUBwgCBA4QAgQOEAGoC6QCqAccAqgHCADEDBv/4A1IALQJWAF0CVgBFAlYAzQJWADUCVgCUAlYATggAAAEEAAABAzEAkQMxAJED4gBsA+IAXAKBAGwCgQBNAtkANgLZAOQC2QDdAcYAaAHGAGABxgAxAjEAAADHAAAEOACvBHMAdQQ4AGkEOABaBDgAXgQ4AFAEOABFBVYA5AVWAN8FVgDfBVYBBQVWARAFVgDfBH0ApAVWAQ4GaQBRCZ4AUQVWAN8FVgDfAd0AsgHdALIHmQCqBf0AdwO7AGMHFgCfBxYAnwOWAGYGMABJAw4AfgVWAPUC+gA6AvoAOgAAAIYAAABYAAAAYQAAAHIAAABDAAAALgAAAG8AAAB9AAAAJQAAAFkAAAAmAAAALQAAAJkAAAAxAAAAgAAAAEsAAABqAAAALQIfAHwCaAAl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AY4AAwABBAkABAAiAV4AAwABBAkABQAaAcYAAwABBAkABgAiAeAAAwABBAkABwB2AgIAAwABBAkACAAqAngAAwABBAkACQAUAqIAAwABBAkACwBGArYAAwABBAkADABGArYAAwABBAkADQCYAvwAAwABBAkADgBMA5QAAwABBAkAEAAOA+AAAwABBAkAEQASA+4AqQAgADIAMAAxADUAIABNAGkAYwByAG8AcwBvAGYAdAAgAEMAbwByAHAAbwByAGEAdABpAG8AbgAgACgAdwB3AHcALgBtAGkAYwByAG8AcwBvAGYAdAAuAGMAbwBtACkALAAgAHcAaQB0AGgAIABSAGUAcwBlAHIAdgBlAGQAIABGAG8AbgB0ACAATgBhAG0AZQAgAFMAZQBsAGEAdwBpAGsALgAgAFMAZQBsAGEAdwBpAGsAIABpAHMAIABhACAAdAByAGEAZABlAG0AYQByAGsAIABvAGYAIABNAGkAYwByAG8AcwBvAGYAdAAgAEMAbwByAHAAbwByAGEAdABpAG8AbgAgAGkAbgAgAHQAaABlACAAVQBuAGkAdABlAGQAIABTAHQAYQB0AGUAcwAgAGEAbgBkAC8AbwByACAAbwB0AGgAZQByACAAYwBvAHUAbgB0AHIAaQBlAHMALgBTAGUAbABhAHcAaQBrACAAUwBlAG0AaQBsAGkAZwBoAHQAUgBlAGcAdQBsAGEAcgAxAC4AMAAwADEAOwBNAFMAIAAgADsAUwBlAGwAYQB3AGkAawAtAFMAZQBtAGkAbABpAGcAaAB0AFYAZQByAHMAaQBvAG4AIAAxAC4AMAAwADEAUwBlAGwAYQB3AGkAawAtAFMAZQBtAGkAbABpAGcAaAB0AFMAZQBsAGEAdwBpAGsAIABpAHMAIABhACAAdAByAGEAZABlAG0AYQByAGsAIABvAGYAIAB0AGgAZQAgAE0AaQBjAHIAbwBzAG8AZgB0ACAAZwByAG8AdQBwACAAbwBmACAAYwBvAG0AcABhAG4AaQBlAHMALgBNAGkAYwByAG8AcwBvAGYAdAAgAEMAbwByAHAAbwByAGEAdABpAG8AbgBBAGEAcgBvAG4AIABCAGUAbABsAGgAdAB0AHAAOgAvAC8AdwB3AHcALgBtAGkAYwByAG8AcwBvAGYAdAAuAGMAbwBtAC8AdAB5AHAAbwBnAHIAYQBwAGgAeQBUAGgAaQBzACAARgBvAG4AdAAgAFMAbwBmAHQAdwBhAHIAZQAgAGkAcwAgAGwAaQBjAGUAbgBzAGUAZAAgAHUAbgBkAGUAcgAgAHQAaABlACAAUwBJAEwAIABPAHAAZQBuACAARgBvAG4AdAAgAEwAaQBjAGUAbgBzAGUALAAgAFYAZQByAHMAaQBvAG4AIAAxAC4AMQAuAGgAdAB0AHAAOgAvAC8AbwBwAGUAbgBzAG8AdQByAGMAZQAuAG8AcgBnAC8AbABpAGMAZQBuAHMAZQBzAC8ATwBGAEwALQAxAC4AMQBTAGUAbABhAHcAaQBrAFMAZQBtAGkAbABpAGcAaAB0AAAAAgAAAAAAAP+cADIAAAAAAAAAAAAAAAAAAAAAAAAAAAFjAAAAJADJAQIAxwBiAK0BAwEEAGMArgCQACUAJgD9AP8AZAEFACcA6QEGAQcAKABlAQgAyADKAQkAywEKAQsAKQAqAPgBDAENACsBDgAsAQ8AzADNAM4A+gDPARABEQAtAC4BEgAvARMBFAEVARYA4gAwADEBFwEYARkBGgBmADIA0ADRAGcA0wEbARwAkQCvALAAMwDtADQANQEdAR4BHwA2ASAA5AD7ASEANwEiASMBJAElADgA1ADVAGgA1gEmAScBKAEpADkAOgEqASsBLAEtADsAPADrAS4AuwEvAD0BMADmATEARABpATIAawBsAGoBMwE0AG4AbQCgAEUARgD+AQAAbwE1AEcA6gE2AQEASABwATcAcgBzATgAcQE5AToASQBKAPkBOwE8AEsBPQBMANcAdAB2AHcBPgB1AT8BQAFBAE0BQgBOAUMATwFEAUUBRgFHAOMAUABRAUgBSQFKAUsAeABSAHkAewB8AHoBTAFNAKEAfQCxAFMA7gBUAFUBTgFPAVAAVgFRAOUA/AFSAIkAVwFTAVQBVQFWAFgAfgCAAIEAfwFXAVgBWQFaAFkAWgFbAVwBXQFeAFsAXADsAV8AugFgAF0BYQDnAWIAEwAUABUAFgAXABgAGQAaABsAHAD0APUA9gFjAWQBZQANAD8AwwCHAB0ADwCrAAQAowAGABEAIgCiAAUACgAeABIAQgBeAGAAPgBAAAsADACzALIAEAFmAKkAqgC+AL8AxQC0ALUAtgC3AMQAAwFnAIQAvQAHAWgApgCFAJYAYQC4ACAAIQAfAKQBaQDwAAgAxgAOAJMAXwDoACMACQCIAIsAigCGAIwAgwBBAIIAwgFqAWsBbAFtAW4BbwFwAXEBcgFzAXQBdQF2AXcBeAF5AXoBewCNANsA4QDeANgAjgDcAEMA3wDaAOAA3QDZAXwBfQF+AX8GQWJyZXZlB0FtYWNyb24HQW9nb25lawpDZG90YWNjZW50BkRjYXJvbgZEY3JvYXQGRWNhcm9uCkVkb3RhY2NlbnQHRW1hY3JvbgdFb2dvbmVrB3VuaTAxMjIKR2RvdGFjY2VudARIYmFyAklKB0ltYWNyb24HSW9nb25lawd1bmkwMTM2BkxhY3V0ZQZMY2Fyb24HdW5pMDEzQgRMZG90Bk5hY3V0ZQZOY2Fyb24HdW5pMDE0NQNFbmcNT2h1bmdhcnVtbGF1dAdPbWFjcm9uBlJhY3V0ZQZSY2Fyb24HdW5pMDE1NgZTYWN1dGUHdW5pMDIxOARUYmFyBlRjYXJvbgd1bmkwMTYyB3VuaTAyMUENVWh1bmdhcnVtbGF1dAdVbWFjcm9uB1VvZ29uZWsFVXJpbmcGV2FjdXRlC1djaXJjdW1mbGV4CVdkaWVyZXNpcwZXZ3JhdmULWWNpcmN1bWZsZXgGWWdyYXZlBlphY3V0ZQpaZG90YWNjZW50BmFicmV2ZQdhbWFjcm9uB2FvZ29uZWsKY2RvdGFjY2VudAZkY2Fyb24GZWNhcm9uCmVkb3RhY2NlbnQHZW1hY3Jvbgdlb2dvbmVrB3VuaTAxMjMKZ2RvdGFjY2VudARoYmFyCWkubG9jbFRSSwJpagdpbWFjcm9uB2lvZ29uZWsHdW5pMDIzNwd1bmkwMTM3BmxhY3V0ZQZsY2Fyb24HdW5pMDEzQwRsZG90Bm5hY3V0ZQZuY2Fyb24HdW5pMDE0NgNlbmcNb2h1bmdhcnVtbGF1dAdvbWFjcm9uBnJhY3V0ZQZyY2Fyb24HdW5pMDE1NwZzYWN1dGUHdW5pMDIxOQR0YmFyBnRjYXJvbgd1bmkwMTYzB3VuaTAyMUINdWh1bmdhcnVtbGF1dAd1bWFjcm9uB3VvZ29uZWsFdXJpbmcGd2FjdXRlC3djaXJjdW1mbGV4CXdkaWVyZXNpcwZ3Z3JhdmULeWNpcmN1bWZsZXgGeWdyYXZlBnphY3V0ZQp6ZG90YWNjZW50B3VuaTAwQjkH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AJIAkgCYALYAtgC2ALYAtgC2ALYAtgC2AJ4ApACkAKQApACkAKoAqgCqAKoAqgCqAKoAqgCqALAAtgABA6MFmgABBfwFmgABBUMFmgABBIoDzgABAbYEFAABAdkEFAABBIEDzgABAg4DfgABBFQDzgABBGgDzgABBIMDzgAGABAAAQAKAAAAAQAMAAwAAQAUACoAAQACAU0BTgACAAAACgAAABAAAQDsAAAAAQDVAAAAAgAGAAwAAQC0/aMAAQDh/k8ABgAQAAEACgABAAEADAAcAAEALACmAAIAAgFAAUQAAAFGAUwABQACAAIBQAFDAAABRgFMAAQADAAAADIAAAA4AAAAPgAAAEQAAABKAAAAUAAAAFYAAABcAAAAYgAAAGgAAABuAAAAdAABAZ4DzgABAMMDzgABAYcDzgABAL8DzgABAPQDzgABAXUDzgABAYMDzgABATUDzgABASUDzgABAWMDzgABAaQDzgABAOADzgALABgAHgAkACoAMAA2ADwAQgBIAE4AVAABAaAFXAABAMUFYAABAQcF+wABAMgF+wABAXcGAQABAYUGAAABATcFpwABAScGGAABAWUFoQABAasGWAABARwGigABAAAACgDaAW4AAkRGTFQADmxhdG4AHgAEAAAAAP//AAMAAAACAAsANAAIQVpFIABCQ0FUIABQQ1JUIABeS0FaIABsTU9MIAB6Uk9NIACIVEFUIACWVFJLIACkAAD//wAEAAAAAQACAAsAAP//AAQAAAACAAMACwAA//8ABAAAAAIABAALAAD//wAEAAAAAgAFAAsAAP//AAQAAAACAAYACwAA//8ABAAAAAIABwALAAD//wAEAAAAAgAIAAsAAP//AAQAAAACAAkACwAA//8ABAAAAAIACgALAAxhYWx0AEpjY21wAFJmcmFjAFhsb2NsAF5sb2NsAGRsb2NsAGpsb2NsAHBsb2NsAHZsb2NsAHxsb2NsAIJsb2NsAIhzdXBzAI4AAAACAAAAAQAAAAEAAgAAAAEADgAAAAEADAAAAAEABAAAAAEACwAAAAEACAAAAAEABwAAAAEABgAAAAEACQAAAAEACgAAAAEADQAPACAAUgBoALIAyAECATABMAFKAUoBSgFKAUoBXgF2AAEAAAABAAgAAgAWAAgAVABZAKMAyADOAPUA9gD3AAEACABTAFgAogDHAM0A6QDqAOsAAwAAAAEACAABAP4AAQAIAAIAmQCdAAYAAAACAAoAHAADAAAAAQBOAAEAMAABAAAAAwADAAAAAQA8AAIAFAAeAAEAAAADAAIAAQFOAVEAAAACAAIBQAFEAAABRgFMAAUAAQAAAAEACAABAAYAAQABAAIAmACiAAYAAAABAAgAAQBYAAIACgAeAAEABAAAAAIA+gABADIAAQAAAAUAAQAEAAAAAgD6AAEApgABAAAABQAEAAAAAQAIAAEAHgACAAoAFAABAAQANgACAPoAAQAEAKoAAgD6AAEAAgAyAKYAAQAAAAEACAABAAYAAQABAAQAUwBYAMcAzQABAAAAAQAIAAEABgAFAAEAAQCYAAEAAAABAAgAAQAGAAwAAQADAOkA6gDrAAQAAAABAAgAAQAsAAIACgAgAAIABgAOAPMAAwEIAOwA8gADAQgA6gABAAQA9AADAQgA7AABAAIA6QDr"
    function Library:GetESPFont()
        if self._ESPFont ~= nil then return self._ESPFont or nil end
        self._ESPFont = false
        local loadAsset = getcustomasset or getsynasset
        if not (loadAsset and writefile and isfile and isfolder and makefolder) then return nil end
        pcall(function()
            local root = (tostring(self.IconFolder or "SkeetUI/icons"):match("^(.-)/[^/]*$")) or "SkeetUI"
            local dir = root .. "/fonts"
            local acc = ""
            for part in string.gmatch(dir, "[^/]+") do
                acc = acc == "" and part or (acc .. "/" .. part)
                if not isfolder(acc) then makefolder(acc) end
            end
            local path = dir .. "/esp.ttf" -- свой файл с таким именем приоритетнее
            if not isfile(path) then
                path = dir .. "/selawik-semilight.ttf" -- [v64]
                if not isfile(path) then writefile(path, B64Decode(self._ESPFontB64)) end
            end
            local id = loadAsset(path)
            if type(id) ~= "string" or id == "" then return end
            local json = dir .. "/espfont.json" -- [v64]
            writefile(json, HttpService:JSONEncode({ name = "ESPFont", faces = { { name = "Regular", weight = 400, style = "normal", assetId = id } } }))
            local fam = loadAsset(json)
            if type(fam) == "string" and fam ~= "" then self._ESPFont = Font.new(fam) end
        end)
        return self._ESPFont or nil
    end
    -- [v72] мелкий пиксельный шрифт (как «Small Fonts» у skeet): метки клавиш [M5] / [-], плюс / минус у слайдеров.
    -- Свой VH Pixel (5px заглавные, нарисован с нуля). Чётко при TextSize 8.
    Library._SmallFontB64 = "''' + px + '''"
    function Library:GetSmallFont()
        if self._SmallFont ~= nil then return self._SmallFont or nil end
        self._SmallFont = false
        local loadAsset = getcustomasset or getsynasset
        if not (loadAsset and writefile and isfile and isfolder and makefolder) then return nil end
        pcall(function()
            local root = (tostring(self.IconFolder or "SkeetUI/icons"):match("^(.-)/[^/]*$")) or "SkeetUI"
            local dir = root .. "/fonts"
            local acc = ""
            for part in string.gmatch(dir, "[^/]+") do
                acc = acc == "" and part or (acc .. "/" .. part)
                if not isfolder(acc) then makefolder(acc) end
            end
            local path = dir .. "/vhpixel-1.ttf"
            if not isfile(path) then writefile(path, B64Decode(self._SmallFontB64)) end
            local id = loadAsset(path)
            if type(id) ~= "string" or id == "" then return end
            local json = dir .. "/vhpixel.json"
            writefile(json, HttpService:JSONEncode({ name = "VHPixel", faces = { { name = "Regular", weight = 400, style = "normal", assetId = id } } }))
            local fam = loadAsset(json)
            if type(fam) == "string" and fam ~= "" then self._SmallFont = Font.new(fam) end
        end)
        return self._SmallFont or nil
    end
    -- [v72] короткие имена для индикаторов слева (как DS / HC / JB у gamesense): свои - Library.ShortNames,
    -- иначе первые буквы двух первых слов (одно слово - две первые буквы)
    Library.ShortNames = Library.ShortNames or {}
    function Library:ShortName(text)
        text = tostring(text or "")
        local s = self.ShortNames[text]
        if s then return s end
        local words = {}
        for w in string.gmatch(text, "[%a%d]+") do words[#words + 1] = w end
        if #words == 0 then return string.upper(string.sub(text, 1, 2)) end
        if #words == 1 then return string.upper(string.sub(words[1], 1, 2)) end
        return string.upper(string.sub(words[1], 1, 1) .. string.sub(words[2], 1, 1))
    end
    function Library:ApplySmallFont(label, size)
        local f = self:GetSmallFont()
        if f and label then pcall(function() label.FontFace = f label.TextSize = size or 8 end) end
        return label
    end
    function Library:ApplyESPFont(label)
        local f = self:GetESPFont()
        if f and label then pcall(function() label.FontFace = f end) end
        return label
    end

    local NL_FONT_B64 = {
        Medium = "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Moky1TMfMzkzUDNcM2gzdDOAM4wzlzOkM68z2DP1NAE0DTQZNCk0OTRFNGI0dDR9NIU0kTSdNKU0rTS5NMc01zVvNYk1mDW9NeI18QABAAAAAgNUHs4vhV8PPPUAAwPoAAAAAN2A0+cAAAAA4T2bF/2S/nYK8AQrAAAABgACAAAAAAAAAlgAXgEEAAABEgBEAasAQQKGABgCPAA4A1QALALhADEA7QBBATgAKAE4AB4CJQAmAjwAMAERACYBQgAlAREARAGAAAkCPAAtAjwAUAI8AC4CPAArAjwAFAI8ADsCPAAxAjwAJwI8AC0CPAAtAREARAERAB8CPAAwAjwANAI8ADABvwAJA4IAOAKOAAACkABfAnkAPALdAF8CLQBfAhAAXwLXADwC7ABfAWIAJgEi/7MCeABfAhgAXwOWAF8DCABfAxEAPAJkAF8DEQA8AnkAXwImADICMwANAuIAWQJnAAADrQAIAmIAAwJHAAACPgAiAUoATQGAAAkBSgAZAjwAIgGy//4BMQAoAj4ALQJsAFMB6gA0AmwANAI8ADQBZQAQAmwANAJ2AFMBEABMARD/xgIvAFMBEABTA7UAUwJ2AFMCYQA0AmwAUwJsADQBqQBTAeQAMQF/ABICdgBOAg4AAAMnAAsCHwAOAg8AAQHbACMBgAAYAicA6gGAACICPAAwAQQAAAESAEQCPABVAjwAIgI8ADoCPAALAicA6gH5ADkCTACRA0AAMQFtAB0CHAAoAjwAMAFCACUDQAAxAfT//QGsADICPAAwAWcAGQFnABUBMQAoAnoAUwKPADcBEQBEANsABQFnACcBfAAfAhwAJwMCAB4DIQAWAyAAGAG/ABkCjgAAAo4AAAKOAAACjgAAAo4AAAKOAAADhv//AnkAPAItAF8CLQBfAi0AXwItAF8BYgAgAWIAJgFi//wBYgAdAt0AHAMIAF8DEQA8AxEAPAMRADwDEQA8AxEAPAI8AEADEQA8AuIAWQLiAFkC4gBZAuIAWQJHAAACZABfAo8AUwI+AC0CPgAtAj4ALQI+AC0CPgAtAj4ALQNwAC0B6gA0AjwANAI8ADQCPAA0AjwANAEQ//cBEABOARD/0gEQ//QCYQA0AnYAUwJhADQCYQA0AmEANAJhADQCYQA0AjwAMAJhADQCdgBOAnYATgJ2AE4CdgBOAg8AAQJsAFMCDwABAo4AAAI+AC0CjgAAAj4ALQKOAAACPgAtAnkAPAHqADQCeQA8AeoANAJ5ADwB6gA0AnkAPAHqADQC3QBfAmwANALdABwCcgA0Ai0AXwI8ADQCLQBfAjwANAItAF8CPAA0Ai0AXwI8ADQCLQBfAjwANALXADwCbAA0AtcAPAJsADQC1wA8AmwANALXADwCbAA0AuwAXwJ2/9QC7AAAAnYABwFi//UBEP/LAWIAFwEQ/+4BYgALARD/4QFiACYBEAAgAWIAJgKEACYCIABMASL/swEQ/8YCeABfAi8AUwIvAFMCGABZARAATgIYAF8BEABCAhgAXwEQAFMCGABfASgAUwIYAAkBEP/2AwgAXwJ2AFMDCABfAnYAUwMIAF8CdgBTAsgAAQMIAF8CdgBTAxEAPAJhADQDEQA8AmEANAMRADwCYQA0A60APAO7ADMCeQBfAakAUwJ5AF8BqQBBAnkAXwGpAD4CJgAyAeQAMQImADIB5AAxAiYAMgHkADECJgAyAeQAMQIzAA0BfwASAjMADQF/ABIC4gBZAnYATgLiAFkCdgBOAuIAWQJ2AE4C4gBZAnYATgLiAFkCdgBOAuIAWQJ2AE4DrQAIAycACwJHAAACDwABAkcAAAI+ACIB2wAjAj4AIgHbACMCPgAiAdsAIwFXAFMBuwAoAbsAKAGDACgBnQAoAMgAKAEzACgA/wAoAcoAKAHOACgCLQBfAtoADQINAF8CgwA7AiQAMAEqAF8BKgAaASL/swP5AAQEDgBfAt4ADQKFAF8CcQAGAuUAXwKNAAACcABfAo8AXwINAF8C5wAKAi0AXwOkAAQCRgApAv4AXwL+AF8ChQBfAsUABAOWAF8C7wBfAv0AOwLmAF8CZQBfAoIAOwIzAA0CcQAGA0oANQJjAAQC7wBfAq8ASgQVAF8EEABfAsEADQNmAF8CagBgAooALAPsAF8CiwAbAjgALAJdADMCPwBUAcEAVAJoAAkCMQAvAxcABwHyACMCfQBUAn0AVAIsAFQCVwABAxQAVAJyAFQCWgAvAmsAVAJoAFQB9gAvAd0ADgIPAAEC9wAvAhIACAJxAFQCWwA8A48AUQOSAFQCfQAOAxMAVAIvAFQB+AApAy4AVAJKABwCMQAvAnUABAHCAFQB9wAvAd0AKgERAE0BEAAVARD/xwNmAAEDhQBUAnYABAIsAFQCDwAB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AAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/87/7P/i/87/xAAAAAAAAAAAAAAAAAAA/8T/zv/YAAAAAAAAAAD/7AAAAAD/sP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADIAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAD/7AAAAAAAAP/2AAAAAP/i/+wAAP/sAAAAAAAAAAAAAAAA/7AAAAAAAAAAAAAAAAD/7P/2//b/7P/YAAAAAAAAAAAAAAAAAAD/zv/2//YAAAAAAAAAAAAAAAAAAP/i//YAAP/EAAD/4v/Y/7oAAAAAAAAACgAUAAAAFAAA/+L/4gAAAAAAAAAAAAAAAP+wAAAAAAAA/7r/7P/O/7D/ugAA/+wAAAAAAAAAAAAU/8T/uv/EAAAAAP/YAAD/2AAAAAD/xP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAD/zgAAAAAAAP/sAAAAAP/E/8QAAP+6AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAP/sAAAAAAAAAAAAAAAAAAAAAP9g//YAAAAAAAAAAAAoAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAP/OAAAAAAAAAAAAAAAAAAD/fgAAAAAAAP/2AAAAAAAAAAD/4v/sAAAAAAAAAAAAAAAAAAAAAAAAAB4AAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAARgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAADwAAAAoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+L/9gAA/+IAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/sP/iAAD/xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEApwADAAgADQAOAA8AIgAkACUAJgAsAC0AMAAxADIANQA2ADcAOAA5ADoAOwBCAEMARgBHAEkATgBPAFAAUQBTAFUAVwBYAFkAWgBrAHsAgACBAIIAgwCEAIUAhgCHAIgAiQCKAIsAkACSAJMAlACVAJYAmACZAJoAmwCcAJ0AngCgAKEAogCjAKQApQCmAKgAqQCqAKsArgCvALAAsgCzALQAtQC2ALgAvQC+AL8AwADBAMIAwwDEAMUAxgDIAMoAzADOAM8A0ADSANMA1ADVANYA1wDYANkA2gDbAOUA6QDrAPUA9wD4APoA/AD9AP4BAAEDAQUBCAEKAQsBDAENAQ4BDwEQAREBEgEUARYBGAEhASIBIwEkASUBJwEpASsBLQEvATEBMgEzATQBNQE2ATgBOgGkAaUBpgGoAakBqgGsAa0BrgG2AbcBwAHBAcYAAgBxAAMAAwAMAAgACAAMAA0ADQAQAA4ADgARAA8ADwAQACIAIgACACQAJAAJACUAJQADACYAJgAEACwALAATAC0ALQAKADAAMAADADEAMQAUADIAMgADADUANQANADYANgAGADcAOAALADkAOQATADoAOgAHADsAOwAPAEIAQgABAEcARwAWAEkASQABAE4ATwABAFMAUwASAFUAVQAOAFcAWAAFAFkAWQAZAFoAWgAFAGsAawAXAHsAewAYAIAAhQACAIYAhgAEAIcAhwAJAIgAiwAEAJAAkAADAJIAlgADAJgAmAADAJkAnAAGAJ0AnQAHAJ4AngAUAKAApQABAK4ArwAIAL0AvQAFAL8AvwAFAMAAwAACAMEAwQABAMIAwgACAMMAwwABAMQAxAACAMUAxQABAMYAxgAJAMgAyAAJAMoAygAJAMwAzAAJAM4AzgADAM8AzwAVANAA0AADANIA0gAEANQA1AAEANYA1gAEANgA2AAEANoA2gAEAOUA5QABAOkA6QAIAOsA6wAIAPUA9QATAPcA9wAZAPgA+AAKAPoA+gAKAPwA/AAKAP0A/QAVAP4A/gAKAQABAAAKAQMBAwABAQUBBQABAQgBCAABAQoBCgABAQsBCwADAQ0BDQADAQ8BDwADAREBEQAEARQBFAASARYBFgASARgBGAASASEBIQANASIBIgAOASMBIwANASQBJAAOASUBJQAGAScBJwAGASkBKQAGASsBKwAGAS0BLQAGAS8BLwAGATEBMQALATIBMgAFATMBMwAHATQBNAAFATUBNQAHATYBNgAPATgBOAAPAToBOgAPAaQBpgARAagBqQAMAaoBqgAQAawBrQAMAa4BrgAQAbYBtgAXAbcBtwAYAcABwAANAcEBwQAOAcYBxgAWAAIAjgADAAMAEwAIAAgAEwAKAAoAFQANAA0ADQAOAA4AEgAPAA8ADQAiACIABQAkACQAAgAoACgAAgAwADAAAgAyADIAAgA1ADUADAA2ADYABgA3ADgACgA6ADoACQA7ADsAEQA+AD4AFQBCAEIABABDAEMACABEAEYAAQBHAEcACwBIAEgADgBJAEkACABMAE0ACABOAE8AAwBQAFAAAQBRAFEAAwBSAFIAAQBTAFMAAwBUAFQADwBVAFUAEABWAFYAAwBXAFoABwBbAFsAFABeAF4AFQBrAGsAFwB7AHsAGACAAIUABQCGAIYAFgCHAIcAAgCSAJYAAgCYAJgAAgCZAJwABgCdAJ0ACQCgAKAAAQChAKYABACnAKsAAQCyALYAAQC4ALgAAQC5ALwAAwC9AL0ABwC+AL4ACAC/AL8ABwDAAMAABQDBAMEABADCAMIABQDDAMMABADEAMQABQDFAMUABADGAMYAAgDHAMcAAQDIAMgAAgDJAMkAAQDKAMoAAgDLAMsAAQDMAMwAAgDNAM0AAQDPAM8AAQDRANEAAQDTANMAAQDVANUAAQDXANcAAQDZANkAAQDbANsAAQDcANwAAgDdAN0ADgDeAN4AAgDfAN8ADgDgAOAAAgDhAOEADgDiAOIAAgDjAOMADgDlAOUACAD2APYACAD3APcAAwD5APkACAD7APsACAD9AP0ACAD/AP8ACAEDAQMAAwEFAQUAAwEKAQoAAwELAQsAAgEMAQwAAQENAQ0AAgEOAQ4AAQEPAQ8AAgEQARAAAQERAREAAgESARIAAQEUARQAAwEWARYAAwEaARoADwEeAR4ADwEhASEADAEiASIAEAEjASMADAEkASQAEAElASUABgEmASYAAwEnAScABgEoASgAAwEpASkABgEqASoAAwErASsABgEsASwAAwEtAS0ABgEuAS4AAwEvAS8ABgEwATAAAwExATEACgEyATIABwEzATMACQE0ATQABwE1ATUACQE2ATYAEQE3ATcAFAE4ATgAEQE5ATkAFAE6AToAEQE7ATsAFAGkAaYAEgGpAakAEwGqAaoADQGtAa0AEwGuAa4ADQGyAbIADQG2AbYAFwG3AbcAGAHAAcAADAHBAcEAEAHGAcoACwACAAgAAQAIAAIAFgAEAAAAJgAqAAEAAwAAAAAAAAABAAYAAwAIAagBqQGsAa0AAgAAAAIACQADAAMAAgAIAAgAAgANAA0AAQAPAA8AAQGpAakAAgGqAaoAAQGtAa0AAgGuAa4AAQGyAbIAAQABABQABAAAAAUAIgBkAHoAlACeAAEABQAbAUcBdQGVAZYAEAFH/+sBUP/rAVr/+QFm/+sBaP/5AWn/+QFr//kBbv/rAXkAAAGCAAABhQAAAYgAAAGL//kBlAAAAZcAAAG+AAAABQANAAAADwAAAaoAAAGuAAABsgAAAAYBR//sAVD/7AFa//YBZv/sAWn/9gFu/+wAAgFNACgBmwAUAAkBRwAAAVAAAAFSAAABZgAAAWcAAAFuAAABlQAAAZoAAAGeAAAAAgtWAAQAAAveDdQAJQAnAAAAAAAAAAD/9v/sAAD/7AAAAAAAAP/2//b/2P/Z//YAAP/iAAAAAAAAAAAAAP/9AAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAAAAAAAAAAAAAP/8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9v/sAAD/8f/2AAAAAAAA/+z/7P/YAAD/2AAA//b/9gAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAFAAAAAAAAAAA//EAAP/xAAD/4gAA/+IAFAAAAB4AFAAAABkAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAGQAAAAAAAAAPAAAAAAAAAAA//YAAAAA/+wAAAAA//YAAP/2AAAAAAAA/+wAAP/2AAAAAAAAAAD/9gAU/+wAAP/2/+wAAAAAAAD/2AAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAHgAAAAAAAAAA/+cAAP/2AAAAAAAA/+wAHgAeACgAHgAAAB4AAAAAAAAAAAAAAAAAAAAAAAD/9gAAAFoAAAAAAAAARgAAAAAAAAAA/+wAAAAA/+wAAAAA//YAAAAAAAD/9v/2/+wAAAAAAAAAAAAAAAD/9gAA//EAAAAAAAAAAAAeAAD/8QAAAAAAAAAA//YAAAAAAAD/9gAA/87/nwAA/8H/4gAAAAD/7AAA/4gAAAAA/+z/ugAA/5z/qQAy/87/7AAU/9gAAP/2/87/7AAA/+z/4v/iAAD/2P/i/84AAAAAAAAAAAAA//b/zv/2/+IAAAAAAAAAAAAA/+wAAAAAAAD/2AAA/+L/7AAA/84AAAAUAAAAAAAAAAAAAAAoAAAAAAAAAAAAAAAA/+IAAAAAAAAAAAAAAAAAAP/2AAD/7AAA/7oAAP/E//b/xP/s/9gAAP/TAAAAAAAAAAAAAP+wAAAAAP/2AAAAAP/iAAD/9v/sAAAAAAAA/+wAAAAAAAAAAAAA/9j/ugAUAAAAAAAAAAAAFAAe/7oAFAAUAAAAAAAU/8T/4gAe/84AAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAeAAAAAAAAAAAAAAAA//YAAAAA/8QAAP/iAAD/uv/o/+IAAP/sAAAAAAAAAAAAAP+6/+wAAAAAAAD/9v/YAAD/3QAAADIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAA/+wAAAAA/+wAAAAAAAD/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2P/2//YAAAAAAAAAAAAA/+IAAAAAAAD/2AAA/+L/7AAA/+L/7AAeAAAAAAAAAAAAAAAoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAA/+IAAP/sAAD/xP/sAAD/9v/sAAAAAAAAAAAAAP+mAAAAAAAAAAAAAP/EAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/7AAAP/YAAD/zv/s/8QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAADwAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAP/2AAD/9gAAAAAAAP/sAAD/2P/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//b/2AAA//YAAAAAAAAAAAAA/+IAAAAAAAD/zgAAAAAAAAAA/+L/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAD/7AAAAAAAAP/2AAD/4v/2AAAAAP/2AAAAAAAAAAAAAAAAAAD/+QAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAD/4gAA/9j/2AAA/9j/9gAAAAD/9v/2/7oAFAAA/+L/zv/t/+f/5wAA/+L/2AAU/+wAAP/iAAD/4gAAAAD/3QAAAAD/7P/s/9gAAAAAAAAAAP/O/7r/xAAAAAD/7AAAAAD/7P/Y/7oAFAAA/87/xP/Y/87/2AAAAAD/2AAA/+wAAAAA/8T/4gAAAAD/3gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAP/2AAD/2P/bAAAAAP/2AAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/4gAAAGQAAAAAAAAAPAAAAAAAAAAAAAAAAAAAAAAAAAAA/+IAAP/sAAD/zv/s/+wAAP/sAAAAAAAAAAAAAP+6AAAAAAAAAAAAAP/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+f/zv/s//YAAAAAAAAAAAAA/84AAP/sAAD/fgAA/8T/xAAA/9j/9gAAAAAAAP/2/+z/9gAAAAD/9gAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAA//EAAAAAAAAAAAAAAAAAAAAAAAD/7gAAAAAAAAAAAAAAAAAAAAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/iAAD/2AAAAAAAAP/OAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAACgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//b/4gAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAA/+wAAAAAAAD/xP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/9gAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/5//YAAD/8f/iAAAAAAAA/93/3f/iAAD/2AAA/+L/6gAA//EAAP/2AAD/6//2AAAAAAAA//YAAP/2AAAAAAAA//YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7P/iAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB4AAAAAAAAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFAAAAAAAAAAAAAAAAAAeAAAAAAAeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANAAIAFgADAAMAAAAIAAkAAQANAA8AAwA8ADwABgBcAFwABwBrAGsACAB7AHsACQFGAUoACgFOAVIADwFUAVsAFAFeAV4AHAFiAWIAHQFkAWoAHgFtAW4AJQFwAXIAJwF0AZgAKgGaAaYATwGoAaoAXAGsAa4AXwG2AbcAYgG8AbwAZAG+Ab8AZQACAFMAAwADAAoACAAIAAoACQAJABgADQANABAADgAOABIADwAPABAAPAA8ABgAXABcABgAawBrAB0AewB7AB4BRgFGAAwBRwFHABkBSAFIABUBSQFJAA0BSgFKACABTgFPAA8BUAFQABkBUQFRAAQBUgFSAAcBVAFUAAsBVQFVAB8BVgFWABsBVwFXABUBWAFYAAUBWQFZAAwBWgFaAAQBWwFbABsBXgFeAAQBYgFiAAIBZAFkABoBZQFlAA0BZgFmABUBZwFnAAcBaAFoACEBaQFpAAQBagFqAAUBbQFtAAUBbgFuAA8BcAFwAA8BcQFyAAIBdAF0ABcBdgF2ABQBdwF3AA4BeAF4AAMBegF6AAYBewF7ABQBfAF9AAEBfgF+AAYBfwGBAAEBgwGDAAEBhQGFABEBhgGGAA4BhwGHAAgBiQGJAAYBigGKAAMBiwGMAAEBjQGNAAMBjgGOAAkBjwGPAAEBkAGQAAkBkwGTAAEBlQGVABwBlgGWAA4BlwGXABEBmAGYACIBmgGaACQBmwGbACMBnAGdAAkBngGeABwBnwGfAAYBoAGgAAgBoQGhAAEBogGiABYBowGjABMBpAGmABIBqAGpAAoBqgGqABABrAGtAAoBrgGuABABtgG2AB0BtwG3AB4BvAG8AAwBvwG/AAEAAgBUAAMAAwAXAAgACAAXAAoACgAZAA0ADQAQAA4ADgAWAA8ADwAQABsAHAAaAD4APgAZAF4AXgAZAGsAawAbAHsAewAcAUcBRwANAUkBSQAYAUoBSgAeAU0BTQAhAU4BTgATAVABUAANAVIBUgAOAVQBVAAMAVgBWAASAVoBWgAFAVsBWwAIAV8BXwATAWIBYgAYAWUBZQAYAWYBZgANAWcBZwAOAWgBaAAfAWkBaQAFAWsBawAJAW4BbgANAXEBcQAIAXMBcwAgAXQBdAADAXUBdQAiAXYBdwABAXgBeAAEAXkBeQAGAXoBegAHAXsBewAKAXwBfgABAX8BfwAVAYABgQABAYIBggAGAYMBhAABAYUBhQAGAYYBhgALAYcBhwARAYgBiAAGAYkBiQAHAYoBigABAYsBiwAPAYwBjQABAY4BjgALAY8BkAABAZEBkQAKAZIBkgABAZMBkwAkAZQBlAAGAZUBlQAUAZYBlgABAZcBlwAGAZgBmAAjAZoBmgAmAZsBmwAlAZwBnAAVAZ0BnQABAZ4BngAUAZ8BnwABAaABoAARAaEBoQABAaMBowACAaQBpgAWAagBqAAdAakBqQAXAaoBqgAQAawBrAAdAa0BrQAXAa4BrgAQAbIBsgAQAbYBtgAbAbcBtwAcAb4BvgAGAb8BvwABAAAAAQAAAAoANgBEAAVERkxUACBjeXJsACBkZXYyACBncmVrACBsYXRuACAABAAAAAD//wABAAAAAWxpZ2EACAAAAAEAAAABAAQABAAIAAEACAABADYAAQAIAAUADAAUABwAIgAoAckAAwBHAEoBygADAEcATQHGAAIARwHHAAIASgHIAAIATQABAAEARwABAAEACAADAAAAFAADAAAALAACd2dodAEEAAB3ZHRoAQUAAWl0YWwBEwACAAYAEgAeAAEAAAAAAQoB9AAAAAEAAQACARIAZAAAAAMAAgACARQAAAAAAAEAAAAA",
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

    -- AMBIENCE: мульти-выбор (Multi dropdown); не закрывается после выбора.
    -- [v48] skeet: выбранные пункты - акцентом и жирным, без галочек
    local function OpenMultiList(anchor, values, isOn, onToggle)
        local n = #values
        local w = math.max(anchor.AbsoluteSize.X, 120)
        local h = math.clamp(n * LIST_H + 4, LIST_H + 4, 12 * LIST_H + 4)
        OpenPopup(anchor, w, h, function(frame)
            local scroll = ListScroll(frame)
            for i, v in ipairs(values) do
                local b, lbl = ListRow(scroll, i, v, false)
                local function paint()
                    local on = isOn(v)
                    lbl.TextColor3 = on and Scheme.AccentColor or Scheme.FontColor
                    lbl.FontFace = F(on and W_BOLD or W_REG)
                end
                paint()
                b.MouseButton1Click:Connect(function()
                    Safe(onToggle, v)
                    paint()
                end)
            end
        end, true)
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
    -- [v48] у skeet нет мягких теней: окно, popup и плашки без них
    Shadow = function(parent, radius) return nil end
    -- ФИКС «взрыва»: тень-ребёнок у рамки с AutomaticSize/UIListLayout/UIPadding
    -- участвует в раскладке и раздувает рамку. Для таких рамок тень живёт рядом
    -- (у того же родителя) и просто повторяет её положение и размер.
    local function FollowShadow(target, radius)
        local img = Shadow(target.Parent, radius) -- [v48] теней нет -> nil
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
    -- [v48] метрики skeet (px при масштабе 1; сняты с видео 720p и пересчитаны x1.5)
    --   чекбокс 8x8 на x=20, подписи и контролы с x=38, строка чекбокса 18,
    --   слайдер: подпись 15 + полоса 6 + значение под концом заливки, поле dropdown 20
    --------------------------------------------------------
    local ROW_H = 38 -- (как было: размеры списка биндов ниже считаются от него)
    -- [v49] замер со скриншота 1:1 (от внутреннего края групбокса): чекбокс 6x6 + рамка на x=21,
    -- подписи и контролы с x=41, ширина контрола 157 + рамка, строка чекбокса 18,
    -- слайдер 5 + рамка (7), поле dropdown 18 + рамка (20)
    local SK = {
        -- [v50] по видео (оригинал, x1.5): чекбокс на 19, подписи на 37, ползунок тоньше - 3 + рамка
        -- [v54] по MenuControls.h: чекбокс SameLine(19), слайдер/комбо SameLine(42) шириной 159/158, цвет SameLine(219)
        X_BOX = 19, X_TXT = 42, R_PAD = 22, CTRL_W = 158,
        CHK_H = 19, LBL_H = 13, -- [v74] шаг галочек у skeet 19px (замер 104/123/142/161), было 18
        FIELD_H = 16, BTN_H = 23, BAR_H = 5, -- [v60] кнопка 23 + рамка = 25 (скрин оригинала) -- [v57] слайдер 5 + рамка (скрин 1:1)
        TITLE = Color3.fromRGB(215, 215, 215),
    }
    SK.CtrlSize = function(h) return UDim2.fromOffset(SK.CTRL_W, h) end

    -- квадрат-чекбокс: чёрная рамка + вертикальный градиент (как у skeet)
    SK.Box = function(parent, x, y, size)
        local box = Create("Frame", {
            Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(size or 6, size or 6),
            BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = parent,
        })
        Stroke(box, "InputBorder")
        local grad = Create("UIGradient", { Rotation = 90, Parent = box })
        return box, grad
    end
    -- [v55] +d к каждому каналу (hover у skeet-исходника: все плашки светлее на 10)
    SK.Shift = function(c, d)
        return Color3.fromRGB(math.min(255, c.R * 255 + d), math.min(255, c.G * 255 + d), math.min(255, c.B * 255 + d))
    end
    SK.PaintBox = function(grad, on, hov)
        -- [v49] замер: вкл 135,181,53 -> 97,128,42; выкл 71 -> 56
        local c = on and Scheme.AccentColor or Scheme.OffTrack
        local b = c:Lerp(Color3.new(0, 0, 0), on and 0.2 or 0.21) -- [v57] вкл: низ x0.8 (скрин 1:1)
        if hov and not on then c, b = SK.Shift(c, 10), SK.Shift(b, 10) end -- [v55] imgui_widgets.cpp Checkbox: 76/51 -> 86/61
        grad.Color = ColorSequence.new(c, b)
    end
    -- плашка с градиентом сверху вниз (поле dropdown, кнопка)
    SK.Field = function(class, parent, pos, size)
        local props = { Position = pos, Size = size, BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = parent }
        local f = class == "TextButton" and Button(props) or Create(class, props)
        f.BackgroundTransparency = 0
        f.BackgroundColor3 = WHITE
        Stroke(f, "InputBorder")
        -- [v60] ФИКС «чёрный name»: UIGradient на TextBox красит и сам текст (31/255 -> почти чёрный).
        -- У полей ввода градиента нет - ровный цвет поля.
        local grad = class ~= "TextBox" and Create("UIGradient", { Rotation = 90, Parent = f }) or nil
        local hov = false -- [v55]
        local function paint()
            local c = Scheme.InputColor
            local b = c:Lerp(Color3.new(1, 1, 1), 0.023) -- [v49] 31 -> 36
            if hov then c, b = SK.Shift(c, 10), SK.Shift(b, 10) end -- [v55] Combo hover 41 -> 46
            if grad then grad.Color = ColorSequence.new(c, b) else f.BackgroundColor3 = c end -- [v60]
        end
        Library:AddRefresh(paint)
        return f, grad, function(v) hov = v == true paint() end -- [v55] третье значение: hover
    end
    -- треугольник «v» справа в поле: три полоски 5/3/1px
    SK.Caret = function(parent)
        local c = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 1), Size = UDim2.fromOffset(5, 3),
            BackgroundTransparency = 1, Parent = parent,
        })
        for i = 0, 2 do
            local bar = Create("Frame", { Position = UDim2.fromOffset(i, i), Size = UDim2.fromOffset(5 - i * 2, 1), BorderSizePixel = 0, Parent = c })
            Theme(bar, { BackgroundColor3 = "ValueColor" })
        end
        return c
    end
    -- правая часть строки (цвет, «...», [клавиша]) - растёт влево
    SK.Right = function(row, y)
        local box = Create("Frame", {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -SK.R_PAD, 0, y or 0),
            Size = UDim2.fromOffset(0, SK.CHK_H), AutomaticSize = AX, BackgroundTransparency = 1, Parent = row,
        })
        List(box, Enum.FillDirection.Horizontal, 5, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
        return box
    end
    SK.Label = function(row, text, y, h)
        return Text({
            Text = tostring(text or ""), Position = UDim2.fromOffset(SK.X_TXT, y or 0),
            Size = UDim2.new(1, -SK.X_TXT - SK.R_PAD, 0, h or SK.CHK_H), ClipsDescendants = true, Parent = row,
        })
    end
    -- подпись не заезжает под правые аддоны
    SK.Fit = function(label, right)
        local function fit()
            local sc = Library._UIScale and Library._UIScale.Scale or 1
            local w = math.floor(right.AbsoluteSize.X / math.max(sc, 0.01) + 0.5)
            label.Size = UDim2.new(1, -SK.X_TXT - SK.R_PAD - w - 6, 0, label.Size.Y.Offset)
        end
        right:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
        fit()
    end

    -- [клавиша] - серый текст в скобках (как у skeet справа в строке)
    local function ValueBox(parent, order, clickable)
        local props = { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(0, SK.CHK_H), AutomaticSize = AX, LayoutOrder = order, Parent = parent }
        local box = clickable and Button(props) or Create("Frame", props)
        local label = Text({
            Text = "", TextSize = 11, ColorKey = "DimColor", Size = UDim2.fromScale(0, 1), AutomaticSize = AX,
            TextXAlignment = Enum.TextXAlignment.Center, Parent = box,
        })
        Library:ApplySmallFont(label) -- [v72] [M5] / [-] мелким пиксельным, как у skeet
        return box, label
    end

    --------------------------------------------------------
    -- color picker: свотч 18x8 с чёрной рамкой; popup - квадрат SV, полоса hue, hex
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

        -- [v49] свотч 15x7 + рамка, сверху светлее (замер: 239 -> 178 у белого)
        local swatch = Button({ BackgroundTransparency = 0, Size = UDim2.fromOffset(15, 7), LayoutOrder = order, Parent = parent })
        Stroke(swatch, "InputBorder")
        local shade = Create("UIGradient", { Rotation = 90, Parent = swatch })
        shade.Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 190, 190))

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

        -- [v74] как у skeet (замер по скрину): без заголовка и поля hex, 135x120: квадрат 112x112 и полоса оттенка 11px
        -- (сверху красный -> пурпурный -> синий ... -> красный снизу); окно - слева по свотчу, под ним.
        -- Копировать / вставить цвет - правый клик по свотчу (как у skeet).
        swatch.MouseButton1Click:Connect(function()
            OpenPopup(swatch, 135, 120, function(frame, _, popup)
                frame.BackgroundColor3 = Color3.fromRGB(44, 44, 44)
                local sv = Button({ BackgroundTransparency = 0, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(112, 112), Parent = frame })
                Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = sv })
                local white = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = sv })
                Create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
                local black = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, Parent = sv })
                Create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
                local svCursor = Create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, ZIndex = 3, Parent = sv,
                })
                Create("UIStroke", { Color = WHITE, Thickness = 1, Parent = svCursor })

                local hue = Button({ BackgroundTransparency = 0, BackgroundColor3 = WHITE, Position = UDim2.fromOffset(120, 4), Size = UDim2.fromOffset(11, 112), Parent = frame })
                Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = hue })
                Create("UIGradient", { Rotation = 270, Color = HUE_SEQ, Parent = hue }) -- снизу вверх: красный внизу и вверху
                local hueCursor = Create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(205, 205, 205),
                    BorderSizePixel = 0, ZIndex = 3, Parent = hue,
                })

                local function sync()
                    sv.BackgroundColor3 = Color3.fromHSV(CP.Hue, 1, 1)
                    svCursor.Position = UDim2.fromScale(CP.Sat, 1 - CP.Vib)
                    hueCursor.Position = UDim2.new(0.5, 0, math.clamp(1 - CP.Hue, 0, 1), 0) -- [v74] оттенок снизу вверх
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
                        CP:SetHSV(math.clamp(1 - y, 0, 0.999), CP.Sat, CP.Vib) -- [v74]
                    end)
                    ActiveDrag.Popup = popup
                end)
                return function() CP._Sync = nil end
            end, true)
        end)
        swatch.MouseButton2Click:Connect(function() -- [v74] Copy / Paste (буфер свой + системный, hex)
            OpenList(swatch, { "Copy", "Paste" }, nil, function(v)
                if v == "Copy" then
                    Library._ColorClip = CP.Value
                    local clip = setclipboard or toclipboard
                    if clip then pcall(clip, "#" .. string.upper(CP.Value:ToHex())) end
                elseif v == "Paste" then
                    local c = Library._ColorClip
                    local get = getclipboard or fromclipboard
                    if get then
                        local ok, t = pcall(get)
                        local h = ok and type(t) == "string" and string.match(t, "^%s*#?(%x%x%x%x%x%x)%s*$")
                        if h then c = Color3.fromHex(h) end
                    end
                    if c then CP:SetValueRGB(c) end
                end
            end, true)
        end)

        CP:Display()
        if idx then Options[idx] = CP end
        return CP
    end

    --------------------------------------------------------
    -- key picker: «[F]» справа в строке, клик -> «[...]» -> следующая клавиша
    --------------------------------------------------------
    local function NewKeyPicker(idx, info, parent, order)
        info = info or {}
        local KP = {
            Type = "KeyPicker", Value = info.Default or "None", Mode = info.Mode or "Toggle",
            Changed = {}, Callback = info.ChangedCallback or info.Callback, Text = info.Text,
        }
        local btn, label = ValueBox(parent, order, true)

        function KP:Display() label.Text = "[" .. (self._Picking and "..." or (self.Value == "None" and "-" or tostring(self.Value))) .. "]" end
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
    -- БИНДЫ: ПКМ по любому чекбоксу -> клавиша и режим Toggle / Hold / Always.
    -- Library.Binds[idx] = { Key = "F", Mode = "Toggle" }; сохраняются в конфиг (SaveManager).
    -- [v48] в строке справа серым «[F]», как у skeet
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
        local map = { LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL",
            LeftAlt = "ALT", RightAlt = "RALT", CapsLock = "CAPS", MB2 = "M2", MB3 = "M3" }
        return map[k] or string.upper(tostring(k))
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
        -- [v72] как у skeet: у важных функций (BindIcon) метка видна всегда - «[-]» без клавиши, клик - назначить
        if (b or T.BindIcon) and not mark and T.Right then
            local mb = Button({ Size = UDim2.fromOffset(0, SK.CHK_H), AutomaticSize = AX, LayoutOrder = 99, Parent = T.Right })
            mark = Text({ Text = "", TextSize = 11, ColorKey = "DimColor", Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = mb })
            Library:ApplySmallFont(mark)
            mb.MouseButton1Click:Connect(function() if Library._OpenBindPopup then Library._OpenBindPopup(mb, idx, T.Text or idx) end end)
            BindMarks[idx] = mark
        end
        if mark then
            mark.Parent.Visible = b ~= nil or T.BindIcon ~= nil
            mark.Text = b and ("[" .. ShortKey(b.Key) .. "]") or "[-]"
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

    -- окно настройки бинда (ПКМ по строке): у skeet это маленький список режимов у клавиши.
    -- Здесь: заголовок, поле клавиши, три режима списком (выбранный - акцентом).
    local function OpenBindPopup(anchor, idx, title)
        local cur = Library.Binds[idx]
        local key, mode = cur and cur.Key or "None", cur and cur.Mode or "Toggle"
        OpenPopup(anchor, 150, 24 + 24 + #BIND_MODES * LIST_H + 8, function(frame)
            Text({ Text = tostring(title or idx), TextSize = 12, FontFace = F(W_BOLD), Position = UDim2.fromOffset(8, 3),
                Size = UDim2.new(1, -16, 0, 18), ClipsDescendants = true, Parent = frame })
            -- клавиша: клик -> "..." -> следующая клавиша; Backspace - убрать, Esc - отмена
            local kbtn = SK.Field("TextButton", frame, UDim2.fromOffset(8, 24), UDim2.new(1, -16, 0, 18))
            local klabel = Text({ Text = "", TextSize = 12, ColorKey = "ValueColor", Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -14, 1, 0), Parent = kbtn })
            local function showKey() klabel.Text = "Key: " .. (key == "None" and "-" or ShortKey(key)) end
            showKey()
            local listening
            kbtn.MouseButton1Click:Connect(function()
                if listening then return end
                Library._Binding = true
                klabel.Text = "Key: ..."
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
            -- режимы списком, как пункты dropdown
            local holder = Create("Frame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, #BIND_MODES * LIST_H), BackgroundTransparency = 1, Parent = frame })
            List(holder, nil, 0)
            local btns = {}
            local function paint()
                for m, b in pairs(btns) do
                    b.Label.TextColor3 = (m == mode) and Scheme.AccentColor or Scheme.FontColor
                    b.Label.FontFace = F((m == mode) and W_BOLD or W_REG)
                end
            end
            for i, m in ipairs(BIND_MODES) do
                local b, l = ListRow(holder, i, m, false)
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
        end, true)
    end
    Library._OpenBindPopup = OpenBindPopup -- [v72] метка [-] справа от галочки открывает то же окно

    local DetachedGroup, OpenSettings, DotsButton -- AMBIENCE: определены ниже, после Group
    local function AddonMixin(obj)
        -- AMBIENCE: «...» справа в строке, открывает мини-панель доп. настроек.
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
    -- groupbox: строки разной высоты, без разделителей (как у skeet)
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
        self.Rows += 1
        self.Height = (self.Height or 0) + height
        self.AfterDivider = false
        AttachTooltip(row, tooltip)
        table.insert(self.Page.Rows, { Row = row, Group = self, Text = string.lower(tostring(searchText or "")) })
        return row
    end

    -- чекбокс: [■] подпись .......... [цвет] [...] [F]
    function Group:AddCheckbox(idx, info)
        info = info or {}
        local row = self:_Row(SK.CHK_H, info.Tooltip, info.Text, true)
        local _, grad = SK.Box(row, SK.X_BOX, 6)
        local label = SK.Label(row, info.Text or idx)
        local right = SK.Right(row)
        SK.Fit(label, right)

        local T = {
            Type = "Toggle", Value = info.Default == true, Changed = {}, Callback = info.Callback,
            Text = info.Text, Row = row, Right = right, Addons = {}, BindIcon = info.BindIcon,
        }
        local hovered = false
        function T:Display(instant)
            SK.PaintBox(grad, self.Value, hovered) -- [v55]
            label.TextColor3 = hovered and Color3.fromRGB(235, 235, 235) or Scheme.FontColor
        end
        function T:OnChanged(fn) table.insert(self.Changed, fn) end
        function T:SetValue(v)
            self.Value = v == true
            self:Display()
            Fire(self)
        end
        AddonMixin(T)
        row.MouseEnter:Connect(function() hovered = true T:Display(true) end)
        row.MouseLeave:Connect(function() hovered = false T:Display(true) end)
        row.MouseButton1Click:Connect(function() T:SetValue(not T.Value) end)
        -- БИНДЫ: ПКМ по строке -> клавиша и режим (кроме служебных переключателей меню)
        if idx and not info.NoBind then
            row.MouseButton2Click:Connect(function() OpenBindPopup(right, idx, info.Text or idx) end)
        end
        Library:AddRefresh(function() T:Display(true) end)

        if idx then Toggles[idx] = T end
        if idx and info.BindIcon then Library:SetBind(idx, nil) end -- [v72] [-] у важных функций сразу
        return T
    end
    Group.AddToggle = Group.AddCheckbox

    -- слайдер skeet: подпись сверху, тонкая полоса, значение жирным под концом заливки,
    -- при наведении по краям «-» и «+» (клик - шаг на 1 единицу округления)
    function Group:AddSlider(idx, info)
        info = info or {}
        local hasText = info.Text ~= nil and info.Text ~= ""
        local top = hasText and SK.LBL_H + 1 or 3
        local row = self:_Row(top + SK.BAR_H + 11, info.Tooltip, info.Text, false) -- [v57] шаг слайдеров 30 (скрин 1:1)
        if hasText then SK.Label(row, info.Text, 0, SK.LBL_H) end
        local right = SK.Right(row, -1)
        right.Size = UDim2.fromOffset(0, SK.LBL_H)

        local S = {
            Type = "Slider", Min = info.Min or 0, Max = info.Max or 100, Rounding = info.Rounding or 0,
            Suffix = info.Suffix or "", Changed = {}, Callback = info.Callback, Row = row, Right = right, Addons = {},
        }
        S.Value = math.clamp(Round(info.Default or S.Min, S.Rounding), S.Min, S.Max)

        local hit = Button({ Position = UDim2.fromOffset(SK.X_TXT, top - 1), Size = SK.CtrlSize(SK.BAR_H + 8), Parent = row }) -- [v57] рамка полосы на 13px ниже верха букв подписи
        local bar = Create("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, SK.BAR_H), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = hit })
        Stroke(bar, "InputBorder")
        local barGrad = Create("UIGradient", { Rotation = 90, Parent = bar })
        local fill = Create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = bar })
        local fillGrad = Create("UIGradient", { Rotation = 90, Parent = fill })
        local valueLabel = Text({
            Text = "", TextSize = 10, FontFace = F(W_BOLD), TextColor3 = Color3.fromRGB(213, 213, 213), ColorKey = false, TextXAlignment = Enum.TextXAlignment.Center, -- [v57] 213
            AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(0, 10), AutomaticSize = AX, ZIndex = 2,
            TextStrokeTransparency = 0.15, Parent = hit,
        })
        -- [v72] как у skeet: «-» и «+» видны всегда, мелкие серые, по центру полосы
        local minus = Text({ Text = "-", TextSize = 10, ColorKey = false, TextColor3 = Color3.fromRGB(110, 110, 110),
            TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, SK.X_TXT - 8, 0, top + 1), Size = UDim2.fromOffset(6, 8), Parent = row })
        local plus = Text({ Text = "+", TextSize = 10, ColorKey = false, TextColor3 = Color3.fromRGB(110, 110, 110),
            TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, SK.X_TXT + SK.CTRL_W + 2, 0, top + 1), Size = UDim2.fromOffset(6, 8), Parent = row })
        Library:ApplySmallFont(minus) Library:ApplySmallFont(plus)
        AddonMixin(S)

        local function fmt(v)
            local s = S.Rounding > 0 and string.format("%." .. S.Rounding .. "f", v) or tostring(math.floor(v + 0.5))
            return s .. S.Suffix
        end
        function S:Display()
            local range = self.Max - self.Min
            local a = range ~= 0 and (self.Value - self.Min) / range or 0
            fill.Size = UDim2.fromScale(a, 1)
            valueLabel.Text = fmt(self.Value)
            -- значение под концом заливки; у нуля прижато к левому краю
            valueLabel.AnchorPoint = Vector2.new(a <= 0.02 and 0 or 0.5, 0)
            -- [v49] значение наезжает на низ полосы (как на скрине «50%»)
            valueLabel.Position = UDim2.new(a, a <= 0.02 and -2 or 0, 0, 4) -- [v57] буквы с 3-й строки полосы, низ на 3px ниже рамки (скрин 1:1)
            local c, t = Scheme.AccentColor, Scheme.TrackColor
            fillGrad.Color = ColorSequence.new(c, c:Lerp(Color3.new(0, 0, 0), 0.33)) -- [v57] низ x0.67 (скрин 1:1: яркость 164 -> 110)
            local tb = t:Lerp(Color3.new(1, 1, 1), 0.074) -- [v57] 52 -> 67
            if S._Hov then t, tb = SK.Shift(t, 10), SK.Shift(tb, 10) end -- [v55] SliderScalar hover 52/68 -> 62/78
            barGrad.Color = ColorSequence.new(t, tb)
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
        local step = 10 ^ -(S.Rounding or 0)
        local function nudge(dir) S:SetValue(S.Value + dir * step) end
        for _, it in ipairs({ { minus, -1 }, { plus, 1 } }) do
            local b = Button({ Position = UDim2.fromOffset(-3, -4), Size = UDim2.new(1, 6, 1, 8), Parent = it[1] })
            b.MouseButton1Click:Connect(function() nudge(it[2]) end)
            b.MouseEnter:Connect(function() it[1].TextColor3 = Color3.fromRGB(215, 215, 215) end) -- [v72]
            b.MouseLeave:Connect(function() it[1].TextColor3 = Color3.fromRGB(110, 110, 110) end)
        end
        hit.MouseEnter:Connect(function() S._Hov = true S:Display() end) -- [v55]
        hit.MouseLeave:Connect(function() S._Hov = false S:Display() end) -- [v55]
        Library:AddRefresh(function() S:Display() end)

        S:Display()
        if idx then Options[idx] = S end
        return S
    end

    -- подпись (с аддонами справа: цвет, клавиша)
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
                Text = text, ColorKey = "SubColor", TextWrapped = true,
                Position = UDim2.fromOffset(SK.X_TXT, 0), Size = UDim2.new(1, -SK.X_TXT - SK.R_PAD, 0, 0), AutomaticSize = AY, Parent = row,
            })
            Pad(label, 0, 0, 2, 3)
            self.Height = (self.Height or 0) + 32 -- оценка для popup настроек
        else
            row = self:_Row(SK.CHK_H, nil, text, false)
            label = SK.Label(row, text)
        end
        L.Row = row
        L.Right = SK.Right(row)
        if not wrap then SK.Fit(label, L.Right) end
        function L:SetText(t) label.Text = tostring(t) end
        AddonMixin(L)
        return L
    end

    -- разделитель внутри секции: тонкая линия от X_TXT
    function Group:AddDivider()
        self.Count += 1
        local d = Create("Frame", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, LayoutOrder = self.Count, Parent = self.Panel })
        local line = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, SK.X_TXT, 0.5, 0), Size = SK.CtrlSize(1), BorderSizePixel = 0, Parent = d })
        Theme(line, { BackgroundColor3 = "OutlineColor" })
        self.Height = (self.Height or 0) + 9
        self.AfterDivider = true
    end

    -- кнопка skeet: плашка во всю ширину контрола, жирный текст по центру
    function Group:AddButton(info, func)
        if type(info) == "string" then info = { Text = info, Func = func } end
        info = info or {}
        -- [v60] кнопка как на скрине оригинала (Steal player name): 25px с рамкой, внутри светлая линия 48,
        -- заливка сверху светлее (36 -> 31), текст жирный с чёрной тенью 1px вниз-вправо; шаг кнопок 33
        local row = self:_Row(SK.BTN_H + 10, info.Tooltip, info.Text, false)
        local btn, bgrad = SK.Field("TextButton", row, UDim2.fromOffset(SK.X_TXT, 2), SK.CtrlSize(SK.BTN_H))
        Library:AddRefresh(function()
            local c = Scheme.InputColor
            bgrad.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.023), c)
        end)
        local hl = Create("Frame", { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BackgroundTransparency = 1, Parent = btn })
        Create("UIStroke", { Color = Color3.fromRGB(48, 48, 48), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = hl })
        local shadow = Text({ Text = tostring(info.Text or ""), FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center, ColorKey = false,
            TextColor3 = Color3.new(0, 0, 0), TextTransparency = 0.2, Position = UDim2.fromOffset(1, 1), Size = UDim2.fromScale(1, 1),
            ClipsDescendants = true, Parent = btn })
        local label = Text({ Text = tostring(info.Text or ""), FontFace = F(W_BOLD), TextXAlignment = Enum.TextXAlignment.Center,
            Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = btn })
        btn.MouseEnter:Connect(function() label.TextColor3 = WHITE end)
        btn.MouseLeave:Connect(function() label.TextColor3 = Scheme.FontColor end)
        local B = { Row = row, Button = btn, Label = label, Text = tostring(info.Text or "") }
        function B:SetText(t) -- [v71]
            label.Text, shadow.Text = tostring(t), tostring(t)
        end
        -- [v71] Menu confirmations (как у skeet): info.Confirm - первый клик спрашивает «Are you sure?», второй
        -- (в течение 3 с) выполняет. Выключено в настройках - сразу.
        local armedAt = nil
        btn.MouseButton1Click:Connect(function()
            if info.Confirm and Library.Confirmations ~= false and not (armedAt and os.clock() - armedAt < 3) then
                armedAt = os.clock()
                local my = armedAt
                B:SetText("Are you sure?")
                label.TextColor3 = Scheme.AccentColor
                task.delay(3, function()
                    if armedAt == my then armedAt = nil B:SetText(B.Text) label.TextColor3 = Scheme.FontColor end
                end)
                return
            end
            armedAt = nil
            B:SetText(B.Text)
            label.TextColor3 = Scheme.AccentColor
            Tween(label, 0.25, { TextColor3 = Scheme.FontColor })
            Safe(info.Func or info.Callback)
        end)
        local group = self
        function B:AddButton(...) return group:AddButton(...) end
        return B
    end

    -- [v71] список как у skeet (Presets): тёмное поле фиксированной высоты, строки 18px, выбранная - акцентом
    -- жирным на подложке; не влезает - скролл. info.Values - таблица или функция; info.Rows - высота в строках.
    function Group:AddListbox(idx, info)
        info = info or {}
        local rows = info.Rows or 7
        local h = rows * LIST_H + 4
        local row = self:_Row(h + 8, info.Tooltip, info.Text or "", false)
        local box = Create("Frame", { Position = UDim2.fromOffset(SK.X_TXT, 2), Size = SK.CtrlSize(h), BorderSizePixel = 0, Parent = row })
        Theme(box, { BackgroundColor3 = "InputColor" })
        Stroke(box, "InputBorder")
        local scroll = Create("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = box })
        Theme(scroll, { ScrollBarImageColor3 = "TrackColor" })
        Pad(scroll, 0, 0, 2, 2)
        List(scroll, nil, 0)
        local LB = { Type = "Listbox", Value = info.Default, Values = {}, Changed = {}, Callback = info.Callback }
        function LB:Refresh()
            local vals = info.Values
            if type(vals) == "function" then local ok, v = pcall(vals) vals = ok and v or {} end
            self.Values = vals or {}
            for _, c in ipairs(scroll:GetChildren()) do if c:IsA("GuiButton") then c:Destroy() end end
            for i, v in ipairs(self.Values) do
                local sel = v == self.Value
                local b = ListRow(scroll, i, v, sel)
                if sel then b.BackgroundTransparency = 0 end
                b.MouseLeave:Connect(function() if v == LB.Value then b.BackgroundTransparency = 0 end end)
                b.MouseButton1Click:Connect(function() LB:SetValue(v) end)
            end
        end
        function LB:SetValues(v) info.Values = v or {} self:Refresh() end
        function LB:OnChanged(fn) table.insert(self.Changed, fn) end
        function LB:SetValue(v)
            self.Value = v
            self:Refresh()
            Fire(self)
        end
        LB:Refresh()
        if idx then Options[idx] = LB end
        return LB
    end

    -- поле ввода: подпись сверху, поле 20px, курсор «_» как у skeet
    function Group:AddInput(idx, info)
        info = info or {}
        local hasText = info.Text ~= nil and info.Text ~= ""
        local top = hasText and SK.LBL_H + 1 or 1
        local row = self:_Row(top + SK.FIELD_H + 2 + 5, info.Tooltip, info.Text, false)
        if hasText then SK.Label(row, info.Text, 0, SK.LBL_H) end
        local I = { Type = "Input", Value = tostring(info.Default or ""), Changed = {}, Callback = info.Callback }
        local box = SK.Field("TextBox", row, UDim2.fromOffset(SK.X_TXT, top + 1), SK.CtrlSize(SK.FIELD_H))
        box.ClearTextOnFocus = false
        box.FontFace = F(W_REG)
        box.TextSize = 12
        box.Text = I.Value
        box.PlaceholderText = info.Placeholder or ""
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.ClipsDescendants = true
        Theme(box, { TextColor3 = "ValueColor", PlaceholderColor3 = "DimColor" })
        Pad(box, 7, info.Clear and 18 or 7, 0, 0)
        -- [v71] крестик справа (как в поле имени пресета у skeet): очищает поле
        if info.Clear then
            local x = Button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, SK.X_TXT + SK.CTRL_W - 2, 0, top + 1 + SK.FIELD_H / 2),
                Size = UDim2.fromOffset(14, SK.FIELD_H), ZIndex = 3, Parent = row })
            local xl = Text({ Text = "×", TextSize = 13, ColorKey = "SubColor", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = x })
            x.MouseEnter:Connect(function() xl.TextColor3 = WHITE end)
            x.MouseLeave:Connect(function() xl.TextColor3 = Scheme.SubColor end)
            x.MouseButton1Click:Connect(function() I:SetValue("") end)
        end
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

    -- dropdown skeet: подпись сверху (аддоны справа от неё), поле с «v»; список вплотную под полем
    function Group:AddDropdown(idx, info)
        info = info or {}
        local hasText = info.Text ~= nil and info.Text ~= ""
        local top = hasText and SK.LBL_H + 1 or 1
        local row = self:_Row(top + SK.FIELD_H + 2 + 5, info.Tooltip, info.Text, false)
        local rowLabel = hasText and SK.Label(row, info.Text, 0, SK.LBL_H) or nil
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

        local btn, _, fieldHover = SK.Field("TextButton", row, UDim2.fromOffset(SK.X_TXT, top + 1), SK.CtrlSize(SK.FIELD_H)) -- [v55]
        btn.MouseEnter:Connect(function() fieldHover(true) end) -- [v55]
        btn.MouseLeave:Connect(function() fieldHover(false) end) -- [v55]
        local label = Text({
            Text = "", ColorKey = "ValueColor", Position = UDim2.fromOffset(7, 0),
            Size = UDim2.new(1, -24, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn,
        })
        SK.Caret(btn)
        -- место под аддоны (цвет, «...») - справа на строке подписи
        local addons = SK.Right(row, -1)
        addons.Size = UDim2.fromOffset(0, SK.LBL_H)
        D.Right, D.Addons, D.Row = addons, {}, row
        AddonMixin(D)
        if rowLabel then SK.Fit(rowLabel, addons) end

        function D:Display()
            if self.Multi then
                local parts = {}
                for _, v in ipairs(self.Values) do if self.Value[v] then table.insert(parts, tostring(v)) end end
                label.Text = #parts > 0 and table.concat(parts, ", ") or "-"
            else
                label.Text = self.Value ~= nil and tostring(self.Value) or "-"
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
                OpenList(btn, D.Values, D.Value, function(v) D:SetValue(v) end, true)
            end
        end)

        D:Display()
        if idx then Options[idx] = D end
        return D
    end

    --------------------------------------------------------
    -- AMBIENCE: служебные элементы для панелей настроек
    --------------------------------------------------------
    local Storage = Create("Frame", { Name = "Storage", Visible = false, Size = UDim2.fromOffset(250, 0), Parent = ScreenGui })

    -- секция без страницы: её элементы живут в скрытом хранилище, пока панель не показана
    DetachedGroup = function()
        local G = setmetatable({ Page = { Groups = {}, Rows = {} }, Name = "", Count = 0, Rows = 0, Height = 0 }, Group)
        local panel = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = Storage })
        List(panel)
        G.Panel, G.Holder = panel, panel
        return G
    end

    -- popup с «одолженной» секцией (высота - сумма строк)
    OpenSettings = function(anchor, G, title, width)
        local head = title and 24 or 6
        local h = head + (G.Height or 0) + 8
        OpenPopup(anchor, width or 250, h, function(frame, _, p)
            if title then
                Text({ Text = tostring(title), FontFace = F(W_BOLD), Position = UDim2.fromOffset(SK.X_BOX - 6, 4), Size = UDim2.new(1, -24, 0, 16), Parent = frame })
            end
            G.Panel.Position = UDim2.fromOffset(-8, head)
            G.Panel.Size = UDim2.new(1, 8, 0, 0)
            G.Panel.Parent = frame
            p.Late = function() if G.Panel.Parent ~= nil then G.Panel.Parent = Storage end end
            return nil
        end)
    end

    -- «...» (три точки 2px) справа в строке
    DotsButton = function(parent, order)
        local b = Button({ Size = UDim2.fromOffset(14, SK.CHK_H), LayoutOrder = order, Parent = parent })
        local dots = {}
        for i = -1, 1 do
            local d = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 4, 0.5, 1), Size = UDim2.fromOffset(2, 2), BorderSizePixel = 0, Parent = b })
            Theme(d, { BackgroundColor3 = "SubColor" })
            table.insert(dots, d)
        end
        b.MouseEnter:Connect(function() for _, d in ipairs(dots) do d.BackgroundColor3 = Scheme.AccentColor end end)
        b.MouseLeave:Connect(function() for _, d in ipairs(dots) do d.BackgroundColor3 = Scheme.SubColor end end)
        return b
    end

    -- ESP: кнопки-переключатели. Каждая кнопка - обычный Toggle (Toggles[idx]), нарисованный
    -- плашкой: включённая - на подложке, текст акцентом (у skeet так выбран пункт списка).
    function Group:AddChips(info)
        -- [v58] вместо кнопок-плашек - обычные чекбоксы skeet (те же Toggles[idx], ПКМ - бинд)
        info = info or {}
        if info.Title then self:AddLabel(tostring(info.Title)) end
        local C = { Toggles = {} }
        for _, it in ipairs(info.Items or {}) do
            C.Toggles[it.Idx] = self:AddCheckbox(it.Idx, { Text = it.Text, Default = it.Default == true, Tooltip = it.Tooltip })
        end
        return C
    end

    -- SKINCHANGER: картинка (превью аватара) на всю ширину секции
    function Group:AddImage(info)
        info = info or {}
        local h = info.Height or 200
        local row = self:_Row(h + 10, nil, info.Text or "", false)
        local box = Create("Frame", { Position = UDim2.fromOffset(SK.X_BOX, 4), Size = UDim2.new(1, -SK.X_BOX - SK.R_PAD, 1, -8), BorderSizePixel = 0, Parent = row })
        Theme(box, { BackgroundColor3 = "MainColor" })
        Stroke(box, "InputBorder")
        local img = Create("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = "", ScaleType = Enum.ScaleType.Fit, Parent = box })
        local hint = Text({ Text = tostring(info.Placeholder or "No preview"), ColorKey = "DimColor",
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

    -- строка-кнопка «Подпись ...» (открывает панель настроек)
    function Group:AddSubmenu(text, info)
        info = info or {}
        local g = DetachedGroup()
        Safe(info.Build, g)
        local row = self:_Row(SK.CHK_H, info.Tooltip, text, true)
        local label = SK.Label(row, text)
        local more = Text({ Text = "...", ColorKey = "SubColor", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -SK.R_PAD, 0, -3),
            Size = UDim2.fromOffset(16, SK.CHK_H), TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
        row.MouseEnter:Connect(function() label.TextColor3 = WHITE more.TextColor3 = Scheme.AccentColor end)
        row.MouseLeave:Connect(function() label.TextColor3 = Scheme.FontColor more.TextColor3 = Scheme.SubColor end)
        row.MouseButton1Click:Connect(function() OpenSettings(more, g, info.Title or text, info.Width) end)
        return { Row = row, SettingsGroup = g }
    end

    -- список-выбор как listbox у skeet (пресеты / Lua): выбранная строка - акцентом и жирным,
    -- справа «...» (меню действий) или «+»
    -- info.Items() -> { { Name, Text, Added, Selected } }, info.OnSelect(name), info.OnAdd(name), info.Menu(name) -> { {Text, Func} }
    function Group:AddSelectList(info)
        info = info or {}
        local row = self:_Row(0, nil, "", false)
        row.AutomaticSize = AY
        local box = Create("Frame", { Position = UDim2.fromOffset(SK.X_TXT, 2), Size = SK.CtrlSize(0), AutomaticSize = AY, BorderSizePixel = 0, Parent = row })
        Theme(box, { BackgroundColor3 = "InputColor" })
        Stroke(box, "InputBorder")
        local holder = Create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = box })
        Pad(holder, 0, 0, 2, 2)
        List(holder, nil, 0)
        Pad(row, 0, 0, 0, 6)
        self.Height = (self.Height or 0) + 120
        local SL = {}
        function SL:Refresh()
            for _, c in ipairs(holder:GetChildren()) do if c:IsA("GuiButton") then c:Destroy() end end
            local items = {}
            pcall(function() items = info.Items() or {} end)
            for i, it in ipairs(items) do
                local b, lbl = ListRow(holder, i, it.Text or it.Name, it.Selected)
                lbl.Size = UDim2.new(1, -40, 1, 0)
                if not it.Added then lbl.TextColor3 = Scheme.SubColor end
                local right = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(0, LIST_H),
                    AutomaticSize = AX, BackgroundTransparency = 1, Parent = b })
                List(right, Enum.FillDirection.Horizontal, 2, nil, Enum.VerticalAlignment.Center)
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
                    local add = Button({ Size = UDim2.fromOffset(0, LIST_H), AutomaticSize = AX, LayoutOrder = 1, Parent = right })
                    Pad(add, 4, 4, 0, 0)
                    Text({ Text = "+ Add", ColorKey = "AccentColor", Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = add })
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
    -- [v48] окно skeet 660x560 (замер с видео: 438x373 при 720p, x1.5):
    --   рамка из 6 слоёв 1px (11/27/50/38/48/15), радужная полоска 2px сверху,
    --   колонка вкладок 76px (иконки, у активной фон контента), справа контент с групбоксами,
    --   у вкладок с подвкладками сверху полоса-переключатель (как «Weapon type»),
    --   снизу узкая строка: название / футер слева, поиск, сохранить, конфиг справа.
    --------------------------------------------------------
    function Library:CreateWindow(info)
        info = info or {}
        -- [v49] размеры со скриншота skeet 1:1: колонка вкладок 73 + линии 0 / 48, вкладка 64,
        -- поля контента 20 слева / 23 сверху, колонки групбоксов через 22
        local W, H, TABW, TAB_H = 660, 560, 75, 64 -- [v54] по Menu.cpp: колонка вкладок 75 [v74] вкладка 64 (замер по скринам: шаг иконок 64, было 75)
        local title = tostring(info.Title or "Menu")
        local Window = { Tabs = {}, Active = nil }
        Library.Window = Window
        LoadMenuFontNow() -- [v49] шрифт до создания окна (синхронно), и на уже созданные тексты
        if MenuFamily then
            for _, d in ipairs(ScreenGui:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    pcall(function() if d.FontFace.Family == FONT then d.FontFace = Font.new(MenuFamily, d.FontFace.Weight) end end)
                end
            end
        end

        -- Main - прозрачная рамка (ловит клики, масштаб, позиция при драге).
        -- АНИМАЦИЯ: всё содержимое в Body, чтобы окно целиком плавно проявлялось.
        local Main = Button({
            Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
            Visible = info.AutoShow ~= false, Parent = ScreenGui,
        })
        -- [v50] рамка окна как у оригинала (1080p кадр gamesense): 12 / 70 / 40 / 40 / 70 / 0 (снаружи внутрь)
        local Body = Create("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(12, 12, 12), Parent = Main })
        local ring = Body
        for i, c in ipairs({ 70, 40, 40, 70, 0 }) do
            ring = Create("Frame", { Name = "Ring" .. i, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2),
                BackgroundColor3 = Color3.fromRGB(c, c, c), BorderSizePixel = 0, Parent = ring })
        end
        local Inner = Create("Frame", { Name = "Inner", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), BorderSizePixel = 0, ClipsDescendants = true, Parent = ring })
        Theme(Inner, { BackgroundColor3 = "MainColor" })
        Library._Inner = Inner
        -- фон контента - узор 4x4 skeet (нет getcustomasset - ровный цвет 21)
        local function Pattern(parent, z)
            local id = Library:GetIcon("sk_pattern_3")
            if not id then return nil end
            local img = Create("ImageLabel", { Name = "Pattern", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = id,
                ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(4, 8), ZIndex = z or 1, Parent = parent })
            pcall(function() img.ResampleMode = Enum.ResamplerMode.Pixelated end)
            return img
        end
        SK.Pattern = Pattern
        Pattern(Inner, 0)
        -- сверху: линия 12, радужная полоска 1px яркая + 1px тёмная (у skeet фиксированная, не от акцента)
        local RAINBOW = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(55, 177, 218)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(201, 72, 205)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(204, 227, 53)),
        })
        Create("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(12, 12, 12), BorderSizePixel = 0, ZIndex = 5, Parent = Inner })
        for i, tr in ipairs({ 0, 0.45 }) do
            local line = Create("Frame", { Name = "Rainbow", Position = UDim2.fromOffset(0, i), Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = WHITE, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 5, Parent = Inner })
            local g = Create("UIGradient", { Color = RAINBOW, Parent = line })
            if tr > 0 then line.BackgroundColor3 = Color3.fromRGB(145, 145, 145) end -- [v55] ColorBar: чёрный 0.43 поверх -> x0.57
        end
        -- прозрачность окна (Config -> Theme): фон контента и колонки вкладок
        Library:AddRefresh(function()
            local t = math.clamp(Library.Transparency or 0, 0, 0.9)
            Inner.BackgroundTransparency = t
        end)

        local Scale = Create("UIScale", { Parent = Main })
        Library._UIScale = Scale
        local fitScale, zoom = 1, 1
        Library.MenuScale = Library.MenuScale or 1
        local function applyScale() Scale.Scale = fitScale * zoom * (Library.MenuScale or 1) end
        function Library:SetMenuScale(v)
            Library.MenuScale = math.clamp(tonumber(v) or 1, 0.5, 2)
            applyScale()
            if Library._ThemeSave then Library._ThemeSave() end
        end
        -- [v49] как у skeet: 1:1, уменьшается только если не влезает в экран (раньше растягивалось до 125%)
        local function rescale()
            local vp = ScreenGui.AbsoluteSize
            if vp.X <= 0 then return end
            local sz = Main.Size -- [v51] окно растягивается: подгонка под экран от текущего размера
            fitScale = math.clamp(math.min((vp.X - 24) / sz.X.Offset, (vp.Y - 24) / sz.Y.Offset), 0.45, 1)
            applyScale()
        end
        rescale()
        Connect(ScreenGui:GetPropertyChangedSignal("AbsoluteSize"), rescale)
        local ZoomValue = Create("NumberValue", { Value = 1 })
        Connect(ZoomValue:GetPropertyChangedSignal("Value"), function() zoom = ZoomValue.Value applyScale() end)

        -- колонка вкладок: фон 12, справа линии 0 и 48
        local Side = Create("Frame", { Name = "Side", Position = UDim2.fromOffset(0, 3), Size = UDim2.new(0, TABW, 1, -3), BorderSizePixel = 0, ZIndex = 2, Active = true, Parent = Inner })
        Theme(Side, { BackgroundColor3 = "BackgroundColor" })
        Library:AddRefresh(function() Side.BackgroundTransparency = math.clamp(Library.Transparency or 0, 0, 0.9) end)
        for i, c in ipairs({ 0, 45 }) do -- [v50] оригинал: 0 / 45
            Create("Frame", { Position = UDim2.fromOffset(TABW + i - 1, 3), Size = UDim2.new(0, 1, 1, -3), BackgroundColor3 = Color3.fromRGB(c, c, c),
                BorderSizePixel = 0, ZIndex = 1, Parent = Inner })
        end
        -- [v54] TabSpacer 10 сверху (Menu.cpp)
        local Nav = Create("Frame", { Name = "Nav", Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 1, -10), BackgroundTransparency = 1, Parent = Side })
        List(Nav, nil, 0)
        local navOrder = 0
        local function nextOrder() navOrder += 1 return navOrder * 100 end

        -- ячейка вкладки 64px: иконка по центру (неактивная 100, активная 185);
        -- у активной фон контента с узором, сверху линии 0 / 48, снизу 48 / 0, и она на 2px шире колонки -
        -- перекрывает край, вкладка «сливается» с контентом (как на скрине)
        -- [v52] имена иконок из rest.lua -> иконки вкладок в духе skeet
        -- [v56] иконки со скриншота gamesense; [v57] + дискета Config
        local TAB_ICONS = { players = "sk_gs_players", world = "sk_gs_world", visuals = "sk_gs_world", skin = "sk_gs_skin", survivor = "sk_gs_survivor", -- [v73] visuals - солнце
            sub_killer = "sk_gs_killer", misc = "sk_gs_misc", config = "sk_gs_config" }
        local function NavItem(text, order, icon)
            icon = TAB_ICONS[icon] or icon
            local item = Button({ Name = "Tab", Size = UDim2.new(1, 2, 0, TAB_H), LayoutOrder = order, ZIndex = 3, Parent = Nav })
            local pat = Pattern(item, 3)
            local lines = {}
            for i, c in ipairs({ { 0, 0 }, { 1, 45 }, { -2, 45 }, { -1, 0 } }) do
                local f = Create("Frame", { Position = UDim2.new(0, 0, c[1] < 0 and 1 or 0, c[1]), Size = UDim2.new(1, 0, 0, 1),
                    BackgroundColor3 = Color3.fromRGB(c[2], c[2], c[2]), BorderSizePixel = 0, Visible = false, ZIndex = 4, Parent = item })
                lines[i] = f
            end
            local slot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -1, 0.5, 0), Size = UDim2.fromOffset(34, 34),
                BackgroundTransparency = 1, ZIndex = 4, Parent = item })
            local isz = string.find(tostring(icon), "^sk_gs_") and 48 or 34 -- [v56] скриновые 48x48 - без масштаба
            slot.Size = UDim2.fromOffset(isz, isz) -- [v56]
            local glyph = Icon(slot, icon, nil, isz, true) -- [v56]
            if glyph then glyph.ZIndex = 4 end
            if glyph and not glyph:IsA("ImageLabel") then glyph.Size = UDim2.fromOffset(10, 10) end
            local hovered = false
            local N = { Wrap = item, Item = item, Open = true }
            local function set(inst, props)
                if Library.Animations then Anim(inst, T_NAV, props) else for k, v in pairs(props) do inst[k] = v end end
            end
            function N:Paint(selected)
                item.BackgroundColor3 = Scheme.MainColor
                item.BackgroundTransparency = selected and 0 or 1
                if pat then pat.Visible = selected end
                for _, l in ipairs(lines) do l.Visible = selected end
                local gc = selected and Color3.fromRGB(185, 185, 185) or (hovered and Color3.fromRGB(185, 185, 185) or Color3.fromRGB(100, 100, 100)) -- [v55] TabTextHovered 185
                if glyph:IsA("ImageLabel") then set(glyph, { ImageColor3 = gc }) else set(glyph, { BackgroundColor3 = gc }) end
            end
            function N:SetOpen() end -- (у NL раскрывались подпункты; у skeet подвкладки сверху)
            item.MouseEnter:Connect(function() hovered = true if N.Repaint then N.Repaint() end end)
            item.MouseLeave:Connect(function() hovered = false if N.Repaint then N.Repaint() end end)
            AttachTooltip(item, text)
            return N
        end

        -- [v49] настройки, что у NL жили в попапе профиля (Menu / ESP Scale, Units), перенесены в Config -> Theme
        Library.ESPScale = Library.ESPScale or 1
        Library.Units = Library.Units or "studs"

        -- контент (без шапки и нижней строки - как у skeet)
        local Content = Create("Frame", { Name = "Content", Position = UDim2.fromOffset(TABW + 1, 3), Size = UDim2.new(1, -TABW - 1, 1, -3), BackgroundTransparency = 1, Parent = Inner })
        local PagesHolder = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = Content })
        -- поиск остался только как API (Window:SetSearch / ApplySearch); поля в окне нет - у skeet его нет
        local SearchBox = { Text = "" }
        function Window:SetSearch(q)
            SearchBox.Text = tostring(q or "")
            self:ApplySearch()
        end

        -- [v51] растягивание окна, как у skeet: ручка-треугольник в правом нижнем углу.
        -- Левый верхний угол стоит на месте; размер 600x440 .. 1200x900; запоминается в theme_skeet.json.
        local MIN_W, MIN_H, MAX_W, MAX_H = 600, 440, 1200, 900
        function Library:SetMenuSize(w, h, keepCorner)
            w = math.clamp(math.floor((tonumber(w) or W) + 0.5), MIN_W, MAX_W)
            h = math.clamp(math.floor((tonumber(h) or H) + 0.5), MIN_H, MAX_H)
            local old = Main.Size
            -- [v52] ФИКС «окно ездит при растягивании»: сдвиг по формуле был верен только при масштабе 1
            -- (у тебя ~1.13), ошибка копилась. Теперь угол меряется до и после и возвращается на место.
            -- [v58] ФИКС «ездит при растягивании» (2): Offset у UDim2 целый, дробная поправка каждого кадра
            -- обрезалась и ошибка копилась. Теперь сдвиг считается от момента захвата (keepCorner = таблица).
            if type(keepCorner) == "table" then
                -- [v79] ФИКС «тряска при растягивании»: на время тяги у окна AnchorPoint (0, 0) (см. Grip ниже),
                -- левый верхний угол стоит сам - меняется только размер, позицию не трогаем. Раньше при центре
                -- (0.5, 0.5) и масштабе ~1.13 угол каждый кадр пересчитывался с дробью 0.5px и округлялся то вверх,
                -- то вниз (плюс самопроверка v58 поправляла на 1px туда-обратно) - окно дрожало на 1px.
                Main.Size = UDim2.fromOffset(w, h)
                Library.MenuSize = { W = w, H = h }
                return -- [v58] масштаб под экран пересчитывается после отпускания (иначе окно прыгает во время тяги)
            end
            local before = keepCorner and Main.AbsolutePosition or nil
            if keepCorner then
                local sc = Scale.Scale
                local dw, dh = (w - old.X.Offset) * sc / 2, (h - old.Y.Offset) * sc / 2
                local pos = Main.Position
                Main.Position = UDim2.new(pos.X.Scale, pos.X.Offset + dw, pos.Y.Scale, pos.Y.Offset + dh)
            end
            Main.Size = UDim2.fromOffset(w, h)
            if before then
                local after = Main.AbsolutePosition
                local dx, dy = before.X - after.X, before.Y - after.Y
                if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
                    local pos = Main.Position
                    Main.Position = UDim2.new(pos.X.Scale, pos.X.Offset + dx, pos.Y.Scale, pos.Y.Offset + dy)
                end
            end
            Library.MenuSize = { W = w, H = h }
            rescale()
        end
        Library.MenuSize = { W = W, H = H }
        local Grip = Button({ Name = "ResizeGrip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(12, 12),
            ZIndex = 10, Parent = Inner })
        local gripBars = {}
        for k = 0, 5 do -- треугольник 6px, как в углах у skeet
            local f = Create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 1, -8 + k), Size = UDim2.fromOffset(k + 1, 1),
                BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(70, 70, 70), ZIndex = 10, Parent = Grip })
            table.insert(gripBars, f)
        end
        Grip.MouseEnter:Connect(function() for _, f in ipairs(gripBars) do f.BackgroundColor3 = Color3.fromRGB(120, 120, 120) end end)
        Grip.MouseLeave:Connect(function() for _, f in ipairs(gripBars) do f.BackgroundColor3 = Color3.fromRGB(70, 70, 70) end end)
        Grip.InputBegan:Connect(function(input)
            if not IsClick(input) then return end
            local start, sw, sh = V2(input.Position), Main.Size.X.Offset, Main.Size.Y.Offset
            local sc = math.max(Scale.Scale, 0.01)
            local anchor = {} -- [v58] признак «тянем за угол» для SetMenuSize
            -- [v79] на время тяги - якорь в левом верхнем углу (UIScale масштабирует вокруг AnchorPoint), позиция -
            -- тот же угол на экране: дальше меняется только Size, и угол не дрожит
            local gui0 = ScreenGui.AbsolutePosition
            local abs0 = Main.AbsolutePosition
            Main.AnchorPoint = Vector2.new(0, 0)
            Main.Position = UDim2.fromOffset(math.floor(abs0.X - gui0.X + 0.5), math.floor(abs0.Y - gui0.Y + 0.5))
            BeginDrag(input, function(pos)
                local d = pos - start
                Library:SetMenuSize(sw + d.X / sc, sh + d.Y / sc, anchor) -- [v58]
            end, function()
                -- [v79] обратно к центру (0.5, 0.5), как при создании окна: позиция - от центра экрана, угол на месте
                local vp, tl, sz = ScreenGui.AbsoluteSize, Main.AbsolutePosition - ScreenGui.AbsolutePosition, Main.AbsoluteSize
                Main.AnchorPoint = Vector2.new(0.5, 0.5)
                Main.Position = UDim2.new(0.5, math.floor(tl.X + sz.X / 2 - vp.X / 2 + 0.5), 0.5, math.floor(tl.Y + sz.Y / 2 - vp.Y / 2 + 0.5))
                rescale() -- [v58]
                if Library._ThemeSave then Library._ThemeSave() end
            end)
        end)

        -- перетаскивание окна: за колонку вкладок и за верхнее поле над групбоксами
        local Grip = Create("Frame", { Name = "Grip", Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 1, Active = true, ZIndex = 6, Parent = Content })
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
        draggable(Grip)
        draggable(Side)

        -- страница: две колонки групбоксов; top - место под полосу подвкладок
        local AllPages = {}
        local SUB_H = 60
        -- групбокс skeet: снаружи линия 10, внутри 48, заливка 17; заголовок жирным лежит прямо на линии,
        -- под текстом рамка прерывается (как «Other ESP» на скрине)
        local function GroupFrame(parent, name, order)
            local holder = Create("Frame", { Size = UDim2.fromScale(1, 0), AutomaticSize = AY, BackgroundTransparency = 1, LayoutOrder = order or 1, Parent = parent })
            -- [v50] рамка оригинала: снаружи 0, внутри 45
            Create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = holder })
            local panel = Create("Frame", { Size = UDim2.fromScale(1, 0), AutomaticSize = AY, BorderSizePixel = 0, Parent = holder })
            Theme(panel, { BackgroundColor3 = "GroupColor" })
            Stroke(panel, "OutlineColor")
            -- [v50] ФИКС «перечёркнутых» заголовков: разрыв рамки был ребёнком текста и рисовался ПОВЕРХ букв.
            -- Теперь заголовок - рамка-контейнер: снизу разрыв (цвет фона окна), сверху текст.
            local title = Create("Frame", { Name = "Title", Position = UDim2.fromOffset(10, -7), Size = UDim2.fromOffset(0, 12), AutomaticSize = AX,
                BackgroundTransparency = 1, ZIndex = 3, Parent = holder })
            Pad(title, 3, 3, 0, 0)
            local gap = Create("Frame", { Name = "Gap", Position = UDim2.new(0, -3, 0, 5), Size = UDim2.new(1, 6, 0, 2), BorderSizePixel = 0, ZIndex = 3, Parent = title })
            Theme(gap, { BackgroundColor3 = "MainColor" })
            local titleLabel = Text({ Text = tostring(name or ""), FontFace = F(W_BOLD), ColorKey = false, TextColor3 = SK.TITLE,
                Size = UDim2.fromOffset(0, 12), AutomaticSize = AX, ZIndex = 4, Parent = title })
            title.Visible = tostring(name or "") ~= ""
            return holder, panel, titleLabel
        end
        SK.GroupFrame = GroupFrame
        -- [v52] скроллбар как у skeet: плоский тонкий бегунок (не скруглённый Roblox) и стрелки сверху/снизу
        -- [v58] общий для страницы и для скролла внутри групбокса
        SK.StyleScroll = function(scroll)
            -- [v61] по скрину оригинала: бегунок 6px (65) на светлой дорожке 40 у правого края,
            -- стрелки 5x3 цветом 160 - левее дорожки на 5px и на 4px от верха / низа (не заезжают на полосу)
            scroll.ScrollBarThickness = 6
            scroll.ScrollBarImageColor3 = Color3.fromRGB(65, 65, 65)
            scroll.ZIndex = math.max(tonumber(scroll.ZIndex) or 1, 2)
            local sp, ss = scroll.Position or UDim2.new(), scroll.Size or UDim2.fromScale(1, 1)
            local track = Create("Frame", { Name = "ScrollTrack", AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(sp.X.Scale + ss.X.Scale, sp.X.Offset + ss.X.Offset, sp.Y.Scale, sp.Y.Offset),
                Size = UDim2.new(0, 6, ss.Y.Scale, ss.Y.Offset), BackgroundColor3 = Color3.fromRGB(40, 40, 40), BorderSizePixel = 0,
                Visible = false, ZIndex = 1, Parent = scroll.Parent })
            local flat = Library:GetIcon("sk_white")
            if flat then scroll.TopImage, scroll.MidImage, scroll.BottomImage = flat, flat, flat end
            local deco = Create("Frame", { Name = "ScrollArrows", Position = scroll.Position, Size = scroll.Size, BackgroundTransparency = 1,
                Visible = false, ZIndex = 5, Parent = scroll.Parent })
            local function arrow(up)
                -- [v61] треугольник в строках 1..3 кнопки: ▲ с 4-й строки сверху, ▼ кончается за 4 строки до низа
                local b = Button({ Position = UDim2.new(1, -16, up and 0 or 1, up and 3 or -8),
                    Size = UDim2.fromOffset(5, 5), ZIndex = 5, Parent = deco })
                for k = 0, 2 do -- треугольник 5/3/1
                    local r = up and k or (2 - k)
                    Create("Frame", { Position = UDim2.fromOffset(2 - r, 1 + k), Size = UDim2.fromOffset(1 + r * 2, 1), BorderSizePixel = 0,
                        BackgroundColor3 = Color3.fromRGB(160, 160, 160), ZIndex = 5, Parent = b })
                end
                -- [v61] тёмная полоска у широкого края (у оригинала над ▼)
                Create("Frame", { Position = UDim2.fromOffset(0, up and 4 or 0), Size = UDim2.fromOffset(5, 1), BorderSizePixel = 0,
                    BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5, Parent = b })
                b.MouseButton1Click:Connect(function()
                    local cp = scroll.CanvasPosition
                    if cp then scroll.CanvasPosition = Vector2.new(cp.X, math.max(0, cp.Y + (up and -40 or 40))) end
                end)
            end
            arrow(true) arrow(false)
            local function decoSync()
                local canvas, win = scroll.AbsoluteCanvasSize, scroll.AbsoluteWindowSize
                deco.Visible = scroll.Visible and canvas ~= nil and win ~= nil and canvas.Y > win.Y + 1
                track.Visible = deco.Visible -- [v61]
            end
            for _, prop in ipairs({ "Visible", "AbsoluteCanvasSize", "AbsoluteWindowSize" }) do
                pcall(function() scroll:GetPropertyChangedSignal(prop):Connect(decoSync) end)
            end
            decoSync()
            return deco
        end
        -- parent: AMBIENCE - страница внутри панели поверх контента (не участвует в переключении вкладок)
        local function NewPage(parent, top)
            top = top or 0
            local Page = { Groups = {}, Rows = {} }
            local scroll = Create("ScrollingFrame", {
                Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1, BorderSizePixel = 0,
                ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y,
                Visible = parent ~= nil, Parent = parent or PagesHolder,
            })
            if not parent then table.insert(AllPages, scroll) end
            SK.StyleScroll(scroll) -- [v58] вынесено, чтобы так же оформлять скролл внутри групбокса
            local body = Create("Frame", {
                -- [v54] по Menu.cpp: групбокс 258, слева 19, между колонками 19, сверху 18 (+2 под рамку)
                -- [v74] по скрину оригинала: от колонки вкладок, от правого края и между колонками по 23px (было 18)
                Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -47, 0, 0), AutomaticSize = AY,
                BackgroundTransparency = 1, Parent = scroll,
            })
            Pad(body, 0, 0, 0, 16)
            local function column(left)
                local c = Create("Frame", {
                    Position = left and UDim2.new() or UDim2.new(0.5, 12, 0, 0), Size = UDim2.new(0.5, left and -13 or -12, 0, 0), -- [v74] между колонками 25
                    AutomaticSize = AY, BackgroundTransparency = 1, Parent = body,
                })
                List(c, nil, 22)
                return c
            end
            Page.Scroll = scroll
            local cols = { Left = column(true), Right = column(false) }
            -- [v58] как у skeet: колонка всегда по высоте окна, листается не страница, а групбокс,
            -- которому не хватило места. Высоты: кто влезает - по содержимому, остальным поровну оставшееся
            -- (свой скролл внутри); если всё влезает - последний в колонке тянется до низа.
            -- Если групбоксов столько, что даже по GROUP_MIN не влезают - как раньше листается страница.
            local GROUP_MIN = 60
            local colGroups = { [cols.Left] = {}, [cols.Right] = {} }
            local function relayout()
                local sc = math.max(Library._UIScale and Library._UIScale.Scale or 1, 0.01)
                local pageH = scroll.AbsoluteSize.Y / sc
                for _, list in pairs(colGroups) do
                    local vis = {}
                    for _, g in ipairs(list) do if g.Holder.Visible then table.insert(vis, g) end end
                    local n = #vis
                    if n > 0 then
                        local nat, sum = {}, 0
                        for i, g in ipairs(vis) do
                            local ok, cs = pcall(function() return g.Layout.AbsoluteContentSize end)
                            nat[i] = math.floor(((ok and cs) and cs.Y or 0) / sc + 19 + 0.5) -- + отступы 5 / 6 и 8 под заголовком [v74]
                            sum += nat[i]
                        end
                        local avail = math.floor(pageH - 22 - 16 - 2 - 22 * (n - 1)) -- [v74] сверху 22
                        local hs = {}
                        if sum <= avail then
                            for i = 1, n do hs[i] = nat[i] end
                            hs[n] = nat[n] + (avail - sum)
                        else
                            local order = {}
                            for i = 1, n do order[i] = i end
                            table.sort(order, function(x, y) return nat[x] < nat[y] end)
                            local rem, k, cap = avail, n, nil
                            for _, i in ipairs(order) do
                                if cap == nil and nat[i] <= rem / k then
                                    hs[i] = nat[i] rem -= nat[i] k -= 1
                                else
                                    cap = cap or math.floor(rem / k)
                                    hs[i] = cap
                                end
                            end
                            if cap and cap < GROUP_MIN then for i = 1, n do hs[i] = nat[i] end end
                        end
                        for i, g in ipairs(vis) do
                            local h = math.max(hs[i], 20)
                            if g.Box.Size.Y.Offset ~= h then g.Box.Size = UDim2.new(1, 0, 0, h) end
                        end
                    end
                end
            end
            scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
            scroll:GetPropertyChangedSignal("Visible"):Connect(relayout)
            Page.Restretch = relayout
            local function addGroup(col, name)
                local G = setmetatable({ Page = Page, Name = tostring(name or ""), Count = 0, Rows = 0, Height = 0 }, Group)
                local holder, panel, titleLabel = GroupFrame(col, G.Name, #Page.Groups + 1)
                -- [v58] рамка групбокса фиксированной высоты, внутри свой скролл со строками
                panel.AutomaticSize = Enum.AutomaticSize.None
                panel.Size = UDim2.new(1, 0, 0, 40)
                -- [v74] у skeet от рамки (заголовка) до первой галочки 20px (у нас было 12): скролл начинается на 8px ниже рамки,
                -- поэтому и пролистанные строки не заезжают под заголовок
                local gs = Create("ScrollingFrame", { Name = "GroupScroll", Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 1, -8), BackgroundTransparency = 1, BorderSizePixel = 0,
                    CanvasSize = UDim2.new(), AutomaticCanvasSize = AY, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = panel })
                SK.StyleScroll(gs)
                local rows = Create("Frame", { Name = "Rows", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AY, BackgroundTransparency = 1, Parent = gs })
                Pad(rows, 0, 0, 5, 6)
                local layout = List(rows)
                G.Holder, G.Panel, G.Title, G.Box, G.Layout, G.Scroll = holder, rows, titleLabel, panel, layout, gs
                table.insert(Page.Groups, G)
                table.insert(colGroups[col], G)
                -- [v72] убрать групбокс (Lua-скрипт выгружен): из страницы, колонки, поиска; раскладка заново
                function G:Destroy()
                    for i, g in ipairs(Page.Groups) do if g == G then table.remove(Page.Groups, i) break end end
                    local list = colGroups[col]
                    for i, g in ipairs(list) do if g == G then table.remove(list, i) break end end
                    for i = #Page.Rows, 1, -1 do if Page.Rows[i].Group == G then table.remove(Page.Rows, i) end end
                    pcall(function() holder:Destroy() end)
                    task.defer(relayout)
                end
                pcall(function() layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout) end)
                holder:GetPropertyChangedSignal("Visible"):Connect(relayout) -- поиск прячет групбоксы
                task.defer(relayout)
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

        -- АНИМАЦИЯ смены страницы: старая гаснет, новая проявляется (у skeet ~3 кадра).
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
                for _, t in ipairs(Window.Tabs) do -- [v50] растяжка нижних групбоксов
                    local pages = table.clone(t.SubTabs)
                    if t.Default then table.insert(pages, t.Default) end
                    for _, pg in ipairs(pages) do
                        if pg.Scroll == scroll and pg.Restretch then task.defer(pg.Restretch) end
                    end
                end
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
                if t.SubBar then t.SubBar.Visible = (t == tab) end
                t:Paint()
            end
            local page = self:CurrentPage()
            ShowPage(page and page.Scroll or nil)
            self:ApplySearch()
        end

        -- AMBIENCE: панель поверх области контента: шапка с заголовком и «x», ниже - две колонки секций
        function Window:AddOverlay(titleText)
            local OH = 28
            local ov = Button({
                Name = "Overlay", BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 20,
                Visible = false, Parent = Content,
            })
            Theme(ov, { BackgroundColor3 = "MainColor" })
            Text({ Text = tostring(titleText or ""), FontFace = F(W_BOLD), Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -60, 0, OH), Parent = ov })
            local line = Create("Frame", { Position = UDim2.fromOffset(0, OH), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Parent = ov })
            Theme(line, { BackgroundColor3 = "SeparatorColor" })
            -- «x» справа сверху
            local x = Button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0, OH / 2), Size = UDim2.fromOffset(16, 16), Parent = ov })
            local bars = {}
            for _, rot in ipairs({ 45, -45 }) do
                local b = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 1), Rotation = rot, BorderSizePixel = 0, Parent = x })
                Theme(b, { BackgroundColor3 = "SubColor" })
                table.insert(bars, b)
            end
            x.MouseEnter:Connect(function() for _, b in ipairs(bars) do b.BackgroundColor3 = Scheme.FontColor end end)
            x.MouseLeave:Connect(function() for _, b in ipairs(bars) do b.BackgroundColor3 = Scheme.SubColor end end)
            local body = Create("Frame", { Position = UDim2.fromOffset(0, OH + 1), Size = UDim2.new(1, 0, 1, -OH - 1), BackgroundTransparency = 1, Parent = ov })
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

        -- категория: у skeet подписей в колонке нет - просто промежуток между группами вкладок
        function Window:AddCategory(name)
            -- [v54] у skeet вкладки идут сплошь (7 x 75 + 10 = 535 из 545) - промежутков нет
        end

        -- полоса подвкладок (как «Weapon type» у skeet): групбокс во всю ширину, кнопки «иконка + имя»
        local function SubBar(tab)
            if tab.SubBar then return tab.SubBar end
            -- [v49] как «Weapon type»: обычный групбокс во всю ширину (рамка 10 / 48, заливка 17)
            local bar = Create("Frame", { Name = "SubBar", Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -47, 0, SUB_H - 30), -- [v74]
                BackgroundTransparency = 1, Visible = Window.Active == tab, Parent = Content })
            local holder, panel = GroupFrame(bar, "")
            holder.AutomaticSize, panel.AutomaticSize = Enum.AutomaticSize.None, Enum.AutomaticSize.None
            holder.Size, panel.Size = UDim2.fromScale(1, 1), UDim2.fromScale(1, 1)
            local row = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = panel })
            Pad(row, 14, 14, 0, 0)
            List(row, Enum.FillDirection.Horizontal, 22, nil, Enum.VerticalAlignment.Center)
            tab.SubBar, tab.SubRow = bar, row
            return bar
        end
        local function SubButton(tab, sub, i)
            local b = Button({ Size = UDim2.fromOffset(0, 22), AutomaticSize = AX, LayoutOrder = i, Parent = tab.SubRow })
            List(b, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
            local slot = Create("Frame", { Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, LayoutOrder = 1, Parent = b })
            local glyph = Icon(slot, sub.Icon, nil, 18, true)
            local label = Text({ Text = sub.Name, ColorKey = false, Size = UDim2.fromOffset(0, 22), AutomaticSize = AX, LayoutOrder = 2, Parent = b })
            local hovered = false
            local N = { Wrap = b, Item = b, Label = label }
            function N:Paint(on)
                local c = on and Color3.fromRGB(215, 215, 215) or (hovered and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(100, 100, 100))
                label.TextColor3 = c
                label.FontFace = F(on and W_BOLD or W_REG)
                if glyph:IsA("ImageLabel") then glyph.ImageColor3 = c else glyph.BackgroundColor3 = c end
            end
            function N:SetOpen() end
            b.MouseEnter:Connect(function() hovered = true tab:Paint() end)
            b.MouseLeave:Connect(function() hovered = false tab:Paint() end)
            b.MouseButton1Click:Connect(function() tab:SelectSub(sub) end)
            return N
        end

        -- [v73] opts.Category (вкладка Visuals): как «Category» у skeet - групбокс во всю ширину с заголовком,
        -- в нём только иконки подвкладок (шаг 75, выбранная - светлая, остальные серые). Замер по скрину: рамка 57px,
        -- центр первой иконки в 47px от края, до следующего групбокса 25px.
        local CAT_H, CAT_TOP, CAT_W = 57, 82, 75
        local function CatBar(tab)
            if tab.SubBar then return tab.SubBar end
            local bar = Create("Frame", { Name = "SubBar", Position = UDim2.fromOffset(24, 22), Size = UDim2.new(1, -47, 0, CAT_H), -- [v74]
                BackgroundTransparency = 1, Visible = Window.Active == tab, Parent = Content })
            local holder, panel = GroupFrame(bar, "Category")
            holder.AutomaticSize, panel.AutomaticSize = Enum.AutomaticSize.None, Enum.AutomaticSize.None
            holder.Size, panel.Size = UDim2.fromScale(1, 1), UDim2.fromScale(1, 1)
            local row = Create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = panel })
            Pad(row, 10, 10, 0, 0)
            List(row, Enum.FillDirection.Horizontal, 0, nil, Enum.VerticalAlignment.Center)
            tab.SubBar, tab.SubRow = bar, row
            return bar
        end
        local function CatButton(tab, sub, i)
            local b = Button({ Size = UDim2.fromOffset(CAT_W, CAT_H - 4), LayoutOrder = i, Parent = tab.SubRow })
            local slot = Create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(36, 36),
                BackgroundTransparency = 1, Parent = b })
            local glyph = Icon(slot, sub.Icon, nil, 36, true)
            local hovered = false
            local N = { Wrap = b, Item = b }
            function N:Paint(on)
                local c = on and Color3.fromRGB(215, 215, 215) or (hovered and Color3.fromRGB(150, 150, 150) or Color3.fromRGB(104, 104, 104))
                if glyph:IsA("ImageLabel") then glyph.ImageColor3 = c else glyph.BackgroundColor3 = c end
            end
            function N:SetOpen() end
            b.MouseEnter:Connect(function() hovered = true tab:Paint() end)
            b.MouseLeave:Connect(function() hovered = false tab:Paint() end)
            b.MouseButton1Click:Connect(function() tab:SelectSub(sub) end)
            return N
        end

        -- opts.Switcher (NL: переключатель над колонкой) у skeet не нужен: подвкладки всегда сверху
        function Window:AddTab(name, icon, opts)
            opts = opts or {}
            local order = nextOrder()
            local Tab = { Name = tostring(name), SubTabs = {}, ActiveSub = nil, Default = nil, Switcher = opts.Switcher == true,
                Category = opts.Category == true } -- [v73]
            local nav = NavItem(Tab.Name, order, icon)
            Tab.Nav = nav

            function Tab:Paint()
                nav:Paint(Window.Active == self)
                for _, s in ipairs(self.SubTabs) do
                    if s.Nav then s.Nav:Paint(self.ActiveSub == s) end
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

            -- подвкладка = кнопка в полосе сверху; её страница начинается под полосой
            -- [v70] opts.Switcher (Players): как «Weapon type» у skeet - полосы сверху нет, первым групбоксом
            -- слева «ESP type»: жирное имя подвкладки, её иконка и стрелка; клик - список подвкладок
            function Tab:AddSubTab(sname, sicon)
                local Sub
                if self.Category then -- [v73]
                    CatBar(self)
                    Sub = NewPage(nil, CAT_TOP)
                elseif self.Switcher then
                    Sub = NewPage(nil, 0)
                else
                    SubBar(self)
                    Sub = NewPage(nil, SUB_H)
                end
                Sub.Name, Sub.Icon = tostring(sname), sicon
                Sub.SwitchTab = self
                table.insert(self.SubTabs, Sub)
                if self.Switcher then
                    local tab = self
                    local box = Sub:AddLeftGroupbox(tostring(opts.SwitcherTitle or "ESP type"))
                    local row = box:_Row(24, nil, Sub.Name, true)
                    local label = Text({ Text = Sub.Name, FontFace = F(W_BOLD), ColorKey = false, TextColor3 = Color3.fromRGB(215, 215, 215),
                        Position = UDim2.fromOffset(SK.X_TXT, 0), Size = UDim2.new(1, -SK.X_TXT - 80, 1, 0), Parent = row })
                    local field = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -SK.R_PAD, 0.5, 0),
                        Size = UDim2.fromOffset(60, 22), BackgroundTransparency = 1, Parent = row })
                    local slot = Create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -18, 0.5, 0), Size = UDim2.fromOffset(20, 20),
                        BackgroundTransparency = 1, Parent = field })
                    local glyph = Icon(slot, sicon, nil, 20, true)
                    if glyph:IsA("ImageLabel") then glyph.ImageColor3 = Color3.fromRGB(200, 200, 200) else glyph.BackgroundColor3 = Color3.fromRGB(200, 200, 200) end
                    SK.Caret(field)
                    row.MouseEnter:Connect(function() label.TextColor3 = WHITE end)
                    row.MouseLeave:Connect(function() label.TextColor3 = Color3.fromRGB(215, 215, 215) end)
                    function Sub.TypePick(name)
                        for _, s in ipairs(tab.SubTabs) do
                            if s.Name == name then tab:SelectSub(s) return true end
                        end
                        return false
                    end
                    row.MouseButton1Click:Connect(function()
                        local names = {}
                        for _, s in ipairs(tab.SubTabs) do names[#names + 1] = s.Name end
                        OpenList(field, names, Sub.Name, function(v) Sub.TypePick(v) end, false)
                    end)
                    Sub.TypeRow, Sub.TypeLabel = row, label
                elseif self.Category then
                    Sub.Nav = CatButton(self, Sub, #self.SubTabs) -- [v73]
                else
                    Sub.Nav = SubButton(self, Sub, #self.SubTabs)
                end
                if not self.ActiveSub then self.ActiveSub = Sub end
                if Window.Active == self then Window:SelectTab(self) else self:Paint() end
                return Sub
            end

            table.insert(Window.Tabs, Tab)
            Library:AddRefresh(function() Tab:Paint() end)
            if not Window.Active then Window:SelectTab(Tab) end
            return Tab
        end

        -- конфиг (провайдер ставит SaveManager); выбор конфига - во вкладке Config, как у skeet
        function Window:SetConfigName(n)
            Library.ConfigName = tostring(n or "default") -- ВАТЕРМАРКА: пункт Preset
        end
        function Window:SetConfigProvider(p) self.ConfigProvider = p end

        -- освобождение мыши (first person) + свой курсор (у skeet - стрелка; здесь квадрат 5px с обводкой)
        local Modal = Button({ Size = UDim2.fromOffset(0, 0), Modal = true, Visible = Main.Visible, Parent = ScreenGui })
        local Cursor = Create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 5), BackgroundColor3 = WHITE,
            BorderSizePixel = 0, ZIndex = 100, Visible = false, Parent = ScreenGui,
        })
        Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = Cursor })
        local showCursor = info.ShowCustomCursor ~= false

        Connect(RunService.RenderStepped, function()
            if not Main.Visible then return end
            Acrylic:Update(Main, 6 * Scale.Scale)
            local m = MousePos()
            if showCursor then Cursor.Position = UDim2.fromOffset(m.X, m.Y) end
            if Tip.Visible then
                local vp = ScreenGui.AbsoluteSize
                local s = Tip.AbsoluteSize
                -- [v85] как у skeet: под курсором, левый край чуть левее острия (-6, +16)
                Tip.Position = UDim2.fromOffset(math.clamp(m.X - 6, 2, math.max(vp.X - s.X - 2, 2)), math.min(m.Y + 16, vp.Y - s.Y - 2))
            end
        end)

        -- АНИМАЦИЯ открытия/закрытия (skeet: только прозрачность ~0.10s). Состояние меняется сразу.
        Library.Toggled = Main.Visible
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
                    if not wasClosing then ZoomValue.Value = ZOOM_FROM end
                    Anim(ZoomValue, T_OPEN, { Value = 1 })
                    local from = 1
                    if wasClosing then from = nil end -- открыли посреди закрытия: продолжаем с текущего кадра
                    Fade(Body, 0, from, 0, T_OPEN, 0, UpdateBlur)
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
                    Anim(ZoomValue, T_CLOSE, { Value = ZOOM_FROM })
                    Fade(Body, 0, nil, 1, T_CLOSE, 0, function()
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
                BackgroundTransparency = 0, Position = UDim2.new(0, 12, 0.3, 0), Size = UDim2.fromOffset(40, 40),
                ZIndex = 40, Parent = ScreenGui,
            })
            Theme(mob, { BackgroundColor3 = "GroupColor" })
            Stroke(mob, "InputBorder")
            local initials = info.Logo or string.upper((title:gsub("(%w)%w*%s*", "%1"))):sub(1, 2)
            Text({ Text = initials, TextSize = 14, FontFace = F(W_BOLD), ColorKey = "AccentColor", TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), Parent = mob })
            mob.MouseButton1Click:Connect(function() Library:Toggle() end)
        end
        Library.LogoText = info.Logo or string.upper((title:gsub("(%w)%w*%s*", "%1"))):sub(1, 2)

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
    Library.KeybindColor = Color3.fromRGB(150, 195, 50) -- [v50] зелёный, как «NS» у gamesense

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

    -- [v72] хит-логи как у gamesense: строки сверху слева на тёмной полосе ватермарки (растворяется с обеих
    -- сторон), шрифт ватермарки; выделенные слова - акцентом. Двигается, пока открыто меню; позиция - в теме.
    -- HL:Push({ "Hit ", { "Name" }, " for ", { "40" }, " damage" }) - таблица в списке = выделить акцентом.
    function Library:CreateHitLog()
        if self.HitLogObj then return self.HitLogObj end
        self:LoadBindFonts()
        local insetY = 0
        pcall(function() insetY = GuiService:GetGuiInset().Y end)
        local HL = { Lines = {}, Enabled = true, Time = 5, Max = 6 }
        local holder = Create("Frame", { Name = "HitLog", Position = UDim2.fromOffset(6, 4 - insetY), Size = UDim2.fromOffset(420, 20),
            BackgroundTransparency = 1, Active = true, ZIndex = 40, Parent = ScreenGui })
        HL.Holder = holder
        local function esc(t) return (tostring(t):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
        local function layout()
            local y = 0
            for _, ln in ipairs(HL.Lines) do
                if ln.Y ~= y then ln.Y = y Tween(ln.Row, 0.12, { Position = UDim2.fromOffset(0, y) }) end
                y += 21
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
                if type(p) == "table" then
                    out[#out + 1] = '<font color="' .. hex .. '">' .. esc(p[1]) .. "</font>"
                else
                    out[#out + 1] = esc(p)
                end
            end
            local row = Create("Frame", { Position = UDim2.fromOffset(-12, #self.Lines * 21), Size = UDim2.fromOffset(0, 20), AutomaticSize = AX,
                BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 40, Parent = holder })
            Create("UIGradient", { Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.25), NumberSequenceKeypoint.new(0.88, 0.25), NumberSequenceKeypoint.new(1, 1),
            }), Parent = row })
            Pad(row, 22, 30, 0, 0)
            local txt = Text({ Text = table.concat(out), RichText = true, TextSize = 13, FontFace = BindFont(W_SEMI), ColorKey = false,
                TextColor3 = Color3.fromRGB(225, 225, 225), TextStrokeTransparency = 0.6, Size = UDim2.fromOffset(0, 20), AutomaticSize = AX,
                ZIndex = 41, Parent = row })
            local ln = { Row = row, Text = txt, Y = #self.Lines * 21, Born = os.clock() }
            table.insert(self.Lines, ln)
            Tween(row, 0.15, { Position = UDim2.fromOffset(0, ln.Y) })
            while #self.Lines > self.Max do remove(self.Lines[1]) end
            task.delay(self.Time, function() if table.find(HL.Lines, ln) then remove(ln) end end)
            layout()
        end
        function HL:Clear() for i = #self.Lines, 1, -1 do remove(self.Lines[i]) end end
        function HL:Serialize() return { pos = PosOf(holder), enabled = self.Enabled } end
        function HL:Load(d)
            if type(d) ~= "table" then return end
            SetPos(holder, d.pos)
        end
        DragWhenMenuOpen(holder)
        self.HitLogObj = HL
        return HL
    end

    -- [v75] HUD-панель в стиле окна skeet (радар, статистика): чёрная рамка, серая 2px, тёмный фон, сверху полоска
    -- акцента и заголовок. Двигается, пока открыто меню; позиции всех панелей - в теме (поле hud).
    Library.HudPanels = {}
    function Library:CreateHudPanel(key, title, w, h, pos)
        if self.HudPanels[key] then return self.HudPanels[key] end
        self:LoadBindFonts()
        local P = { Key = key }
        local holder = Create("Frame", { Name = "Hud_" .. tostring(key), Position = pos or UDim2.fromOffset(20, 200), Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = Color3.fromRGB(40, 40, 40), BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 30, Parent = ScreenGui })
        Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = holder })
        local inner = Create("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = Color3.fromRGB(17, 17, 17),
            BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 30, Parent = holder })
        Create("UIStroke", { Color = Color3.fromRGB(60, 60, 60), Thickness = 1, Parent = inner })
        local line = Create("Frame", { Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, ZIndex = 33, Parent = inner })
        Library:AddRefresh(function() line.BackgroundColor3 = Scheme.AccentColor end)
        line.BackgroundColor3 = Scheme.AccentColor
        local top = 2
        if title and title ~= "" then
            P.Title = Text({ Text = tostring(title), TextSize = 12, FontFace = BindFont(W_SEMI), ColorKey = false, TextColor3 = Color3.fromRGB(215, 215, 215),
                Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 15), ZIndex = 33, Parent = inner })
            top = 19
        end
        P.Body = Create("Frame", { Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top), BackgroundTransparency = 1, ZIndex = 31, Parent = inner })
        P.Frame, P.Inner = holder, inner
        function P:SetVisible(v) holder.Visible = v and not Library.Unloaded end
        function P:SetSize(nw, nh) holder.Size = UDim2.fromOffset(nw, nh) end
        function P:Serialize() return PosOf(holder) end
        function P:Load(d) SetPos(holder, d) end
        DragWhenMenuOpen(holder)
        self.HudPanels[key] = P
        if self._HudPending and self._HudPending[key] then P:Load(self._HudPending[key]) end
        return P
    end

    function Library:CreateKeybindList()
        if self.KeybindList then return self.KeybindList end
        self:LoadBindFonts()
        local T_IN, T_OUT = 0.18, 0.14

        ------------------------------------------------ индикаторы
        -- [v33] замер по твоей разметке: у NL плашка выше (над «H» ~8px, под ней ~11px), текст чуть выше центра
        local ROW_H, GAP = 29, 4 -- [v73] по скрину gamesense: плашка 29px, между ними 4px (было 34 / 7)
        local KL = { Enabled = true, Items = {}, Order = {}, Count = 0, Status = {} }
        self.KeybindList = KL
        local holder = Create("Frame", { Name = "Indicators", Position = UDim2.new(0, 0, 0.6, 0), Size = UDim2.fromOffset(220, ROW_H),
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
                { it.Box, it.BoxProp, 0.45 + 0.55 * a }, -- [v52] тёмная полоса gamesense
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
            -- [v52] как у gamesense: тёмная полоса от самого края экрана, справа растворяется; иконка + крупный жирный текст
            local box = Create("Frame", { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(0, ROW_H), AutomaticSize = AX,
                BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 41, Parent = row })
            local boxProp = "BackgroundTransparency"
            Create("UIGradient", { Transparency = NumberSequence.new({
                -- [v59] растворяется с обеих сторон (раньше слева резкий край)
                -- [v73] плашка по размеру содержимого (как у gamesense): поля 12 / 14, растворение только на них
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.15), NumberSequenceKeypoint.new(0.82, 0.15), NumberSequenceKeypoint.new(1, 1),
            }), Parent = box })
            Pad(box, 12, 14, 0, 0) -- [v73] было 34 / 34
            List(box, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
            local slot = Create("Frame", { Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 42, Parent = box })
            local T = Toggles[idx]
            local sinfo = KL.Status[idx]
            -- [v72] иконки как у gamesense: прицел -> HC, щит (парри) -> таймер, бег -> ботинок, SLOW -> треугольник
            local IND = { kb_target = "ind_md", kb_shield = "ind_timer", kb_run = "ind_shoe", kb_warn = "ind_warn" } -- [v85] прицел -> MD (скрин)
            local iname = (sinfo and sinfo.Icon) or (T and T.BindIcon) or "kb_key"
            local icon = Icon(slot, IND[iname] or iname, nil, 18, true) -- [v73] 18 (было 20)
            icon.ZIndex = 42
            local label = Text({ Text = "", TextSize = 21, FontFace = F(W_BOLD), ColorKey = false, Size = UDim2.fromOffset(0, ROW_H), -- [v73] 21
                AutomaticSize = AX, LayoutOrder = 2, ZIndex = 42, Parent = box })
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            bar.Visible = false -- [v50] у gamesense нет цветной полоски слева: иконка + жирный текст на тёмной подложке
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
                local txt = sinfo and tostring(sinfo.Text) or Library:ShortName(T and T.Text or idx) -- [v72] сокращения, как у gamesense
                if it.Label.Text ~= txt then it.Label.Text = txt end
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
            hintStroke.Transparency = 1 -- [v52] без рамки-подсказки (у gamesense её нет)
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

        -- [v52] окно Hotkeys убрано (по просьбе): у gamesense его нет, остались только индикаторы слева
        self.HotkeyList = nil

        ------------------------------------------------ общее
        function KL:Serialize()
            return { enabled = KL.Enabled, color = Library.KeybindColor:ToHex(), ind = PosOf(holder) }
        end
        function KL:Load(d)
            if type(d) ~= "table" then return end
            if type(d.enabled) == "boolean" then KL.Enabled = d.enabled end
            if type(d.color) == "string" then pcall(function() Library.KeybindColor = Color3.fromHex(d.color) end) end
            SetPos(holder, d.ind)
            KL:Refresh()
        end

        local acc = 0
        Connect(RunService.Heartbeat, function(dt)
            acc += dt or 0
            if acc < 0.1 then return end
            acc = 0
            KL:Refresh()
        end)
        KL:Refresh()
        return KL
    end

    function Library:CreateWatermark(info)
        info = info or {}
        if self.WatermarkObj then return self.WatermarkObj end
        self:LoadBindFonts() -- [v52] Noto Sans SemiBold для ватермарки (как у gamesense CS2)
        local WM = {
            Enabled = true, AltColor = Color3.fromRGB(240, 160, 130),
            -- [v50] как у gamesense: без аватара
            Items = { Logo = true, Framerate = true, Latency = true, Username = true, Time = true, Avatar = false },
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
        -- [v50] ватермарка gamesense (CS2): без плашки и иконок - тёмная полупрозрачная полоса,
        -- слева растворяется; текст жирный с тенью, «visuals» + «hub» акцентом (как game + sense)
        -- [v52] полоса до самого края экрана (раньше обрывалась за 6px до него), справа поле 12
        local PADL, GAP, ICON_W, AV, PADR = 22, 14, 0, 16, 34 -- [v59] справа поле под растворение
        local bar = Button({
            Name = "Watermark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4 - insetY),
            Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 0.35, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 40, Parent = ScreenGui,
        })
        Create("UIGradient", { Transparency = NumberSequence.new({
            -- [v59] растворяется с обеих сторон (раньше справа обрывалась у края экрана)
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.25), NumberSequenceKeypoint.new(0.88, 0.25), NumberSequenceKeypoint.new(1, 1),
        }), Parent = bar })
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
                -- [v50] «visuals» + «hub» акцентом, без бейджа (у gamesense: game + sense)
                C.Pre = 0
                C.Label = Text({ Text = "", TextSize = 13, FontFace = BindFont(W_SEMI), ColorKey = false, TextStrokeTransparency = 0.6,
                    Size = UDim2.new(1, 0, 1, 0), Parent = cell })
                C.Accent = Text({ Text = "", TextSize = 13, FontFace = BindFont(W_SEMI), ColorKey = false, TextStrokeTransparency = 0.6,
                    Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Parent = cell })
            else
                local holder = Create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12),
                    BackgroundTransparency = 1, Visible = false, Parent = cell }) -- [v50] иконок у gamesense нет
                C.Icon = Icon(holder, it.Icon, nil, 12, true)
                C.Label = Text({ Text = "", TextSize = 13, FontFace = BindFont(W_SEMI), ColorKey = false, TextStrokeTransparency = 0.6,
                    Position = UDim2.fromOffset(ICON_W, 0), Size = UDim2.new(1, -ICON_W, 1, 0), Parent = cell })
                -- [v52] единица мелкими капителями после значения («25 PING»), светло-серая
                C.Unit = Text({ Text = "", TextSize = 10, FontFace = BindFont(W_SEMI), ColorKey = false, TextStrokeTransparency = 0.6,
                    TextColor3 = Color3.fromRGB(165, 165, 165), Size = UDim2.fromScale(0, 1), AutomaticSize = AX, Position = UDim2.fromOffset(0, 1), Parent = cell })
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
            if key == "Username" then return Library.NameOverride or (Library.StreamerMode and "user" or LP.Name) end -- [v71] Streamer mode, [v91] ник анонимайзера
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
            return math.ceil((C.Icon and ICON_W or 0) + (C.Pre or 0) + textW(C.Label) + (C.Accent and textW(C.Accent) or 0)
                + ((C.Unit and C.Unit.Text ~= "") and (3 + textW(C.Unit)) or 0))
        end
        local function measure(C)
            if C.Fixed then C.W = C.Fixed return end
            C.Measure.Text = (string.gsub(tostring(C.Label.Text), "%d", "0"))
            local extra = 0
            if C.Accent then -- [v50] акцентная часть логотипа сразу за основной
                local lw = textW(C.Label)
                C.Accent.Position = UDim2.fromOffset(math.floor(lw + 0.5), 0)
                extra = textW(C.Accent)
            end
            if C.Unit and C.Unit.Text ~= "" then -- [v52] единица за значением (по «линейке», чтобы не дёргалась)
                local lw = math.max(textW(C.Label), textW(C.Measure))
                C.Unit.Position = UDim2.fromOffset(math.floor(lw + 3.5), 1)
                extra = 3 + textW(C.Unit)
            end
            local want = math.ceil((C.Icon and ICON_W or 0) + (C.Pre or 0) + math.max(textW(C.Label), textW(C.Measure)) + extra)
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
            if C.Unit then
                if now then C.Unit.TextTransparency = t else Anim(C.Unit, 0.15, { TextTransparency = t }) end
            end
            if C.Accent then
                if now then C.Accent.TextTransparency = t else Anim(C.Accent, 0.15, { TextTransparency = t }) end
            end
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
            x += (last == "Avatar" and 4 or PADR) - GAP
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
                        -- [v50] «Visuals Hub» -> «visuals» + «hub» (последнее слово акцентом), как «gamesense»
                        local t = string.lower(tostring(self.Title))
                        local head, tail = string.match(t, "^(.-)%s*(%S+)$")
                        if t == "gamesense" then head, tail = "game", "sense" end -- [v72]
                        if not head or head == "" then head, tail = string.sub(t, 1, math.ceil(#t / 2)), string.sub(t, math.ceil(#t / 2) + 1) end
                        C.Label.Text, C.Accent.Text = head, tail
                        C.Label.TextColor3 = Color3.fromRGB(200, 200, 200)
                        C.Accent.TextColor3 = Scheme.AccentColor
                        for _, l in ipairs({ C.Label, C.Accent }) do
                            local ff = BindFont(W_SEMI) if l.FontFace ~= ff then l.FontFace = ff end -- шрифт догружается
                        end
                    else
                        local warn = WM_WARN[it.Key] and WM_WARN[it.Key](v[it.Key] or 0)
                        -- [v52] «53 MS» -> значение «53» + единица «PING» мелкими капителями (как у gamesense)
                        local txt = fmt(it.Key, v)
                        local val, unit = string.match(txt, "^([%d%.%%]+) (%u+)$")
                        if it.Key == "Latency" and unit then unit = "PING" end
                        C.Label.Text = val or txt
                        C.Unit.Text = unit or ""
                        -- пинг - акцентом, как «25» на скрине; остальное светлое; плохое значение - Additional Color
                        -- [v72] как у gamesense: все числа акцентом (199 FPS, 28% CPU ...), единицы светлые; время - белым
                        local numeric = val ~= nil and it.Key ~= "Time"
                        C.Label.TextColor3 = warn and self.AltColor or (numeric and Scheme.AccentColor or Color3.fromRGB(225, 225, 225))
                        if C.Unit then C.Unit.TextColor3 = Color3.fromRGB(225, 225, 225) end
                        for _, l in ipairs({ C.Label, C.Unit }) do
                            local ff = BindFont(W_SEMI) if l.FontFace ~= ff then l.FontFace = ff end
                        end
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

    -- [v71] сбор / применение значений вынесены (нужны для Reset и Import / Export)
    function SaveManager:_Collect()
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
        for idx, o in pairs(self.Pending or {}) do -- [v72]
            if not (Toggles[idx] or Options[idx]) then table.insert(objects, o) end
        end
        return objects
    end

    function SaveManager:_Apply(data)
        Library:ClearBinds() -- БИНДЫ: у каждого конфига свои
        local binds = {}
        for _, o in ipairs(data.objects or {}) do
            local idx = o.idx
            if idx and not self:_Ignored(idx) then
                if o.type == "Bind" then
                    table.insert(binds, o)
                elseif o.type == "Toggle" then
                    if Toggles[idx] then Toggles[idx]:SetValue(o.value) elseif string.sub(idx, 1, 4) == "Lua_" then self.Pending[idx] = o end -- [v72]
                else
                    local el = Options[idx]
                    if not el and string.sub(idx, 1, 4) == "Lua_" then self.Pending[idx] = o end -- [v72] UI Lua-скрипта, он ещё не загружен
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
    end

    -- [v72] значения элементов, которых сейчас нет (UI Lua-скриптов): применяются, когда скрипт их создаст,
    -- и попадают в сохранение, пока скрипт выгружен
    SaveManager.Pending = {}
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

    function SaveManager:Save(name)
        if not HasFS() then return false, "executor has no file functions" end
        name = tostring(name or "")
        if name:gsub("%s", "") == "" then return false, "empty config name" end
        local ok, encoded = pcall(function() return HttpService:JSONEncode({ objects = self:_Collect() }) end)
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
        self:_Apply(data)
        self.Current = name
        if Library.Window then Library.Window:SetConfigName(name) end
        return true
    end

    -- [v71] Reset: все настройки как при запуске скрипта (снимок до автозагрузки)
    function SaveManager:Reset()
        if not self.Defaults then return false, "no defaults" end
        self:_Apply({ objects = self.Defaults })
        return true
    end
    -- [v71] Export / Import через буфер обмена (JSON того же вида, что файл конфига)
    function SaveManager:Export()
        local ok, encoded = pcall(function() return HttpService:JSONEncode({ objects = self:_Collect() }) end)
        if not ok then return false, "failed to encode data" end
        local clip = setclipboard or toclipboard or (Clipboard and Clipboard.set)
        if not clip then return false, "executor has no setclipboard" end
        local cok, cerr = pcall(clip, encoded)
        if not cok then return false, tostring(cerr) end
        return true
    end
    function SaveManager:Import(fallbackText)
        local text = nil
        local get = getclipboard or fromclipboard
        if get then pcall(function() text = get() end) end
        if type(text) ~= "string" or not string.find(text, "objects", 1, true) then text = fallbackText end
        if type(text) ~= "string" or text == "" then return false, "clipboard is empty (or paste the config into the name field)" end
        local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
        if not ok or type(data) ~= "table" or type(data.objects) ~= "table" then return false, "not a config" end
        self:_Apply(data)
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

    -- [v71] как «Presets» у skeet (вкладка конфига): список, поле имени с крестиком и кнопки
    -- Load / Save / Delete / Reset / Import from clipboard / Export to clipboard
    function SaveManager:BuildConfigSection(tab)
        local box = tab:AddLeftGroupbox("Presets")
        local function notify(text) Library:Notify({ Title = "Config", Description = text, Time = 4 }) end
        self.Defaults = self.Defaults or self:_Collect()
        local lb = box:AddListbox("SaveManager_ConfigList", { Rows = 7, Values = function() return self:List() end })
        local input = box:AddInput("SaveManager_ConfigName", { Placeholder = "name", Clear = true })
        lb:OnChanged(function(v) if v and input.Value ~= v then input:SetValue(v) end end)
        local function pick()
            local n = tostring(input.Value or "")
            if n:gsub("%s", "") == "" then n = lb.Value end
            return n
        end
        local function refresh(sel)
            lb:SetValues(self:List())
            if sel ~= nil then lb:SetValue(sel) end
            if self.AutoDD then self.AutoDD:SetValues(self:AutoValues()) end
        end
        self.RefreshList = refresh
        box:AddButton({ Text = "Load", Confirm = true, Func = function()
            local n = pick()
            local ok, err = self:Load(n)
            notify(ok and ("Loaded " .. tostring(n)) or ("Failed to load: " .. tostring(err)))
        end })
        box:AddButton({ Text = "Save", Func = function()
            local n = pick()
            local ok, err = self:Save(n)
            if not ok then return notify("Failed to save: " .. tostring(err)) end
            notify("Saved " .. n)
            refresh(n)
        end })
        box:AddButton({ Text = "Delete", Confirm = true, Func = function()
            local n = pick()
            local ok, err = self:Delete(n)
            if not ok then return notify("Failed to delete: " .. tostring(err)) end
            notify("Deleted " .. tostring(n))
            input:SetValue("")
            lb.Value = nil
            refresh(nil)
        end })
        box:AddButton({ Text = "Reset", Confirm = true, Func = function()
            local ok, err = self:Reset()
            notify(ok and "Settings reset to defaults" or ("Failed to reset: " .. tostring(err)))
        end })
        box:AddButton({ Text = "Import from clipboard", Confirm = true, Func = function()
            local ok, err = self:Import(input.Value)
            notify(ok and "Imported config from clipboard" or ("Failed to import: " .. tostring(err)))
        end })
        box:AddButton({ Text = "Export to clipboard", Func = function()
            local ok, err = self:Export()
            notify(ok and "Config copied to clipboard" or ("Failed to export: " .. tostring(err)))
        end })

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

    -- [v71] автозагрузка - выпадающий список в Settings (у skeet её нет, у нас - вместо кнопок)
    function SaveManager:AutoValues()
        local v = { "None" }
        for _, n in ipairs(self:List()) do v[#v + 1] = n end
        return v
    end
    function SaveManager:BuildAutoload(box)
        local dd = box:AddDropdown("SaveManager_Autoload", { Text = "Autoload preset", Values = self:AutoValues(),
            Default = self:GetAutoload() or "None", Tooltip = "Preset loaded automatically when the script starts." })
        self.AutoDD = dd
        dd:OnChanged(function(v)
            if not HasFS() then return end
            if v == nil or v == "None" then
                if delfile and isfile(self:_AutoloadPath()) then pcall(delfile, self:_AutoloadPath()) end
            else
                pcall(writefile, self:_AutoloadPath(), tostring(v))
            end
        end)
        return dd
    end

    --------------------------------------------------------
    -- ThemeManager (акцент + фон, сохраняется отдельно от конфигов)
    --------------------------------------------------------
    local ThemeManager = { Folder = "NeverUI" }
    function ThemeManager:SetLibrary(lib) self.Library = lib end
    function ThemeManager:SetFolder(folder) self.Folder = folder end
    -- [v49] свой файл: старый theme.json от NeverUI (тема Neverlose, фон 0A0A0E, синий акцент)
    -- подхватывался новым меню и перекрашивал всё в NL. Теперь у skeet-меню отдельный файл.
    function ThemeManager:_Path() return self.Folder .. "/theme_skeet.json" end

    function ThemeManager:Save()
        if not HasFS() then return end
        pcall(function()
            if not isfolder(self.Folder) then makefolder(self.Folder) end
            writefile(self:_Path(), HttpService:JSONEncode({
                accent = Scheme.AccentColor:ToHex(), main = Scheme.MainColor:ToHex(),
                anim = Library.Animations, theme = Library.ThemeName,
                menuScale = Library.MenuScale, espScale = Library.ESPScale, units = Library.Units,
                animSpeed = Library.AnimSpeed, confirm = Library.Confirmations, streamer = Library.StreamerMode, -- [v71]
                dpi = Options.ThemeManager_DPI and Options.ThemeManager_DPI.Value or nil,
                menuW = Library.MenuSize and Library.MenuSize.W or nil, menuH = Library.MenuSize and Library.MenuSize.H or nil, -- [v51]
                transparency = Library.Transparency, blur = Library.Blur, glow = Library.Glow,
                wm = Library.WatermarkObj and Library.WatermarkObj:Serialize() or nil,
                kb = Library.KeybindList and Library.KeybindList:Serialize() or nil,
                hl = Library.HitLogObj and Library.HitLogObj:Serialize() or nil, -- [v72] позиция хит-логов
                hud = (function() -- [v75] позиции HUD-панелей
                    local t = {}
                    for k, p in pairs(Library.HudPanels or {}) do t[k] = p:Serialize() end
                    for k, v in pairs(Library._HudPending or {}) do if not t[k] then t[k] = v end end
                    return t
                end)(),
            }))
        end)
    end

    -- [v71] как «Settings» у skeet (вкладка конфига): Menu color, Menu animation speed, Menu confirmations,
    -- DPI scale, Streamer mode. Сохраняются в theme_skeet.json (не в пресетах).
    local DPI = { Automatic = 1, ["75%"] = 0.75, ["100%"] = 1, ["125%"] = 1.25, ["150%"] = 1.5, ["200%"] = 2 }
    function ThemeManager:BuildMenuSettings(box)
        box:AddLabel("Menu color"):AddColorPicker("ThemeManager_Accent", { Default = Scheme.AccentColor, Title = "Menu color" })
        box:AddSlider("ThemeManager_AnimSpeed", { Text = "Menu animation speed", Default = math.floor((Library.AnimSpeed or 1) * 100 + 0.5),
            Min = 25, Max = 300, Rounding = 0, Suffix = "%", Callback = function(v)
                Library.AnimSpeed = math.clamp((tonumber(v) or 100) / 100, 0.25, 3)
                if Library._ThemeSave then Library._ThemeSave() end
            end })
        box:AddCheckbox("ThemeManager_Confirm", { Text = "Menu confirmations", Default = Library.Confirmations ~= false, NoBind = true,
            Tooltip = "Load / Delete / Reset / Import ask 'Are you sure?' first (click again to confirm).", Callback = function(v)
                Library.Confirmations = v and true or false
                if Library._ThemeSave then Library._ThemeSave() end
            end })
        box:AddDropdown("ThemeManager_DPI", { Text = "DPI scale", Values = { "Automatic", "75%", "100%", "125%", "150%", "200%" },
            Default = "Automatic", Callback = function(v)
                local k = DPI[v]
                if k and Library.SetMenuScale then Library:SetMenuScale(k) end
                if Options.ThemeManager_MenuScale and k then pcall(function() Options.ThemeManager_MenuScale:SetValue(k * 100) end) end
            end })
        box:AddCheckbox("ThemeManager_Streamer", { Text = "Streamer mode", Default = Library.StreamerMode == true, NoBind = true,
            Tooltip = "Hides player names in ESP and your name in the watermark.", Callback = function(v)
                Library.StreamerMode = v and true or false
                if Library._ThemeSave then Library._ThemeSave() end
            end })
    end

    function ThemeManager:ApplyToTab(tab)
        -- [v60] переехало в Misc (справа) и разделено: Theme - вид меню, Interface - ватермарка / индикаторы / ESP
        -- [v73] групбокс Theme убран (есть Menu color в Config): элементы живут в скрытой группе, чтобы не ломать сохранение
        local box = DetachedGroup()
        local themeBox = box
        local names = {}
        for _, t in ipairs(Library.Themes) do names[#names + 1] = t.Name end
        box:AddDropdown("ThemeManager_Theme", { Text = "Theme", Values = names, Default = Library.ThemeName,
            Tooltip = "Menu color theme. Accent / background below can still be tweaked on top of it.",
            Callback = function(v)
                if Library._ApplyingTheme or not v then return end
                Library:ApplyTheme(v)
            end })
        if not Options.ThemeManager_Accent then -- [v71] обычно уже есть: Menu color в Config -> Settings
            box:AddLabel("Accent color"):AddColorPicker("ThemeManager_Accent", { Default = Scheme.AccentColor, Title = "Accent color" })
        end
        box:AddLabel("Background"):AddColorPicker("ThemeManager_Main", { Default = Scheme.MainColor, Title = "Background" })
        local loading = false
        -- АНИМАЦИЯ: выключатель всех анимаций меню (сохраняется в theme.json)
        box:AddToggle("ThemeManager_Animations", { Text = "Animations", Default = Library.Animations, Callback = function(v)
            Library.Animations = v and true or false
            if not loading then self:Save() end
        end })
        -- ЭФФЕКТЫ (по умолчанию - как замерено на видео)
        box:AddSlider("ThemeManager_Transparency", {
            Text = "Menu transparency", Default = math.floor(Library.Transparency * 100 + 0.5), Min = 0, Max = 40,
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
        -- [v48] Glow убран: у skeet нет свечения элементов
        -- [v49] бывший попап профиля NL: масштаб меню / ESP и единицы - обычными элементами
        -- [v71] масштаб меню теперь - DPI scale в Config -> Settings; ползунок остаётся скрытым (значение, сохранение)
        DetachedGroup():AddSlider("ThemeManager_MenuScale", { Text = "Menu scale", Default = math.floor((Library.MenuScale or 1) * 100 + 0.5),
            Min = 50, Max = 150, Rounding = 0, Suffix = "%", Callback = function(v)
                if Library.SetMenuScale and math.abs((Library.MenuScale or 1) * 100 - v) > 0.5 then Library:SetMenuScale(v / 100) end
            end })
        box = tab:AddRightGroupbox("Interface") -- [v60]
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
        Library:CreateHitLog() -- [v72] хит-логи (позиция грузится из темы)
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

        -- [v60] масштаб ESP и единицы - после ватермарки / индикаторов
        box:AddSlider("ThemeManager_ESPScale", { Text = "ESP scale", Default = math.floor((Library.ESPScale or 1) * 100 + 0.5),
            Min = 50, Max = 200, Rounding = 0, Suffix = "%", Callback = function(v)
                Library.ESPScale = v / 100
                if not loading then self:Save() end
            end })
        box:AddDropdown("ThemeManager_Units", { Text = "Distance units", Values = { "studs", "meters" }, Default = Library.Units or "studs",
            Callback = function(v)
                if v == "studs" or v == "meters" then Library.Units = v end
                if not loading then self:Save() end
            end })

        -- фон задаёт всю тёмную гамму; остальные оттенки - сдвиг яркости, как в исходной палитре
        -- [v48] сдвиги от палитры skeet (фон 16): колонка 11, групбокс 23, рамка 40, поля 33, слайдер 52
        local SHIFT = {
            BackgroundColor = -0.020, GroupColor = 0.027, OutlineColor = 0.094, SeparatorColor = 0.055,
            ItemColor = 0.067, InputColor = 0.067, InputBorder = -0.031, TrackColor = 0.141, OffTrack = 0.173,
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

        themeBox:AddButton({ Text = "Reset theme", Func = function() -- [v60] в своём групбоксе
            Library:ApplyTheme(Library.ThemeName or "Default") -- сброс правок акцента/фона к выбранной теме
            self:Save()
        end })

        if HasFS() and isfile(self:_Path()) then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(self:_Path())) end)
            if ok and type(data) == "table" then
                loading = true
                -- [v45] сначала тема, поверх - свои правки акцента / фона (если отличаются от темы)
                -- [v73] темы убраны из меню: сохранённую тему / фон / прозрачность / blur не применяем (их больше не поменять)
                data.theme, data.main, data.transparency, data.blur = nil, nil, nil, nil
                local th = type(data.theme) == "string" and Library:GetTheme(data.theme)
                if th then pcall(function() Library:ApplyTheme(th.Name) end) end
                local themeMain = th and th.Scheme.MainColor:ToHex() or nil
                local themeAccent = th and th.Scheme.AccentColor:ToHex() or nil
                if type(data.accent) == "string" and string.lower(data.accent) == "87b535" then data.accent = nil end -- [v57] старый дефолт
                if type(data.accent) == "string" and string.lower(data.accent) ~= string.lower(themeAccent or "") then
                    pcall(function() Options.ThemeManager_Accent:SetValueRGB(Color3.fromHex(data.accent)) end)
                end
                if type(data.main) == "string" and string.lower(data.main) ~= string.lower(themeMain or "") then
                    pcall(function() Options.ThemeManager_Main:SetValueRGB(Color3.fromHex(data.main)) end)
                end
                if type(data.anim) == "boolean" then pcall(function() Toggles.ThemeManager_Animations:SetValue(data.anim) end) end
                if type(data.transparency) == "number" then pcall(function() Options.ThemeManager_Transparency:SetValue(data.transparency * 100) end) end
                if type(data.blur) == "boolean" then pcall(function() Toggles.ThemeManager_Blur:SetValue(data.blur) end) end
                if type(data.menuScale) == "number" and Library.SetMenuScale then pcall(function() Library:SetMenuScale(data.menuScale) end) end
                -- [v71] настройки меню (Config -> Settings)
                if type(data.animSpeed) == "number" and Options.ThemeManager_AnimSpeed then pcall(function() Options.ThemeManager_AnimSpeed:SetValue(data.animSpeed * 100) end) end
                if type(data.confirm) == "boolean" and Toggles.ThemeManager_Confirm then pcall(function() Toggles.ThemeManager_Confirm:SetValue(data.confirm) end) end
                if type(data.streamer) == "boolean" and Toggles.ThemeManager_Streamer then pcall(function() Toggles.ThemeManager_Streamer:SetValue(data.streamer) end) end
                if type(data.dpi) == "string" and Options.ThemeManager_DPI and DPI[data.dpi] then
                    pcall(function() Options.ThemeManager_DPI.Value = data.dpi Options.ThemeManager_DPI:Display() end)
                end
                if type(data.espScale) == "number" then Library.ESPScale = math.clamp(data.espScale, 0.5, 2) end
                if type(data.menuW) == "number" and type(data.menuH) == "number" and Library.SetMenuSize then -- [v51] размер окна
                    pcall(function() Library:SetMenuSize(data.menuW, data.menuH) end)
                end
                if data.units == "studs" or data.units == "meters" then Library.Units = data.units end
                -- [v49] показать загруженное в элементах
                pcall(function() Options.ThemeManager_MenuScale:SetValue((Library.MenuScale or 1) * 100) end)
                pcall(function() Options.ThemeManager_ESPScale:SetValue((Library.ESPScale or 1) * 100) end)
                pcall(function() Options.ThemeManager_Units:SetValue(Library.Units) end)
                if type(data.hl) == "table" and Library.HitLogObj then pcall(function() Library.HitLogObj:Load(data.hl) end) end -- [v72]
                if type(data.hud) == "table" then -- [v75]
                    Library._HudPending = data.hud
                    for k, d in pairs(data.hud) do if Library.HudPanels[k] then pcall(function() Library.HudPanels[k]:Load(d) end) end end
                end
                if type(data.kb) == "table" then
                    pcall(function() kl:Load(data.kb) end)
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

    return Library, ThemeManager, SaveManager
end)()
