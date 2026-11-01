-- [v94] скрипт ветки skeet с меню NeverUI: слой совместимости
assert(Library.Theme == "Neverlose", "NeverUI library")
assert(CONFIG.DisplayName == "Visuals Hub", "NL display name")
assert(Library.ESPTextK and Library.ApplyESPFont and Library.CreateHudPanel and Library.HitLogObj, "compat API")
-- иконки вкладок skeet -> NL
assert(Library:GetIcon("cat_team") == Library:GetIcon("sub_survivor"), "icon alias")
-- текстуры эффектов есть
assert(Library:GetIcon("fx_galaxy") ~= nil, "fx texture copied from SkeetUI")
-- Listbox
local tab = Window:AddTab("NLTest", "misc")
local g = tab:AddLeftGroupbox("t")
local lb = g:AddListbox("NLT_List", { Rows = 3, Values = { "a", "b" } })
local changed = 0
lb:OnChanged(function() changed += 1 end)
lb:SetValue("b")
assert(lb.Value == "b" and changed == 1, "listbox select")
lb:SetValues({ "c" })
assert(lb.Value == nil, "listbox value cleared when gone")
-- кнопка с подтверждением и SetText
local fired = 0
local b = g:AddButton({ Text = "Do", Confirm = true, Func = function() fired += 1 end })
b:SetText("Do it")
assert(b.Label.Text == "Do it", "button SetText")
-- Group:Destroy
g:Destroy()
assert(g.Holder.Parent == nil, "group destroyed")
-- HUD-панель и хит-лог
local P = Library:CreateHudPanel("nltest", "test", 100, 60)
P:SetVisible(true)
assert(P.Frame.Visible and P.Body, "hud panel")
local okP = pcall(function() Library.HitLogObj:Push({ "Hit ", { "Jason" }, " 30" }) end)
assert(okP and #Library.HitLogObj.Lines == 1, "hit log push")
-- Pending значения Lua-скриптов попадают в конфиг
SaveManager.Pending.Lua_x_Show = { type = "Toggle", idx = "Lua_x_Show", value = true }
SaveManager:Save("nltest")
local found = false
for _, o in ipairs(SaveManager.LastObjects or {}) do if o.idx == "Lua_x_Show" then found = true end end
assert(found, "pending value saved")
-- функции скрипта работают так же
Toggles.AutoParry_Enabled:SetValue(true)
assert(Toggles.AutoParry_Enabled.Value, "features")
Toggles.AutoParry_Enabled:SetValue(false)
print("NL TESTS PASSED")
