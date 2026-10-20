#!/usr/bin/env bash
# Fetch the bible-rs public-domain .bbl translations into .sources/.
# The generated JSON in data/ is committed, so this is only needed when
# refreshing the text.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p .sources

for id in kjv web bsb asv ylt dby wbs; do
  echo "fetching $id"
  curl -fsSL -o ".sources/$id.bbl" \
    "https://raw.githubusercontent.com/michaelshimeles/bible-rs/main/data/translations/$id.bbl"
done

python3 tools/build_data.py .sources data
