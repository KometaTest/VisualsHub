#!/bin/bash
# Сборка: src/head + src/SkeetUI ([v48]; было src/NeverUI) + src/hs_data + src/sky_data ([v75]) + src/rest -> build/body.lua, проверка лимита локалов,
# компиляция, 10 наборов тестов ([v78] + tests_v78) на моке, выдача dist/VisualsHub_NL.lua (CRLF).
# [v93] + lib/SkeetUI.lua, dist/VisualsHub.lua (библиотека с GitHub), loader.lua; адрес репозитория - repo.conf
# Нужен Luau CLI (luau, luau-ast, luau-compile) в ./luau или в $LUAU_DIR:
#   https://github.com/luau-lang/luau/releases -> luau-ubuntu.zip
set -e
cd "$(dirname "$0")"
export LUAU_DIR="${LUAU_DIR:-$PWD/luau}"
mkdir -p build dist
cat src/head.lua src/SkeetUI.lua src/hs_data.lua src/sky_data.lua src/rest.lua > build/body.lua
python3 tools/lcheck.py build/body.lua
"$LUAU_DIR/luau-compile" --binary build/body.lua > /dev/null
fail=0
for t in tests_icons tests_anim tests_fx tests_wm tests_amb tests_note tests_skin tests_flush tests_esp tests_v78 tests_v80 tests_v81 tests_v86; do # [v78] + tests_v78, [v80] + tests_v80, [v81] + tests_v81, [v86] + tests_v86
  if [ $t = tests_flush ]; then cat tests/mock.lua build/body.lua tests/prelude_flush.lua tests/prelude_pages.lua tests/$t.lua > build/run_$t.lua
  else cat tests/mock.lua build/body.lua tests/prelude_pages.lua tests/$t.lua > build/run_$t.lua; fi
  set +e; out=$("$LUAU_DIR/luau" build/run_$t.lua 2>&1); rc=$?; set -e
  if [ $rc -ne 0 ] || echo "$out" | grep -qi "error\|failed"; then echo "== $t FAIL"; echo "$out" | tail -8; fail=1
  else echo "== $t ok"; fi
done
[ $fail = 0 ] || exit 1
sed 's/$/\r/' build/body.lua > dist/VisualsHub_NL.lua
# [v93] GitHub: отдельная библиотека lib/SkeetUI.lua + скрипт, который её качает (dist/VisualsHub.lua) + loader.lua
REPO="OWNER/VisualsHub"; BRANCH="main"
[ -f repo.conf ] && . ./repo.conf
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
python3 tools/split_lib.py "$RAW/lib/SkeetUI.lua"
"$LUAU_DIR/luau-compile" --binary lib/SkeetUI.lua > /dev/null
cat src/head.lua build/lib_remote.lua src/hs_data.lua src/sky_data.lua src/rest.lua > build/body_remote.lua
python3 tools/lcheck.py build/body_remote.lua
"$LUAU_DIR/luau-compile" --binary build/body_remote.lua > /dev/null
# смоук-тест: скрипт с библиотекой «с GitHub» (HttpGet в моке отдаёт lib/SkeetUI.lua) проходит tests_wm
python3 - <<'PY'
lib = open('lib/SkeetUI.lua', encoding='utf8').read()
assert ']=====]' not in lib
open('build/prelude_remote.lua', 'w', encoding='utf8').write('local __LIB = [=====[' + lib + ']=====]\n'
    'game.HttpGet = function(_, url) if string.find(url, "SkeetUI", 1, true) then return __LIB end return "" end\n')
PY
cat tests/mock.lua build/prelude_remote.lua build/body_remote.lua tests/prelude_pages.lua tests/tests_wm.lua > build/run_remote.lua
"$LUAU_DIR/luau" build/run_remote.lua 2>&1 | grep -q "WM TESTS PASSED" || { echo "== remote FAIL"; exit 1; }
echo "== remote ok"
cp build/body_remote.lua dist/VisualsHub.lua
printf -- '-- VisualsHub (gamesense): запусти это в экзекуторе. Скрипт и библиотека качаются с GitHub, обновляются сами.\nloadstring(game:HttpGet("%s/dist/VisualsHub.lua"))()\n' "$RAW" > loader.lua
echo "OK -> dist/VisualsHub_NL.lua (всё в одном), dist/VisualsHub.lua + lib/SkeetUI.lua (GitHub), loader.lua"
