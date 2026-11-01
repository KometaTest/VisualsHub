"""[v93] Из src/<Lib>.lua делает отдельную библиотеку для GitHub: lib/<Lib>.lua (`return Library, ThemeManager, SaveManager`).
[v94] Две библиотеки (SkeetUI, NeverUI) и build/lib_remote.lua - замена встроенной библиотеки в скрипте:
проверка ключа (getgenv().Key, keys.txt в репозитории) и загрузка нужной библиотеки по getgenv().Theme.
Использование: split_lib.py <raw-url репозитория (без / в конце)>"""
import sys, os
raw = sys.argv[1]
os.makedirs('lib', exist_ok=True)
head = 'local Library, ThemeManager, SaveManager = (function()'
tail = 'end)()'
for name in ('SkeetUI', 'NeverUI'):
    src = open(f'src/{name}.lua', encoding='utf8').read()
    i = src.index(head)
    j = src.rstrip().rindex(tail)
    with open(f'lib/{name}.lua', 'w', encoding='utf8', newline='\n') as f:
        f.write(src[:i])
        f.write('-- Загрузка: local Library, ThemeManager, SaveManager = loadstring(game:HttpGet(<raw url>))()\n')
        f.write('return (function()' + src[i + len(head):j] + 'end)()\n')

remote = f'''------------------------------------------------------------
-- [v94] Загрузка с GitHub. Перед loadstring можно задать:
--   getgenv().Key   = "ключ"                    -- если в репозитории есть keys.txt (хэши ключей)
--   getgenv().Theme = "Neverlose" | "Skeet"     -- меню: NeverUI или SkeetUI (по умолчанию Skeet)
-- Встроенные копии (без загрузки): dist/VisualsHub_NL.lua (SkeetUI), dist/VisualsHub_Neverlose.lua (NeverUI).
------------------------------------------------------------
local Library, ThemeManager, SaveManager = (function()
    local RAW = "{raw}"
    local env = (getgenv and getgenv()) or _G
    local function get(path)
        local ok, res = pcall(function() return game:HttpGet(RAW .. path) end)
        if ok and type(res) == "string" then return res end
        return nil
    end
    -- ключ: FNV-1a 32 от строки ключа, сверяется со строками keys.txt (hex). Нет keys.txt / он пустой - без ключа.
    local function fnv(str)
        local h = 2166136261
        for i = 1, #str do
            h = bit32.bxor(h, string.byte(str, i))
            h = (bit32.lshift(h, 24) + h * 403) % 4294967296
        end
        return string.format("%08x", h)
    end
    local keys = get("/keys.txt")
    local list = {{}}
    if keys and not string.find(keys, "404", 1, true) then
        for line in string.gmatch(keys, "[^\\r\\n]+") do
            local hx = string.match(line, "^%s*(%x%x%x%x%x%x%x%x)%s*$")
            if hx then list[string.lower(hx)] = true end
        end
    end
    if next(list) then
        local key = tostring(env.Key or _G.Key or "")
        if key == "" or not list[fnv(key)] then
            error("[VisualsHub] invalid key. Set getgenv().Key = \\"...\\" before loadstring.", 0)
        end
    end
    local theme = string.lower(tostring(env.Theme or _G.Theme or "Skeet"))
    local name = (theme == "neverlose" or theme == "nl" or theme == "neverui") and "NeverUI" or "SkeetUI"
    local src = get("/lib/" .. name .. ".lua")
    if not src or src == "" then error("[VisualsHub] can't download " .. name, 0) end
    local fn, err = loadstring(src, "=" .. name)
    if not fn then error("[VisualsHub] " .. name .. " compile error: " .. tostring(err), 0) end
    return fn()
end)()
'''
with open('build/lib_remote.lua', 'w', encoding='utf8', newline='\n') as f:
    f.write(remote)
print('lib/SkeetUI.lua + lib/NeverUI.lua + build/lib_remote.lua')
