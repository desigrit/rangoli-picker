#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

if [[ -z "${SDKROOT:-}" ]]; then
    local_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    if [[ -d "$local_sdk" ]]; then
        export SDKROOT="$local_sdk"
    else
        export SDKROOT="$(xcrun --show-sdk-path)"
    fi
fi

export CLANG_MODULE_CACHE_PATH="$project_dir/.build/ModuleCache"
cache_path="$project_dir/.build/cache"

swift run --disable-sandbox --cache-path "$cache_path" RangCoreChecks
swift build --disable-sandbox --cache-path "$cache_path" -c release -debug-info-format none --product Rangoli
swift build --disable-sandbox --cache-path "$cache_path" -c release -debug-info-format none --product RangoliLoginLauncher
bin_path="$(swift build --disable-sandbox --cache-path "$cache_path" -c release -debug-info-format none --show-bin-path)"

app_path="$project_dir/dist/Rangoli.app"
helper_path="$app_path/Contents/Library/LoginItems/RangoliLoginLauncher.app"
artwork_path="$project_dir/.build/artwork"
swift Scripts/generate-icon.swift "$artwork_path" --package 6
iconutil --convert icns "$artwork_path/Rangoli.iconset" --output "$artwork_path/Rangoli.icns"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$helper_path/Contents/MacOS"
cp "$bin_path/Rangoli" "$app_path/Contents/MacOS/Rangoli"
cp "$bin_path/RangoliLoginLauncher" "$helper_path/Contents/MacOS/RangoliLoginLauncher"
cp "$project_dir/Packaging/Rangoli-Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Packaging/RangoliLoginLauncher-Info.plist" "$helper_path/Contents/Info.plist"
cp "$artwork_path/Rangoli.icns" "$artwork_path/RangoliMenu.png" "$artwork_path/RangoliMenu@2x.png" "$app_path/Contents/Resources/"

plutil -lint "$app_path/Contents/Info.plist" "$helper_path/Contents/Info.plist"
sign_identity="${RANG_CODESIGN_IDENTITY:--}"
codesign --force --sign "$sign_identity" --identifier com.rang.colorpicker.login "$helper_path"
codesign --force --sign "$sign_identity" --identifier com.rang.colorpicker "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
# Finder and Launch Services use the bundle's modification time for icon caching.
touch "$app_path"

echo "Built $app_path"
