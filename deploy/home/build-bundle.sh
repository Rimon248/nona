#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: build-bundle.sh OUTPUT_DIRECTORY" >&2
    exit 2
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
output_dir=$1
mkdir -p "$output_dir/sql"
mkdir -p "$output_dir/keycloak"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)

(
    cd "$repo_root/services/control-api"
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$output_dir/control-api" ./cmd/api
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$output_dir/admin" ./cmd/admin
)
cp "$script_dir/compose.yaml" "$script_dir/compose.auth.yaml" "$script_dir/Dockerfile" "$script_dir/Caddyfile.nona.example" "$script_dir/Caddyfile.public.example" "$script_dir/Caddyfile.keycloak.example" "$output_dir/"
cp "$repo_root"/services/control-api/sql/*.sql "$output_dir/sql/"
cp "$script_dir"/keycloak/*.json "$output_dir/keycloak/"
chmod 0755 "$output_dir/control-api" "$output_dir/admin"
echo "Bundle ready: $output_dir"
