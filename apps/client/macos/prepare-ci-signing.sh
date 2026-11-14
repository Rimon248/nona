#!/bin/bash
set -euo pipefail

# The privileged daemon needs a stable Apple-issued signing identity.
: "${RUNNER_TEMP:?Run this only on a GitHub macOS runner}"
: "${GITHUB_ENV:?GitHub environment file is required}"
if [[ -z "${NONA_MACOS_CERT_P12_BASE64:-}" || -z "${NONA_MACOS_CERT_PASSWORD:-}" ]]; then
  echo 'Set NONA_MACOS_CERT_P12_BASE64 and NONA_MACOS_CERT_PASSWORD for the macOS helper.' >&2
  exit 1
fi
scratch=$(mktemp -d "$RUNNER_TEMP/nona-certificate.XXXXXX")
keychain="$RUNNER_TEMP/nona-signing.keychain-db"
trap 'rm -rf "$scratch"' EXIT
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"

printf '%s' "$NONA_MACOS_CERT_P12_BASE64" | base64 -D > "$scratch/signing.p12"
certificate_password=$NONA_MACOS_CERT_PASSWORD

security import "$scratch/signing.p12" -k "$keychain" \
  -P "$certificate_password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: \
  -s -k "$keychain_password" "$keychain" >/dev/null
identity=$(security find-identity -v -p codesigning "$keychain" \
  | grep -Eo '[A-F0-9]{40}' | head -n 1)
if [[ -z "$identity" ]]; then
  echo 'Imported certificate is not a valid Code Signing identity.' >&2
  exit 1
fi
{
  printf 'NONA_MACOS_SIGNING_IDENTITY=%s\n' "$identity"
  printf 'NONA_MACOS_KEYCHAIN=%s\n' "$keychain"
} >> "$GITHUB_ENV"
echo 'Prepared macOS code signing identity for the VPN helper.'
