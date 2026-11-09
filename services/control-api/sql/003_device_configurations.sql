-- Apply after 002_devices.sql. Only signed envelopes with encrypted credentials belong here.
CREATE TABLE IF NOT EXISTS device_configurations (
    device_id text PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    version bigint NOT NULL CHECK (version > 0),
    expires_at timestamptz NOT NULL,
    envelope text NOT NULL CHECK (octet_length(envelope) BETWEEN 1 AND 1500000),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_configurations_expires_at_idx ON device_configurations(expires_at);
