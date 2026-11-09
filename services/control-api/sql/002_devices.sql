-- Apply after 001_accounts.sql.
CREATE TABLE IF NOT EXISTS devices (
    id text PRIMARY KEY,
    account_id text NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    label text NOT NULL,
    public_key bytea NOT NULL CHECK (octet_length(public_key) = 32),
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    UNIQUE (account_id, public_key)
);

CREATE INDEX IF NOT EXISTS devices_account_id_idx ON devices(account_id);
