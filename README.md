# Visuals Hub — Violence District

Один скрипт, два меню на выбор: **SkeetUI** (gamesense) и **NeverUI** (Neverlose). Функции одинаковые.

## Запуск

```lua
getgenv().Key = "ваш-ключ"
getgenv().Theme = "Neverlose" -- или "Skeet" (по умолчанию)
loadstring(game:HttpGet("https://raw.githubusercontent.com/KometaTest/VisualsHub/main/dist/VisualsHub.lua"))()
```

`dist/VisualsHub.lua` проверяет ключ, качает нужную библиотеку меню (`lib/SkeetUI.lua` или `lib/NeverUI.lua`) и запускает скрипт.
Без загрузки (всё в одном файле): `dist/VisualsHub_NL.lua` — меню Skeet, `dist/VisualsHub_Neverlose.lua` — меню Neverlose.

## Ключи

`keys.txt` — по строке на ключ, в виде хэша (FNV-1a 32, hex). Сами ключи в репозиторий не попадают.

```bash
python3 tools/keygen.py            # случайный ключ, хэш добавится в keys.txt
python3 tools/keygen.py мой-ключ   # свой ключ
```

Удалить ключ — удалить его строку из `keys.txt`. Пустой или отсутствующий `keys.txt` — скрипт работает без ключа.
Проверка идёт на стороне клиента: это защита «от случайных людей», а не от того, кто разберёт скрипт.

## Сборка

```bash
bash tools/get_luau.sh   # один раз: Luau CLI в ./luau
bash build.sh            # проверки, тесты обоих меню, dist/* и lib/*
```

Адрес репозитория для ссылок — `repo.conf`.
`src/rest.lua` — весь функционал; `src/SkeetUI.lua` и `src/NeverUI.lua` — меню. В `src/NeverUI.lua` в конце есть слой
совместимости `[v94]`: всё, что скрипт ветки skeet вызывает у меню, но чего у NeverUI не было (хит-логи, HUD-панели,
Listbox, подтверждения кнопок, Pending-значения Lua-скриптов, Autoload, Streamer mode, иконки вкладок, текстуры эффектов).
