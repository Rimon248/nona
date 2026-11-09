-- Apply once to an existing database before enabling NONA_OIDC_ISSUER.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS oidc_subject text;
CREATE UNIQUE INDEX IF NOT EXISTS accounts_oidc_subject_idx ON accounts (oidc_subject) WHERE oidc_subject IS NOT NULL;
