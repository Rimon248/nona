-- A durable marker is written before creating a remote VPN client. It remains
-- even if provisioning fails, so a device cannot be revoked locally while
-- its remote credentials might still be active.
CREATE TABLE IF NOT EXISTS device_remote_credentials (
    device_id text NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    node_id text NOT NULL,
    client_id text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (device_id, node_id)
);
