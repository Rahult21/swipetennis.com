CREATE TABLE IF NOT EXISTS cup_memberships (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cup_code TEXT NOT NULL,
  joined_at INTEGER NOT NULL,
  PRIMARY KEY(user_id, cup_code)
);
CREATE INDEX IF NOT EXISTS cup_membership_recent ON cup_memberships(user_id, joined_at DESC);
