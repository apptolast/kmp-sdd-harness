#!/usr/bin/env bash
#
# Keeps the `android-skills` entry of .claude-plugin/marketplace.json pinned to the latest release of
# github.com/android/skills (tag + commit sha). Google tags releases vX.Y.Z; the newest one wins.
#
#   scripts/bump-android-skills.sh --check   # exit 0 if up to date, 1 if behind (prints both pins)
#   scripts/bump-android-skills.sh --apply   # rewrites ref/sha; prints the new tag, or nothing if current
#
# Overrides (tests, offline use):
#   MARKETPLACE=<path>                 marketplace.json to read and write
#   ANDROID_SKILLS_LATEST="<tag> <sha>"  skip the network lookup
#
# Exit 2 on usage or lookup errors.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="${MARKETPLACE:-$HERE/.claude-plugin/marketplace.json}"
UPSTREAM="https://github.com/android/skills"

die() { echo "error: $*" >&2; exit 2; }

MODE="${1:-}"
case "$MODE" in
  --check | --apply) ;;
  *) echo "usage: $0 --check | --apply" >&2; exit 2 ;;
esac
[ -f "$MARKETPLACE" ] || die "$MARKETPLACE not found"

current="$(python3 - "$MARKETPLACE" << 'EOF'
import json, sys
entries = [p for p in json.load(open(sys.argv[1]))["plugins"] if p["name"] == "android-skills"]
if not entries:
    sys.exit("no android-skills entry")
src = entries[0]["source"]
print(src.get("ref", ""), src.get("sha", ""))
EOF
)" || die "cannot read the android-skills entry of $MARKETPLACE"
read -r cur_tag cur_sha <<< "$current"

if [ -n "${ANDROID_SKILLS_LATEST:-}" ]; then
  read -r new_tag new_sha <<< "$ANDROID_SKILLS_LATEST"
else
  # Newest strict vX.Y.Z tag; for an annotated tag, the peeled ^{} line carries the commit sha.
  refs="$(git ls-remote --tags "$UPSTREAM" 'v*')" || die "git ls-remote $UPSTREAM failed"
  new_tag="$(printf '%s\n' "$refs" | sed -n 's#.*refs/tags/\(v[0-9]*\.[0-9]*\.[0-9]*\)$#\1#p' \
    | sort -t. -k1.2,1n -k2,2n -k3,3n | tail -1)"
  [ -n "$new_tag" ] || die "no vX.Y.Z tag found in $UPSTREAM"
  new_sha="$(printf '%s\n' "$refs" | awk -v t="refs/tags/$new_tag^{}" '$2 == t { print $1 }')"
  [ -n "$new_sha" ] || new_sha="$(printf '%s\n' "$refs" | awk -v t="refs/tags/$new_tag" '$2 == t { print $1 }')"
fi
[[ "$new_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "unexpected tag: $new_tag"
[[ "$new_sha" =~ ^[0-9a-f]{40}$ ]] || die "unexpected sha for $new_tag: $new_sha"

if [ "$MODE" = "--check" ]; then
  echo "pinned: $cur_tag $cur_sha"
  echo "latest: $new_tag $new_sha"
  if [ "$cur_tag $cur_sha" = "$new_tag $new_sha" ]; then exit 0; else exit 1; fi
fi

[ "$cur_tag $cur_sha" = "$new_tag $new_sha" ] && exit 0

python3 - "$MARKETPLACE" "$new_tag" "$new_sha" << 'EOF'
import collections, json, sys
path, tag, sha = sys.argv[1:4]
data = json.load(open(path), object_pairs_hook=collections.OrderedDict)
for plugin in data["plugins"]:
    if plugin["name"] == "android-skills":
        plugin["source"]["ref"] = tag
        plugin["source"]["sha"] = sha
with open(path, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
EOF
echo "$new_tag"
