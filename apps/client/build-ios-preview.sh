#!/bin/sh
set -eu

client_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
verify_key=$(tr -d '\r\n' < "$client_dir/trust/nona-config-2026-11.b64")
if ! printf '%s' "$verify_key" | LC_ALL=C grep -Eq '^[A-Za-z0-9_-]{43}$'; then
  echo 'Invalid public configuration verification key' >&2
  exit 1
fi

cd "$client_dir"
flutter pub get
flutter build ios --release --no-codesign \
  --dart-define=NONA_API_BASE_URL=https://nona.server.basketref.ru \
  --dart-define=NONA_CONFIG_KEY_ID=nona-config-2026-11 \
  "--dart-define=NONA_CONFIG_VERIFY_KEY_B64=$verify_key"
