#!/bin/bash
# Writes the loader manifests for the bundled Vulkan drivers into
# $WINE_PREFIX/share/vulkan/icd.d. win32u (patches/wine/0006) points
# VK_DRIVER_FILES at one of them, MoltenVK unless WINE_VK_DRIVER=kosmickrisp.
#
# library_path is relative, which the loader resolves against the manifest's
# own directory, so the prefix stays relocatable.
#
# MoltenVK's upstream manifest sets is_portability_driver, which makes the
# loader hide it from any instance that doesn't enable
# VK_KHR_portability_enumeration. Wine never does, so it's left out here.
set -euo pipefail
: "${WINE_PREFIX:?}"

icd_dir="$WINE_PREFIX/share/vulkan/icd.d"
mkdir -p "$icd_dir"

[ -f "$WINE_PREFIX/lib/libMoltenVK.dylib" ] ||
    { echo "libMoltenVK.dylib missing from $WINE_PREFIX/lib" >&2; exit 1; }
cat > "$icd_dir/moltenvk_icd.json" <<'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "../../../lib/libMoltenVK.dylib",
        "api_version": "1.2.0"
    }
}
EOF

[ -f "$WINE_PREFIX/lib/libvulkan_kosmickrisp.dylib" ] ||
    { echo "libvulkan_kosmickrisp.dylib missing from $WINE_PREFIX/lib" >&2; exit 1; }
cat > "$icd_dir/kosmickrisp_icd.json" <<'EOF'
{
    "file_format_version": "1.0.1",
    "ICD": {
        "library_path": "../../../lib/libvulkan_kosmickrisp.dylib",
        "api_version": "1.4.0"
    }
}
EOF

ls -l "$icd_dir"
