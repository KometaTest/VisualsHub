
-- ===== animation tests (без авто-флаша) =====
RUN_DEFERRED()
FLUSH_TWEENS()
local SG = Library.ScreenGui
local MainF = SG:FindFirstChild("Main")
local BodyF = MainF:FindFirstChild("Body")
local function fades()
    local n = 0
    for _, d in ipairs(SG:GetDescendants()) do if d.ClassName == "CanvasGroup" then n += 1 end end
    return n
end
local function inFade(obj) return obj.Parent ~= nil and obj.Parent.ClassName == "CanvasGroup" end
Library:Toggle(true) FLUSH_TWEENS()
assert(fades() == 0, "no canvas groups at rest")
assert(BodyF.Parent == MainF, "body at home")
local fit = Library._UIScale.Scale

-- [v73] World стала подвкладкой Visuals: простая вкладка в тестах - Skinchanger
-- смена вкладки: старая страница гаснет в CanvasGroup, новая ждёт
Window:SelectTab(Tabs.Players) FLUSH_TWEENS()
local oldS = Window:CurrentPage().Scroll
Window:SelectTab(Tabs.Skins)
local newS = Window:CurrentPage().Scroll
assert(inFade(oldS) and oldS.Visible, "old page fading out")
assert(not newS.Visible, "new page waits")
FLUSH_TWEENS()
assert(newS.Visible and not oldS.Visible, "new page shown after anim")
assert(not inFade(newS) and fades() == 0, "pages restored from canvas")

-- спам кликами: виден только последний
Window:SelectTab(Tabs.Misc)
Window:SelectTab(Tabs.Survivor)
Window:SelectTab(Tabs.Survivor)
FLUSH_TWEENS()
local vis = 0
for _, t in pairs(Tabs) do
    local pages = {}
    if t.Default then table.insert(pages, t.Default) end
    for _, s in ipairs(t.SubTabs or {}) do table.insert(pages, s) end -- [v73] Tabs.World - теперь подвкладка
    for _, p in ipairs(pages) do if p.Scroll.Visible then vis += 1 assert(p == Window:CurrentPage(), "wrong page visible") end end
end
assert(vis == 1, "exactly one page visible: " .. vis)
assert(fades() == 0, "no leftover canvas after spam")

-- туда-обратно: вернулись на текущую до конца анимации
local cur = Window:CurrentPage().Scroll
Window:SelectTab(Tabs.Skins)
Window:SelectTab(Tabs.Survivor)
FLUSH_TWEENS()
assert(cur.Visible and not Tabs.Skins.Default.Scroll.Visible, "back-and-forth")

-- [v48] skeet: подвкладки - полоса сверху контента (как «Weapon type»), видна только у активной вкладки
Window:SelectTab(Tabs.Skins)
FLUSH_TWEENS()
assert(Tabs.Survivor.SubBar and not Tabs.Survivor.SubBar.Visible, "subbar hidden under inactive tab")
assert(Tabs.Skins.SubBar == nil, "no subbar for tab without subtabs")
Window:SelectTab(Tabs.Survivor)
FLUSH_TWEENS()
assert(Tabs.Survivor.SubBar.Visible, "subbar shown for active tab")
local sub = Tabs.Survivor.SubTabs[1]
assert(sub.Nav and sub.Nav.Item.Parent == Tabs.Survivor.SubRow, "sub button lives in the bar")
assert(sub.Scroll.Position.Y.Offset > 0, "sub page starts below the bar")
Window:SelectTab(Tabs.Skins)
FLUSH_TWEENS()
assert(not Tabs.Survivor.SubBar.Visible, "subbar hidden again")

-- подсветка пункта
assert(Tabs.Skins.Nav.Item.BackgroundTransparency == 0, "selected nav bg")
assert(Tabs.Misc.Nav.Item.BackgroundTransparency == 1, "unselected nav bg")

-- закрытие меню: состояние сразу, окно гаснет и потом скрывается
Library:Toggle(false)
assert(Library.Toggled == false and MainF.Visible and inFade(BodyF), "closing anim")
FLUSH_TWEENS()
assert(not MainF.Visible and BodyF.Parent == MainF and fades() == 0, "closed")
assert(math.abs(Library._UIScale.Scale - fit) < 1e-9, "scale reset after close")
-- открытие
Library:Toggle(true)
assert(MainF.Visible and inFade(BodyF), "opening anim")
FLUSH_TWEENS()
assert(BodyF.Parent == MainF and math.abs(Library._UIScale.Scale - fit) < 1e-9, "opened")
-- открыть посреди закрытия
Library:Toggle(false)
Library:Toggle(true)
FLUSH_TWEENS()
assert(MainF.Visible and Library.Toggled and fades() == 0, "reopen mid-close")
-- закрыть посреди открытия
Library:Toggle(false) FLUSH_TWEENS()
Library:Toggle(true)
Library:Toggle(false)
FLUSH_TWEENS()
assert(not MainF.Visible and fades() == 0, "close mid-open")
Library:Toggle(true) FLUSH_TWEENS()

-- popup: появление/исчезновение
local popups = SG:FindFirstChild("Popups")
local cfgBtn
for _, d in ipairs(MainF:GetDescendants()) do
    if d.ClassName == "TextLabel" and d.Text == "default" then cfgBtn = d.Parent end
end
-- [v49] нижней строки с конфигом нет: popup открываем полем dropdown темы (Config -> Theme)
cfgBtn = cfgBtn or Options.ThemeManager_Theme.Row:FindFirstChildOfClass("TextButton")
FIRE(cfgBtn.MouseButton1Click)
assert(#popups:GetChildren() == 2 and popups:GetChildren()[2].ClassName == "CanvasGroup", "popup fading in")
FLUSH_TWEENS()
assert(popups:GetChildren()[2].ClassName == "TextButton", "popup restored")
Library:ClosePopup()
assert(#popups:GetChildren() == 1 and popups:GetChildren()[1].ClassName == "CanvasGroup", "popup fading out, blocker gone")
FLUSH_TWEENS()
assert(#popups:GetChildren() == 0, "popup destroyed")
-- открыть второй popup во время исчезновения первого
FIRE(cfgBtn.MouseButton1Click) FLUSH_TWEENS()
Library:ClosePopup()
FIRE(cfgBtn.MouseButton1Click)
FLUSH_TWEENS()
assert(#popups:GetChildren() == 2, "new popup alive, old one gone")
Library:ClosePopup() FLUSH_TWEENS()

-- выключатель анимаций
Toggles.ThemeManager_Animations:SetValue(false)
assert(Library.Animations == false)
Window:SelectTab(Tabs.Misc)
assert(Tabs.Misc.ActiveSub.Scroll.Visible and fades() == 0, "instant tab switch") -- [v91] у Misc подвкладки
Library:Toggle(false)
assert(not MainF.Visible, "instant close")
Library:Toggle(true)
assert(MainF.Visible and fades() == 0, "instant open")
Toggles.ThemeManager_Animations:SetValue(true)
print("tweens played:", TWEEN_COUNT)
Window:SelectTab(Tabs.Players) FLUSH_TWEENS()
print("ANIM TESTS PASSED")
