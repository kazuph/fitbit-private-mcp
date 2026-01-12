-- VO2max (心肺機能スコア)
CREATE TABLE vo2max_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  vo2max TEXT,  -- 範囲("44-48")または単一値("45")
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- SpO2 (血中酸素濃度)
CREATE TABLE spo2_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  avg REAL,
  min REAL,
  max REAL,
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Slack投稿状態追跡
CREATE TABLE sync_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- daily_summary にVO2max/SpO2カラム追加
ALTER TABLE daily_summary ADD COLUMN vo2max TEXT;
ALTER TABLE daily_summary ADD COLUMN spo2_avg REAL;

-- インデックス
CREATE INDEX idx_vo2max_data_date ON vo2max_data(date DESC);
CREATE INDEX idx_spo2_data_date ON spo2_data(date DESC);
