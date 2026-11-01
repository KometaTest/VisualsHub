
-- ===== notification tests =====
FLUSH_TWEENS() RUN_DEFERRED()
local SG = Library.ScreenGui
local holder
for _, c in ipairs(SG:GetChildren()) do
    if c.ClassName == "Frame" and c:FindFirstChildOfClass("UIListLayout") and c.ZIndex == 70 then holder = c end
end
assert(holder, "notify holder")
local inset = game:GetService("GuiService"):GetGuiInset()
assert(holder.AnchorPoint == Vector2.new(1, 0) and holder.Position.Y.Offset == 40 - inset.Y, "under the watermark, top-right")
local before = #holder:GetChildren()
Library:Notify({ Title = "Config", Description = "Saved config default", Time = 3 })
local wraps = {}
for _, c in ipairs(holder:GetChildren()) do if c.ClassName == "Frame" then table.insert(wraps, c) end end
local wrap = wraps[#wraps]
-- [v48] skeet: плашка 250x40, чёрная обводка, акцентная полоска слева, без бейджа и свечения
assert(wrap and wrap.Size.X.Offset == 250 and wrap.Size.Y.Offset == 40, "card 250x40")
local function find(root, pred) for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end end
assert(find(wrap, function(d) return d.ClassName == "TextLabel" and d.Text == "Config" end), "title")
assert(find(wrap, function(d) return d.ClassName == "TextLabel" and d.Text == "Saved config default" end), "description")
assert(not find(wrap, function(d) return d.Name == "FX_glow" end), "no glow")
assert(find(wrap, function(d) return d.ClassName == "Frame" and d.Size.X.Offset == 2 and d.BackgroundColor3 == Library.Scheme.AccentColor end), "accent bar")
assert(find(wrap, function(d) return d.ClassName == "TextLabel" and string.match(d.Text, "^%ds$") end), "countdown")
-- длинное описание -> две строки
Library:Notify({ Title = "Long", Description = string.rep("word ", 14), Time = 1 })
local last
for _, c in ipairs(holder:GetChildren()) do if c.ClassName == "Frame" then last = c end end
assert(last.Size.Y.Offset == 52, "two-line card")
-- только заголовок -> одна строка 24px
Library:Notify({ Title = "Short", Time = 1 })
for _, c in ipairs(holder:GetChildren()) do if c.ClassName == "Frame" then last = c end end
assert(last.Size.Y.Offset == 24, "title-only card")
-- после таймера карточки уходят
FLUSH_TWEENS() RUN_DEFERRED() FLUSH_TWEENS()
local left = 0
for _, c in ipairs(holder:GetChildren()) do if c.ClassName == "Frame" then left += 1 end end
print("notes left", left)
print("NOTE TESTS PASSED")
