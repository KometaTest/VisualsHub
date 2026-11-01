"""[v93] Из src/SkeetUI.lua делает:
  lib/SkeetUI.lua      - отдельная библиотека для GitHub: `return Library, ThemeManager, SaveManager`
  build/lib_remote.lua - замена встроенной библиотеки в скрипте: грузит lib/SkeetUI.lua с GitHub (raw)
Использование: split_lib.py <raw-url библиотеки>"""
import sys, re, os
url = sys.argv[1]
src = open('src/SkeetUI.lua', encoding='utf8').read()
head = 'local Library, ThemeManager, SaveManager = (function()'
tail = 'end)()'
i = src.index(head)
j = src.rstrip().rindex(tail)
comment = src[:i]
body = src[i + len(head):j]
os.makedirs('lib', exist_ok=True)
with open('lib/SkeetUI.lua', 'w', encoding='utf8', newline='\n') as f:
    f.write(comment)
    f.write('-- Загрузка: local Library, ThemeManager, SaveManager = loadstring(game:HttpGet(<raw url>))()\n')
    f.write('return (function()' + body + 'end)()\n')
remote = f'''------------------------------------------------------------
-- SkeetUI: библиотека грузится с GitHub (lib/SkeetUI.lua). Встроенная копия - в dist/VisualsHub_NL.lua.
------------------------------------------------------------
local Library, ThemeManager, SaveManager = (function()
    local url = "{url}"
    local ok, src = pcall(function() return game:HttpGet(url) end)
    if not ok or type(src) ~= "string" or src == "" then error("[VisualsHub] can't download SkeetUI: " .. tostring(src)) end
    local fn, err = loadstring(src, "=SkeetUI")
    if not fn then error("[VisualsHub] SkeetUI compile error: " .. tostring(err)) end
    return fn()
end)()
'''
with open('build/lib_remote.lua', 'w', encoding='utf8', newline='\n') as f:
    f.write(remote)
print('lib/SkeetUI.lua + build/lib_remote.lua')
