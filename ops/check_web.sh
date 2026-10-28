#!/usr/bin/env bash
# Check the web studio's caption layers against the two things they must agree
# with: the server's subtitle parser (so a caption typed in the studio and one
# imported from an .srt are the same kind of object) and the shape the app's
# SubtitleSegment insists on.
#
#   bash ops/check_web.sh
#
# There is no browser here on purpose — this lifts the studio's own pure
# functions out of the page and runs them, so it tests what is deployed rather
# than a copy of it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PY="backend/.venv/Scripts/python"
[[ -x "$PY" ]] || PY="backend/.venv/bin/python"
[[ -x "$PY" ]] || PY="python"

# Written beside the repo rather than in a temp dir: on Windows the shell's
# /tmp and Python's idea of the filesystem are not the same place.
OUT="$ROOT/.server_defaults.json"
trap 'rm -f "$OUT"' EXIT
( cd backend && "../$PY" -c "
import io, json
from app.services.subtitles import _DEFAULTS
io.open('../.server_defaults.json','w').write(json.dumps(_DEFAULTS))
" )
node ops/check_web_layers.js web/index.html "$OUT"
