-- Preserve old result receipts when changing the rating policy. Never recalculate
-- an already-applied match when a client reconnects or retries its result.
ALTER TABLE st_results ADD COLUMN algorithm_version INTEGER NOT NULL DEFAULT 1;
