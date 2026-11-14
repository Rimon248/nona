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

sign_code() {
  if [ -n "${NONA_MACOS_KEYCHAIN:-}" ]; then
    codesign --keychain "$NONA_MACOS_KEYCHAIN" "$@"
  else
    codesign "$@"
  fi
}

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
  # Sign Flutter's nested frameworks and Xray first. --deep also re-signs the
  # helper with a generated identifier, so restore its Mach service identifier
  # before sealing the outer app bundle.
  sign_code --force --deep --preserve-metadata=entitlements --sign - "$app_path"
  sign_code --force --identifier ru.basketref.nona.helper --sign - \
    "$app_path/Contents/MacOS/NonaPrivilegedHelper"
  sign_code --force --preserve-metadata=entitlements --sign - "$app_path"
else
  if [ "${NONA_MACOS_HARDENED_RUNTIME:-0}" = "1" ]; then
    sign_code --force --deep --preserve-metadata=entitlements \
      --options runtime --timestamp --sign "$identity" "$app_path"
    sign_code --force --identifier ru.basketref.nona.helper \
      --options runtime --timestamp --sign "$identity" \
      "$app_path/Contents/MacOS/NonaPrivilegedHelper"
    sign_code --force --preserve-metadata=entitlements \
      --options runtime --timestamp --sign "$identity" "$app_path"
  else
    sign_code --force --deep --preserve-metadata=entitlements --sign "$identity" "$app_path"
    sign_code --force --identifier ru.basketref.nona.helper --sign "$identity" \
      "$app_path/Contents/MacOS/NonaPrivilegedHelper"
    sign_code --force --preserve-metadata=entitlements --sign "$identity" "$app_path"
  fi
  codesign --verify --strict \
    -R='identifier "ru.basketref.nona.helper" and anchor apple generic' \
    "$app_path/Contents/MacOS/NonaPrivilegedHelper"
  codesign --verify --strict \
    -R='identifier "ru.basketref.nona" and anchor apple generic' "$app_path"
fi
codesign --verify --strict \
  -R='identifier "ru.basketref.nona.helper"' \
  "$app_path/Contents/MacOS/NonaPrivilegedHelper"
codesign --verify --deep --strict "$app_path"
echo "Embedded universal Nona macOS LaunchDaemon helper in $app_path"
