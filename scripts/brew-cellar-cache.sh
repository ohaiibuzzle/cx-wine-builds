#!/bin/bash
# Caches Homebrew kegs that had to be built from source (Intel macOS is
# Tier 3, so e.g. openssl@3 alone takes ~16 minutes). Bottled formulae are
# not cached: pouring them is fast.
#
#   brew-cellar-cache.sh restore DIR   re-install kegs saved in DIR
#   brew-cellar-cache.sh save DIR      snapshot source-built kegs into DIR;
#                                      prints changed=true|false for $GITHUB_OUTPUT
set -euo pipefail

cmd="${1:?restore|save}"
dir="${2:?cache directory}"
cellar="$(brew --cellar)"
opt="$(brew --prefix)/opt"

case "$cmd" in
restore)
    if [ ! -f "$dir/manifest" ]; then
        echo "No cached kegs."
        exit 0
    fi
    tar -xf "$dir/cellar.tar" -C "$cellar"
    while read -r name version keg_only; do
        echo "Restoring $name $version"
        # opt link first: `brew link` picks the keg the opt link points at
        # when several versions are installed.
        ln -sfn "../Cellar/$name/$version" "$opt/$name"
        if [ "$keg_only" = false ]; then
            brew link --overwrite "$name" >/dev/null
        fi
    done < "$dir/manifest"
    cp "$dir/manifest" "$dir/manifest.restored"
    ;;
save)
    mkdir -p "$dir"
    # One line per source-built formula: name, active version, keg-only flag.
    brew info --json=v2 --installed | python3 -c '
import json, sys
for f in json.load(sys.stdin)["formulae"]:
    if not f["installed"]:
        continue
    active = f["linked_keg"] or max(f["installed"], key=lambda k: k["time"] or 0)["version"]
    keg = next((k for k in f["installed"] if k["version"] == active), None)
    if keg and not keg["poured_from_bottle"]:
        print(f["name"], active, str(f["keg_only"]).lower())
' | sort > "$dir/manifest"

    if cmp -s "$dir/manifest" "$dir/manifest.restored" 2>/dev/null; then
        echo "changed=false"
        exit 0
    fi
    echo "Source-built kegs:" >&2
    cat "$dir/manifest" >&2
    awk '{ print $1 "/" $2 }' "$dir/manifest" | tar -cf "$dir/cellar.tar" -C "$cellar" -T -
    echo "changed=true"
    ;;
*)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
