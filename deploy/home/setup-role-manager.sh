#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
umask 077
cfg="/tmp/nona-kcadm-role-manager-$$"
trap 'docker exec nona-identity-1 rm -f "$cfg" >/dev/null 2>&1 || true' EXIT

docker exec nona-identity-1 bash -lc "/opt/keycloak/bin/kcadm.sh config credentials --config '$cfg' --server http://127.0.0.1:8080/auth --realm master --user bootstrap-nona --password \"\$(cat /run/secrets/identity_bootstrap_password)\" >/dev/null"
kc() { docker exec nona-identity-1 /opt/keycloak/bin/kcadm.sh "$@" --config "$cfg"; }

client_id="$(kc get clients -r nona -q clientId=nona-role-manager --fields id,clientId |
    python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin) if x.get("clientId")=="nona-role-manager"]; print(a[0]["id"] if len(a)==1 else "")')"
if [ -z "$client_id" ]; then
    kc create clients -r nona -s clientId=nona-role-manager -s enabled=true -s publicClient=false \
        -s serviceAccountsEnabled=true -s standardFlowEnabled=false -s directAccessGrantsEnabled=false >/dev/null
    client_id="$(kc get clients -r nona -q clientId=nona-role-manager --fields id,clientId |
        python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin) if x.get("clientId")=="nona-role-manager"]; print(a[0]["id"] if len(a)==1 else "")')"
fi
test -n "$client_id"

service_user="$(kc get "clients/$client_id/service-account-user" -r nona |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
kc add-roles -r nona --uid "$service_user" --cclientid realm-management --rolename manage-users >/dev/null
kc add-roles -r nona --uid "$service_user" --cclientid realm-management --rolename view-realm >/dev/null
admin_scope="$(kc get client-scopes -r nona --fields id,name |
    python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin) if x.get("name")=="kc-admin-api"]; print(a[0]["id"] if len(a)==1 else "")')"
test -n "$admin_scope"
kc update "clients/$client_id/default-client-scopes/$admin_scope" -r nona -n >/dev/null

secret_file="$(pwd)/secrets/keycloak_role_manager_secret"
kc get "clients/$client_id/client-secret" -r nona |
    python3 -c 'import json,sys; value=json.load(sys.stdin)["value"]; assert value and "\n" not in value; print(value)' > "$secret_file"
chmod 600 "$secret_file"

owner_sub="$(kc get users -r nona -q username=roman --fields id,username |
    python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin) if x.get("username")=="roman"]; print(a[0]["id"] if len(a)==1 else "")')"
test -n "$owner_sub"
if [ -f .env ] && grep -q '^NONA_OWNER_SUB=' .env; then
    existing="$(sed -n 's/^NONA_OWNER_SUB=//p' .env | head -1)"
    test "$existing" = "$owner_sub"
else
    printf 'NONA_OWNER_SUB=%s\n' "$owner_sub" >> .env
fi
chmod 600 .env
echo "Keycloak role manager ready; owner subject pinned in .env"
