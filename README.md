# VisualsHub (gamesense)

Скрипт для экзекутора (Luau) под Violence District с меню **SkeetUI** (стиль skeet / gamesense).

## Запуск

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/KometaTest/VisualsHub/main/dist/VisualsHub.lua"))()
```

Это содержимое `loader.lua`. Скрипт и библиотека качаются с GitHub при каждом запуске, поэтому после пуша обновление получают все сразу.

## Что где лежит

| Путь | Что это |
|---|---|
| `dist/VisualsHub.lua` | Скрипт для GitHub: библиотеку качает отдельно из `lib/SkeetUI.lua` |
| `dist/VisualsHub_NL.lua` | Всё в одном файле (библиотека встроена), работает без GitHub |
| `lib/SkeetUI.lua` | Библиотека меню отдельно: `local Library, ThemeManager, SaveManager = loadstring(game:HttpGet(url))()` |
| `loader.lua` | Одна строка для запуска |
| `src/` | Исходники: `head.lua`, `SkeetUI.lua` (библиотека), `hs_data.lua`, `sky_data.lua`, `rest.lua` (логика) |
| `tests/` | Тесты на моке Roblox |
| `build.sh` | Сборка: склейка, проверка лимита локалов, компиляция, тесты, выдача `dist/` и `lib/` |
| `repo.conf` | Адрес репозитория (`KometaTest/VisualsHub`) и ветка: от них зависят ссылки в `dist/VisualsHub.lua` и `loader.lua` |

`dist/`, `lib/` и `loader.lua` собираются из `src/`, руками их не правь.

## Первая настройка

1. Создай **публичный** репозиторий на GitHub. Из приватного `raw.githubusercontent.com` без токена не отдаёт, и экзекутор не скачает файлы.
2. В `repo.conf` впиши свой `owner/repo` вместо `KometaTest/VisualsHub`. Если ветка не `main`, поменяй и её, а также ветку в `.github/workflows/build.yml`.
3. Собери один раз, чтобы ссылки встали на место:
   ```bash
   ./tools/get_luau.sh   # один раз: Luau CLI в ./luau
   ./build.sh
   ```
4. Залей:
   ```bash
   git init && git add -A && git commit -m "VisualsHub"
   git branch -M main
   git remote add origin https://github.com/<owner>/<repo>.git
   git push -u origin main
   ```

## Как обновлять

- **Локально:** правишь `src/`, запускаешь `./build.sh`, если тесты прошли, делаешь `git commit` и `git push`.
- **Через GitHub:** правишь `src/` прямо на сайте или пушишь без сборки. Action `build` сам соберёт, прогонит тесты и закоммитит `dist/`, `lib/`, `loader.lua`. Если тесты упадут, сборка не обновится, а ошибка будет видна во вкладке **Actions**.

После пуша новую версию получают все, у кого скрипт запускается через `loader.lua`. Raw-файлы GitHub кешируются, поэтому изменения доходят примерно за 5 минут.
