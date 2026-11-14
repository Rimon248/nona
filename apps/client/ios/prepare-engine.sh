#!/bin/sh
set -eu
ios_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
framework="$ios_dir/Frameworks/LibXray.xcframework"
if [ -d "$framework" ]; then exit 0; fi
archive=$(mktemp)
extract=$(mktemp -d)
trap 'rm -f "$archive"; rm -rf "$extract"' EXIT HUP INT TERM
curl -fL --retry 3 \
  https://github.com/XTLS/libXray/releases/download/v26.10.31/libxray-apple-cgo.zip \
  -o "$archive"
actual=$(shasum -a 256 "$archive" | cut -d' ' -f1)
expected=2666babc1a91d8570a49bc817487338e7a71f17618e02a601e861928d254b95a
if [ "$actual" != "$expected" ]; then
  echo 'libXray iOS archive checksum mismatch' >&2
  exit 1
fi
unzip -q "$archive" -d "$extract"
mkdir -p "$ios_dir/Frameworks"
mv "$extract/libxray-apple-cgo/LibXray.xcframework" "$framework"
