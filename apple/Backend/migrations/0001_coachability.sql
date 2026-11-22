PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT NOT NULL UNIQUE,
  email_mask TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS auth_challenges (
  id TEXT PRIMARY KEY,
  nonce TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS auth_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS play_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  format TEXT NOT NULL CHECK(format IN ('tennis','tiebreak'))
);
CREATE TABLE IF NOT EXISTS coach_points (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id TEXT NOT NULL REFERENCES play_sessions(id) ON DELETE CASCADE,
  point_index INTEGER NOT NULL,
  game_index INTEGER NOT NULL,
  winner INTEGER NOT NULL CHECK(winner IN (0,1)),
  cp INTEGER NOT NULL,
  events TEXT NOT NULL,
  game_complete INTEGER NOT NULL CHECK(game_complete IN (0,1)),
  set_complete INTEGER NOT NULL CHECK(set_complete IN (0,1)),
  created_at INTEGER NOT NULL,
  UNIQUE(session_id, point_index)
);
CREATE INDEX IF NOT EXISTS coach_user ON coach_points(user_id);
CREATE INDEX IF NOT EXISTS coach_game ON coach_points(session_id, game_index);
CREATE INDEX IF NOT EXISTS auth_expiry ON auth_challenges(expires_at);
