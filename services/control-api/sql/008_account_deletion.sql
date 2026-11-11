-- Deletion is a durable state until every remote VPN credential is removed.
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_vpn_access_status_check;
ALTER TABLE accounts ADD CONSTRAINT accounts_vpn_access_status_check
    CHECK (vpn_access_status IN ('pending', 'approved', 'revoking', 'denied', 'deleting'));

-- A still valid access token must not recreate an account after deletion.
CREATE TABLE IF NOT EXISTS deleted_oidc_subjects (
    oidc_subject text PRIMARY KEY,
    deleted_at timestamptz NOT NULL DEFAULT now()
);
