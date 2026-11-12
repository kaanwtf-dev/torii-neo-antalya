#!/bin/bash
# Makes an in-game update for Torii's Mac app (8.2+, scripts/updater.gd):
#   godot/build/torii-<ver>.pck   the whole game as one Godot pack
#   godot/build/version.json      {ver, name, pck, size, sha256, engine, notes}: what the app checks
# then prints the gh command that publishes both as GitHub Release v<ver> of kaanwtf-dev/torii-neo-antalya.
# Publishing is PUBLIC and every copy of the app sees it: run that command yourself, or pass --publish.
#
#   bash tools/publish_update.sh                      build + print the command
#   bash tools/publish_update.sh --notes "New hats!"  the one line Torii reads on the update panel
#   bash tools/publish_update.sh --publish            build + publish (asks gh to create the release)
#
# Before running: bump "ver" in godot/assets/story/godot.json (and add the patch notes), commit.
# The version number is the first number in "ver" ("ALPHA 8.3 · ..." → 8.3) and must be higher than the last release.
# The notes line defaults to "update_note" in godot.json, else the newest patch title.
# An ENGINE change (a new Godot version) can't ship as a pack: build a new app with tools/export_mac.sh instead
# (the app sees the different engine in version.json and tells her to ask you).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="kaanwtf-dev/torii-neo-antalya"
PUBLISH=0; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --publish) PUBLISH=1 ;;
    --notes) NOTES="$2"; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done

IFS=$'\t' read -r VER NAME DEFNOTES < <(python3 - <<'EOF'
import json, re
g = json.load(open("godot/assets/story/godot.json"))
name = g["ver"]
ver = re.search(r"\d+(?:\.\d+)*", name).group(0)
note = g.get("update_note") or (g.get("patches") or [{}])[0].get("t", "")
print(ver, json.dumps(name), json.dumps(note), sep="\t")
EOF
)
NAME=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]))' "$NAME")
[ -z "$NOTES" ] && NOTES=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]))' "$DEFNOTES")
PCK="torii-$VER.pck"
ENGINE=$(godot --version | grep -oE '^[0-9]+(\.[0-9]+){1,2}')

mkdir -p godot/build; touch godot/build/.gdignore      # (.gdignore: nothing in build/ ends up inside the pack)
rm -f "godot/build/$PCK" godot/build/version.json
perl -e 'alarm 600; exec @ARGV' godot --headless --path godot --import >/dev/null 2>&1 || true
perl -e 'alarm 600; exec @ARGV' godot --headless --path godot --export-pack "macOS" "build/$PCK"
[ -s "godot/build/$PCK" ] || { echo "export failed: no godot/build/$PCK"; exit 1; }

SIZE=$(stat -f%z "godot/build/$PCK")
SHA=$(shasum -a 256 "godot/build/$PCK" | cut -d' ' -f1)
python3 - "$VER" "$NAME" "$PCK" "$SIZE" "$SHA" "$ENGINE" "$NOTES" <<'EOF'
import json, sys
ver, name, pck, size, sha, engine, notes = sys.argv[1:]
json.dump({"ver": ver, "name": name, "pck": pck, "size": int(size), "sha256": sha, "engine": engine, "notes": notes},
          open("godot/build/version.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
echo "built: godot/build/$PCK ($(du -h "godot/build/$PCK" | cut -f1), engine $ENGINE)"
cat godot/build/version.json; echo

CMD=(gh release create "v$VER" "godot/build/$PCK" godot/build/version.json --repo "$REPO" --latest
     --title "$NAME" --notes "$NOTES")
echo "To publish (PUBLIC — every copy of the app will offer it):"
q() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//\$/\\\$}; s=${s//\`/\\\`}; printf ' "%s"' "$s"; }
for a in "${CMD[@]}"; do q "$a"; done; echo
if [ "$PUBLISH" = 1 ]; then
  "${CMD[@]}"
  echo "published v$VER: https://github.com/$REPO/releases/tag/v$VER"
fi
