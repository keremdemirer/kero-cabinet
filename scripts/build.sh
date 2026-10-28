#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(grep -m 1 '^  VERSION = ' "$ROOT/kero_cabinet/core.rb" | cut -d "'" -f2)"
if [[ -z "$VERSION" ]]; then
  echo 'Could not detect extension version.' >&2
  exit 1
fi

for source in "$ROOT/kero_cabinet.rb" "$ROOT/kero_cabinet/core.rb" "$ROOT/kero_cabinet/updater.rb"; do
  ruby -c "$source"
done

mkdir -p "$ROOT/dist"
cd "$ROOT"
rm -f "dist/Kero_Cabinet_v${VERSION}.rbz"
zip -q "dist/Kero_Cabinet_v${VERSION}.rbz" kero_cabinet.rb kero_cabinet/core.rb kero_cabinet/updater.rb
unzip -tq "dist/Kero_Cabinet_v${VERSION}.rbz"
echo "Built: dist/Kero_Cabinet_v${VERSION}.rbz"
