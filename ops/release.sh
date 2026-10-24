#!/usr/bin/env bash
# Ship a build.
#
# There is no app store in the loop: the APK is handed out directly, so a
# client stays on whatever build they were last sent unless the app itself
# goes and fetches the new one. This script is the other half of that — it
# puts the builds where the config points and raises the floor, after which
# every older install is stopped at the update screen until it updates.
#
#   bash ops/release.sh 3.2.0 "What changed, in one line"
#
# The version is the one people see and the one the floor is compared against,
# so it has to go up every release.
set -euo pipefail

VERSION="${1:-}"
NOTES="${2:-}"
HOST="${CLIPCART_HOST:-clipcart-oracle}"
REMOTE_DIR="/opt/clipcart/downloads"

if [[ -z "$VERSION" ]]; then
  echo "usage: bash ops/release.sh <version> [notes]" >&2
  echo "   eg: bash ops/release.sh 3.2.0 \"Faster scrubbing\"" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The build number only has to increase; it is never compared across
# architectures (a split-per-ABI build offsets it per architecture), so it is
# derived rather than tracked by hand.
BUILD="$(date -u +%y%m%d%H)"

echo "==> version $VERSION  (build $BUILD)"
python - "$VERSION" "$BUILD" <<'PY'
import io, re, sys
v, b = sys.argv[1], sys.argv[2]
f = "app/pubspec.yaml"
s = io.open(f, encoding="utf-8").read()
s = re.sub(r"^version: .*$", f"version: {v}+{b}", s, count=1, flags=re.M)
io.open(f, "w", encoding="utf-8", newline="").write(s)
PY

echo "==> building"
( cd app && flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm )

ARM64="app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
ARM32="app/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
for f in "$ARM64" "$ARM32"; do
  [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done

# Upload beside the live files first, then move into place, so the download
# URL is never serving a half-written file.
echo "==> uploading"
# The download directory belongs to the deploy user, and we log in as another
# one, so the hop through /tmp is not ceremony - it is the only writable place
# on the way in.
scp -q "$ARM64" "$HOST:/tmp/.upload-arm64.apk"
scp -q "$ARM32" "$HOST:/tmp/.upload-arm32.apk"
# The version is in the filename, so a release is a new URL. The old one was
# a fixed name behind a CDN that caches for four hours - a client who updated
# in that window got handed the build they already had.
ssh "$HOST" "
  set -e
  cd $REMOTE_DIR
  sudo -n install -o deploy -g deploy -m 644 /tmp/.upload-arm64.apk clipcart-$VERSION.apk
  sudo -n install -o deploy -g deploy -m 644 /tmp/.upload-arm32.apk clipcart-$VERSION-arm32.apk
  rm -f /tmp/.upload-arm64.apk /tmp/.upload-arm32.apk
  ls -la clipcart-$VERSION.apk clipcart-$VERSION-arm32.apk
"

# The builds live on the server, not in git: at ~70 MB and ~105 MB a release,
# committing them would add more to the repository every month than all of its
# source has in its lifetime.
echo "==> raising the floor"
python - "$VERSION" "$NOTES" <<'PY'
import io, json, sys
v, notes = sys.argv[1], sys.argv[2]
f = "app-config.json"
d = json.load(io.open(f, encoding="utf-8"))
d["latest_version"] = v
d["min_version"] = v          # everyone older is stopped until they update
d["update_notes"] = notes
d["apk_url"] = f"https://clipscart.app/downloads/clipcart-{v}.apk"
d["apk_url_arm32"] = f"https://clipscart.app/downloads/clipcart-{v}-arm32.apk"
io.open(f, "w", encoding="utf-8", newline="\n").write(json.dumps(d, indent=2) + "\n")
PY

git add app/pubspec.yaml app-config.json
git commit -m "Release $VERSION"
git push origin main

cat <<EOF

Released $VERSION.

  arm64  https://clipscart.app/downloads/clipcart-$VERSION.apk
  arm32  https://clipscart.app/downloads/clipcart-$VERSION-arm32.apk

Every install older than $VERSION now opens on the update screen. The config
reaches phones on their next launch, so give it a minute before testing.
EOF
