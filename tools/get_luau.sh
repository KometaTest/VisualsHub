#!/bin/bash
# Скачивает Luau CLI (luau, luau-ast, luau-compile) в ./luau - нужен для ./build.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p luau
curl -sSL -o luau/luau-ubuntu.zip https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip
cd luau && unzip -o -q luau-ubuntu.zip && chmod +x luau luau-ast luau-compile luau-analyze 2>/dev/null || true
echo "Luau CLI -> ./luau"
