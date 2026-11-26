-- Ratings are independent of Coachability and exist only for authenticated people.
CREATE TABLE st_ratings (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  points REAL NOT NULL DEFAULT 4 CHECK(points BETWEEN 1 AND 10),
  human_matches INTEGER NOT NULL DEFAULT 0 CHECK(human_matches >= 0),
  wins INTEGER NOT NULL DEFAULT 0 CHECK(wins >= 0 AND wins <= human_matches)
);
INSERT INTO st_ratings(user_id) SELECT id FROM users;

-- One receipt per played human match makes retries and reconnects idempotent.
CREATE TABLE st_results (
  id TEXT PRIMARY KEY,
  player0 TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  player1 TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  winner INTEGER NOT NULL CHECK(winner IN (0,1)),
  score0 INTEGER NOT NULL,
  score1 INTEGER NOT NULL,
  before0 REAL NOT NULL,
  before1 REAL NOT NULL,
  after0 REAL NOT NULL,
  after1 REAL NOT NULL,
  matches0 INTEGER NOT NULL,
  matches1 INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  applied INTEGER NOT NULL DEFAULT 0,
  CHECK(player0 != player1)
);
