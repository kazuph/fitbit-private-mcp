-- Fitbit OAuth Tokens
CREATE TABLE oauth_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL DEFAULT 'default',
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  scope TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id)
);

-- Daily Activity Summary
CREATE TABLE daily_activity (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  steps INTEGER DEFAULT 0,
  calories_out INTEGER DEFAULT 0,
  distance REAL DEFAULT 0,
  floors INTEGER DEFAULT 0,
  sedentary_minutes INTEGER DEFAULT 0,
  lightly_active_minutes INTEGER DEFAULT 0,
  fairly_active_minutes INTEGER DEFAULT 0,
  very_active_minutes INTEGER DEFAULT 0,
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Heart Rate Data
CREATE TABLE heart_rate (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  resting_heart_rate INTEGER,
  out_of_range_minutes INTEGER DEFAULT 0,
  fat_burn_minutes INTEGER DEFAULT 0,
  cardio_minutes INTEGER DEFAULT 0,
  peak_minutes INTEGER DEFAULT 0,
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Sleep Data
CREATE TABLE sleep_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  start_time TEXT,
  end_time TEXT,
  duration_minutes INTEGER DEFAULT 0,
  efficiency INTEGER,
  deep_minutes INTEGER DEFAULT 0,
  light_minutes INTEGER DEFAULT 0,
  rem_minutes INTEGER DEFAULT 0,
  wake_minutes INTEGER DEFAULT 0,
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Weight/Body Data
CREATE TABLE weight_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  weight REAL,
  bmi REAL,
  fat_percent REAL,
  raw_data TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Daily Summary (aggregated view for dashboard)
CREATE TABLE daily_summary (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  steps INTEGER DEFAULT 0,
  calories INTEGER DEFAULT 0,
  distance REAL DEFAULT 0,
  active_minutes INTEGER DEFAULT 0,
  resting_heart_rate INTEGER,
  sleep_duration_minutes INTEGER DEFAULT 0,
  sleep_efficiency INTEGER,
  weight REAL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(date)
);

-- Indexes
CREATE INDEX idx_daily_activity_date ON daily_activity(date DESC);
CREATE INDEX idx_heart_rate_date ON heart_rate(date DESC);
CREATE INDEX idx_sleep_data_date ON sleep_data(date DESC);
CREATE INDEX idx_weight_data_date ON weight_data(date DESC);
CREATE INDEX idx_daily_summary_date ON daily_summary(date DESC);

-- Update trigger for oauth_tokens
CREATE TRIGGER oauth_tokens_updated_at
AFTER UPDATE ON oauth_tokens
BEGIN
  UPDATE oauth_tokens SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- Update trigger for daily_summary
CREATE TRIGGER daily_summary_updated_at
AFTER UPDATE ON daily_summary
BEGIN
  UPDATE daily_summary SET updated_at = datetime('now') WHERE id = NEW.id;
END;
