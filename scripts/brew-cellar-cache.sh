#!/bin/bash
# Caches Homebrew kegs that had to be built from source (Intel macOS is
# Tier 3, so e.g. openssl@3 alone takes ~16 minutes). Bottled formulae are
# not cached: pouring them is fast.
#
#   brew-cellar-cache.sh restore DIR   re-install kegs saved in DIR
#   brew-cellar-cache.sh save DIR      snapshot source-built kegs into DIR;
#                                      prints changed=true|false for $GITHUB_OUTPUT
#
# restore also records what the runner image already had, so save only
# snapshots kegs this workflow built (not e.g. the image's own taps).
set -euo pipefail

cmd="${1:?restore|save}"
dir="${2:?cache directory}"
cellar="$(brew --cellar)"
prefix="$(brew --prefix)"

# Switches one restored keg in. The image may already have another version
# of the same formula linked; that has to be unlinked first, while its opt
# link still points at it, or `brew link` refuses.
restore_keg() {
    local name="$1" version="$2" keg_only="$3"
    if [ -L "$prefix/var/homebrew/linked/$name" ]; then
        brew unlink "$name" >/dev/null || return 1
    fi
    ln -sfn "../Cellar/$name/$version" "$prefix/opt/$name" || return 1
    if [ "$keg_only" = false ]; then
        brew link --overwrite "$name" >/dev/null || return 1
    fi
}

case "$cmd" in
restore)
    mkdir -p "$dir"
    brew list --versions > "$dir/baseline"
    rm -f "$dir/manifest.restored"
    if [ ! -f "$dir/manifest" ]; then
        echo "No cached kegs."
        exit 0
    fi
    tar -xf "$dir/cellar.tar" -C "$cellar"
    while read -r name version keg_only; do
        # Already on the image at this exact version: nothing to do.
        if awk -v n="$name" -v v="$version" \
            '$1 == n { for (i = 2; i <= NF; i++) if ($i == v) f = 1 } END { exit !f }' \
            "$dir/baseline"; then
            continue
        fi
        echo "Restoring $name $version"
        if ! restore_keg "$name" "$version" "$keg_only"; then
            # A half-restored keg is worse than none: brew would see it as
            # installed and never link it. Drop it so brew rebuilds it.
            echo "::warning::Could not restore $name $version; it will be rebuilt"
            rm -rf "${cellar:?}/$name/$version"
        fi
    done < "$dir/manifest"
    cp "$dir/manifest" "$dir/manifest.restored"
    ;;
save)
    # One line per source-built formula this workflow installed:
    # name, active version, keg-only flag.
    brew info --json=v2 --installed | python3 -c '
import json, sys
baseline = set()
for line in open(sys.argv[1]):
    name, *versions = line.split()
    baseline.update((name, v) for v in versions)
for f in json.load(sys.stdin)["formulae"]:
    if not f["installed"]:
        continue
    active = f["linked_keg"] or max(f["installed"], key=lambda k: k["time"] or 0)["version"]
    keg = next((k for k in f["installed"] if k["version"] == active), None)
    if keg and not keg["poured_from_bottle"] and (f["name"], active) not in baseline:
        print(f["name"], active, str(f["keg_only"]).lower())
' "$dir/baseline" | sort > "$dir/manifest.new"

    if cmp -s "$dir/manifest.new" "$dir/manifest.restored" 2>/dev/null; then
        rm "$dir/manifest.new"
        echo "changed=false"
        exit 0
    fi
    mv "$dir/manifest.new" "$dir/manifest"
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
