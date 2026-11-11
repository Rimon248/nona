#!/bin/sh
set -eu

version=26.10.31
arm64_hash=0a05dca3bd311b0bc5a89c7ce56350cab1e829e131e4b2bcd48eb304fac07e9a
x64_hash=37c60b63c77ef5edcfb46a0d70349f7d96e0c132e6a356ead4fd20aeeacc5c75
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
engine_dir="$project_dir/Runner/engine"
scratch_dir=$(mktemp -d)
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM
mkdir -p "$engine_dir"

curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/v$version/Xray-macos-arm64-v8a.zip" \
  -o "$scratch_dir/xray-arm64.zip"
curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/v$version/Xray-macos-64.zip" \
  -o "$scratch_dir/xray-x86_64.zip"
printf '%s  %s\n' "$arm64_hash" "$scratch_dir/xray-arm64.zip" | shasum -a 256 -c -
printf '%s  %s\n' "$x64_hash" "$scratch_dir/xray-x86_64.zip" | shasum -a 256 -c -

unzip -p "$scratch_dir/xray-arm64.zip" xray > "$scratch_dir/xray-arm64"
unzip -p "$scratch_dir/xray-x86_64.zip" xray > "$scratch_dir/xray-x86_64"
unzip -p "$scratch_dir/xray-arm64.zip" LICENSE > "$engine_dir/Xray-Core-LICENSE.txt"
lipo -create "$scratch_dir/xray-arm64" "$scratch_dir/xray-x86_64" \
  -output "$engine_dir/xray"
chmod 755 "$engine_dir/xray"
codesign --force --sign - "$engine_dir/xray"

printf 'Prepared universal Xray-core %s for macOS.\n' "$version"
