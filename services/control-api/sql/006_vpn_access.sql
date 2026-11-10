-- Self-registered Keycloak accounts start without VPN access. Preserve access
-- for accounts that already have an installed device configuration.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS display_username text;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS vpn_access_status text NOT NULL DEFAULT 'pending';
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_vpn_access_status_check') THEN
        ALTER TABLE accounts ADD CONSTRAINT accounts_vpn_access_status_check
            CHECK (vpn_access_status IN ('pending', 'approved', 'revoking', 'denied'));
    END IF;
END $$;
UPDATE accounts SET vpn_access_status='approved'
WHERE vpn_access_status='pending' AND EXISTS (
    SELECT 1 FROM devices d JOIN device_configurations c ON c.device_id=d.id
    WHERE d.account_id=accounts.id
);
CREATE INDEX IF NOT EXISTS accounts_vpn_access_status_idx ON accounts(vpn_access_status, created_at);
