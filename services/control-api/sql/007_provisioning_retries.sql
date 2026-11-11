-- Record only retry timing, never VPN credentials or remote error bodies.
CREATE TABLE IF NOT EXISTS device_provisioning_attempts (
    device_id text PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
    attempts integer NOT NULL CHECK (attempts BETWEEN 1 AND 1000),
    last_failed_at timestamptz NOT NULL,
    next_attempt_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS device_provisioning_attempts_due_idx
    ON device_provisioning_attempts(next_attempt_at);
