-- [v53] иконки вкладок из открытых наборов (как у skeet): sk_icon_*
local f = FILES["VisualsHub/icons/sk_gs_world.png"] -- [v56] [v73] солнце у Visuals (прицел больше не используется)
assert(f, "icon written")
local sum = 0 for i = 1, #f do sum = (sum + string.byte(f, i)) % 65536 end
print("decoded sk_gs_world.png", #f, sum)
assert(string.sub(f, 2, 4) == "PNG", "png header")
local img
for _, d in ipairs(Tabs.Players.Nav.Item:GetDescendants()) do if d.ClassName == "ImageLabel" then img = d end end
assert(img and img.Image == "rbxasset://custom/VisualsHub/icons/sk_gs_world.png", "nav icon applied") -- [v56] [v73]
for _, n in ipairs({ "sk_gs_world", "cat_enemy", "cat_team", "cat_eye", "cat_bot", "cat_world", "sk_gs_skin", "sk_gs_survivor", "sk_gs_killer", "sk_gs_misc", "sk_gs_config" }) do -- [v56] [v57]
    assert(FILES["VisualsHub/icons/" .. n .. ".png"], n .. " written")
end
-- [v62] пиксельный шрифт ESP пишется и подключается
assert(Library:GetESPFont() ~= nil, "esp font family")
local ttf = FILES["VisualsHub/fonts/selawik-semilight.ttf"] -- [v64]
assert(ttf and #ttf == 33660 and string.sub(ttf, 1, 4) == "\0\1\0\0", "esp ttf decoded")
print("ICON TESTS PASSED")
