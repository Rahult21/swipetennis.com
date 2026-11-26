CREATE TABLE tour_draws (pool TEXT PRIMARY KEY, code TEXT NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE tour_trophies (
  code TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL, division TEXT NOT NULL, size INTEGER NOT NULL, won_at INTEGER NOT NULL
);
CREATE INDEX trophy_owner ON tour_trophies(owner,won_at);
CREATE TABLE tour_clubs (code TEXT PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE tour_members (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  club TEXT NOT NULL REFERENCES tour_clubs(code)
);
CREATE TRIGGER remove_empty_club AFTER DELETE ON tour_members BEGIN
 DELETE FROM tour_clubs WHERE code=OLD.club AND NOT EXISTS (SELECT 1 FROM tour_members WHERE club=OLD.club);
END;
CREATE INDEX results_p0 ON st_results(player0,created_at);
CREATE INDEX results_p1 ON st_results(player1,created_at);

-- Aggregate product metrics from already-recorded play, by UTC day.
CREATE VIEW tour_engagement_daily AS
WITH activity AS (
 SELECT user_id,created_at,'practice' kind FROM coach_points
 UNION ALL SELECT player0,created_at,'tour' FROM st_results WHERE applied=1
 UNION ALL SELECT player1,created_at,'tour' FROM st_results WHERE applied=1
), daily AS (
 SELECT user_id,date(created_at/1000,'unixepoch') day,
 SUM(kind='practice') practice_points,SUM(kind='tour') human_results
 FROM activity GROUP BY user_id,day
), visits AS (
 SELECT *,MIN(day) OVER(PARTITION BY user_id) first_day FROM daily
)
SELECT day,COUNT(*) active_players,SUM(day>first_day) returning_players,
 SUM(practice_points) practice_points,SUM(human_results)/2 human_matches
FROM visits GROUP BY day;
