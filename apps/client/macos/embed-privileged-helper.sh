#!/bin/sh
set -eu

client_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$client_dir/build/macos/Build/Products/Release/Nona.app"}
helper_source="$client_dir/macos/Helper/NonaPrivilegedHelper.swift"
helper_plist="$client_dir/macos/Helper/ru.basketref.nona.helper.plist"
scratch_dir=$(mktemp -d)
module_cache="$scratch_dir/module-cache"
identity=${NONA_MACOS_SIGNING_IDENTITY:--}
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

if [ ! -d "$app_path" ]; then
  echo "macOS app bundle not found: $app_path" >&2
  exit 1
fi

sdk_path=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p "$module_cache"
for arch in arm64 x86_64; do
  mkdir -p "$module_cache/$arch"
  xcrun --sdk macosx swiftc \
    -parse-as-library \
    -module-cache-path "$module_cache/$arch" \
    -sdk "$sdk_path" \
    -target "$arch-apple-macosx13.0" \
    -O \
    -framework Foundation \
    -framework Security \
    "$helper_source" \
    -o "$scratch_dir/NonaPrivilegedHelper-$arch"
done

lipo -create \
  "$scratch_dir/NonaPrivilegedHelper-arm64" \
  "$scratch_dir/NonaPrivilegedHelper-x86_64" \
  -output "$app_path/Contents/MacOS/NonaPrivilegedHelper"
chmod 755 "$app_path/Contents/MacOS/NonaPrivilegedHelper"
mkdir -p "$app_path/Contents/Library/LaunchDaemons"
cp "$helper_plist" "$app_path/Contents/Library/LaunchDaemons/ru.basketref.nona.helper.plist"

if [ "$identity" = "-" ]; then
  codesign --force --sign - "$app_path/Contents/MacOS/NonaPrivilegedHelper"
  codesign --force --deep --sign - "$app_path"
else
  if [ "${NONA_MACOS_HARDENED_RUNTIME:-0}" = "1" ]; then
    codesign --force --options runtime --timestamp --sign "$identity" \
      "$app_path/Contents/MacOS/NonaPrivilegedHelper"
    codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_path"
  else
    codesign --force --sign "$identity" "$app_path/Contents/MacOS/NonaPrivilegedHelper"
    codesign --force --deep --sign "$identity" "$app_path"
  fi
fi
codesign --verify --deep --strict "$app_path"
echo "Embedded universal Nona macOS LaunchDaemon helper in $app_path"
