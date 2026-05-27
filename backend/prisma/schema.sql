-- IronLog PostgreSQL Schema
-- Run: psql -U ironlog -d ironlog -f schema.sql

-- ─────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- For full-text search

-- ─────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────
CREATE TYPE workout_status AS ENUM ('planned', 'inProgress', 'completed', 'skipped');
CREATE TYPE subscription_tier AS ENUM ('free', 'proMonthly', 'proYearly', 'lifetime');
CREATE TYPE program_type AS ENUM (
  'powerlifting', 'bodybuilding', 'strengthEndurance',
  'hiit', 'generalFitness', 'olympic', 'custom'
);
CREATE TYPE muscle_group AS ENUM (
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms',
  'quads', 'hamstrings', 'glutes', 'calves', 'abs', 'traps', 'lats',
  'fullBody', 'cardio'
);
CREATE TYPE equipment_type AS ENUM (
  'barbell', 'dumbbell', 'machine', 'cable', 'bodyweight',
  'kettlebell', 'bands', 'ezBar', 'trapBar', 'smith', 'other'
);

-- ─────────────────────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE users (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email             TEXT UNIQUE NOT NULL,
  password_hash     TEXT,
  display_name      TEXT,
  avatar_url        TEXT,
  bodyweight        FLOAT,
  height            FLOAT,
  date_of_birth     DATE,
  subscription      subscription_tier DEFAULT 'free',
  subscription_expiry TIMESTAMPTZ,
  revenuecat_id     TEXT,
  google_id         TEXT UNIQUE,
  apple_id          TEXT UNIQUE,
  active_program_id UUID,
  active_program_week INT DEFAULT 1,
  active_program_day  INT DEFAULT 1,
  is_public_profile   BOOLEAN DEFAULT FALSE,
  gdpr_consent_at     TIMESTAMPTZ,
  last_sync_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_users_email ON users(email);

-- ─────────────────────────────────────────────────────────────
-- EXERCISES
-- ─────────────────────────────────────────────────────────────
CREATE TABLE exercises (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              TEXT NOT NULL,
  primary_muscle    muscle_group NOT NULL,
  secondary_muscles muscle_group[] DEFAULT '{}',
  equipment         equipment_type NOT NULL,
  category          TEXT NOT NULL,   -- compound, isolation, cardio
  description       TEXT,
  video_url         TEXT,
  thumbnail_url     TEXT,
  instructions      TEXT,
  is_custom         BOOLEAN DEFAULT FALSE,
  user_id           UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  -- Full-text search
  search_vector     TSVECTOR GENERATED ALWAYS AS (
    to_tsvector('english', name || ' ' || COALESCE(description, ''))
  ) STORED
);
CREATE INDEX idx_exercises_search     ON exercises USING GIN(search_vector);
CREATE INDEX idx_exercises_muscle     ON exercises(primary_muscle);
CREATE INDEX idx_exercises_equipment  ON exercises(equipment);
CREATE INDEX idx_exercises_user       ON exercises(user_id);

-- ─────────────────────────────────────────────────────────────
-- WORKOUTS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE workouts (
  id                    UUID PRIMARY KEY,
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  status                workout_status DEFAULT 'planned',
  date                  DATE NOT NULL,
  program_id            UUID,
  program_day           INT,
  duration_seconds      INT,
  notes                 TEXT,
  bodyweight            FLOAT,
  perceived_difficulty  INT CHECK (perceived_difficulty BETWEEN 1 AND 10),
  started_at            TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  is_deleted            BOOLEAN DEFAULT FALSE,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_workouts_user_date   ON workouts(user_id, date DESC);
CREATE INDEX idx_workouts_user_status ON workouts(user_id, status);
CREATE INDEX idx_workouts_updated     ON workouts(updated_at);

-- ─────────────────────────────────────────────────────────────
-- WORKOUT EXERCISES
-- ─────────────────────────────────────────────────────────────
CREATE TABLE workout_exercises (
  id                UUID PRIMARY KEY,
  workout_id        UUID NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_id       UUID NOT NULL REFERENCES exercises(id),
  order_index       INT NOT NULL,
  rest_seconds      INT,
  notes             TEXT,
  superset_group_id TEXT
);
CREATE INDEX idx_we_workout ON workout_exercises(workout_id);

-- ─────────────────────────────────────────────────────────────
-- WORKOUT SETS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE workout_sets (
  id                    UUID PRIMARY KEY,
  workout_exercise_id   UUID NOT NULL REFERENCES workout_exercises(id) ON DELETE CASCADE,
  set_number            INT NOT NULL,
  set_type              TEXT DEFAULT 'normal',
  target_weight         FLOAT,
  target_reps           INT,
  target_rpe            FLOAT,
  target_rir            INT,
  tempo                 TEXT,
  target_duration       INT,
  logged_weight         FLOAT,
  logged_reps           INT,
  logged_rpe            FLOAT,
  completed             BOOLEAN,
  rest_seconds          INT,
  completed_at          TIMESTAMPTZ,
  notes                 TEXT,
  -- Computed for analytics
  estimated_1rm         FLOAT GENERATED ALWAYS AS (
    CASE
      WHEN logged_weight IS NOT NULL AND logged_reps > 0
      THEN logged_weight * (1 + logged_reps::float / 30)
      ELSE NULL
    END
  ) STORED,
  volume                FLOAT GENERATED ALWAYS AS (
    CASE
      WHEN logged_weight IS NOT NULL AND logged_reps IS NOT NULL
      THEN logged_weight * logged_reps
      ELSE NULL
    END
  ) STORED
);
CREATE INDEX idx_ws_exercise ON workout_sets(workout_exercise_id);

-- ─────────────────────────────────────────────────────────────
-- PERSONAL RECORDS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE personal_records (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exercise_id     UUID NOT NULL REFERENCES exercises(id),
  exercise_name   TEXT NOT NULL,
  weight          FLOAT NOT NULL,
  reps            INT NOT NULL,
  estimated_1rm   FLOAT NOT NULL,
  achieved_at     TIMESTAMPTZ NOT NULL,
  workout_id      UUID REFERENCES workouts(id)
);
CREATE UNIQUE INDEX idx_pr_user_exercise ON personal_records(user_id, exercise_id);
CREATE INDEX idx_pr_user          ON personal_records(user_id);
CREATE INDEX idx_pr_achieved      ON personal_records(achieved_at DESC);

-- ─────────────────────────────────────────────────────────────
-- PROGRAMS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE programs (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name                  TEXT NOT NULL,
  description           TEXT NOT NULL,
  type                  program_type DEFAULT 'custom',
  days_per_week         INT NOT NULL,
  duration_weeks        INT DEFAULT 0,
  author_id             UUID NOT NULL REFERENCES users(id),
  author_name           TEXT,
  progression_script    TEXT,
  is_public             BOOLEAN DEFAULT FALSE,
  is_premium            BOOLEAN DEFAULT FALSE,
  downloads             INT DEFAULT 0,
  rating                FLOAT DEFAULT 0,
  rating_count          INT DEFAULT 0,
  tags                  TEXT[],
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_programs_author  ON programs(author_id);
CREATE INDEX idx_programs_public  ON programs(is_public) WHERE is_public = TRUE;
CREATE INDEX idx_programs_rating  ON programs(rating DESC) WHERE is_public = TRUE;

CREATE TABLE program_days (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_id  UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  day_number  INT NOT NULL,
  name        TEXT NOT NULL,
  is_rest_day BOOLEAN DEFAULT FALSE
);

CREATE TABLE program_exercises (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  program_day_id      UUID NOT NULL REFERENCES program_days(id) ON DELETE CASCADE,
  exercise_id         UUID NOT NULL REFERENCES exercises(id),
  order_index         INT NOT NULL,
  sets                INT NOT NULL,
  reps_scheme         TEXT NOT NULL,
  weight_scheme       TEXT,
  progression_script  TEXT,
  progression_type    TEXT,
  rest_seconds        INT,
  rpe_target          FLOAT,
  rir_target          INT,
  tempo               TEXT,
  notes               TEXT
);

-- ─────────────────────────────────────────────────────────────
-- EXERCISE HISTORY (denormalized for fast analytics)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE exercise_history (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exercise_id     UUID NOT NULL REFERENCES exercises(id),
  workout_id      UUID REFERENCES workouts(id),
  date            DATE NOT NULL,
  max_weight      FLOAT,
  max_reps        INT,
  estimated_1rm   FLOAT,
  total_volume    FLOAT NOT NULL DEFAULT 0,
  total_sets      INT NOT NULL DEFAULT 0
);
CREATE INDEX idx_eh_user_exercise ON exercise_history(user_id, exercise_id, date DESC);

-- ─────────────────────────────────────────────────────────────
-- REFRESH TOKENS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE refresh_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  device_info TEXT,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_tokens_user    ON refresh_tokens(user_id);
CREATE INDEX idx_tokens_expires ON refresh_tokens(expires_at);

-- ─────────────────────────────────────────────────────────────
-- ANALYTICS MATERIALIZED VIEWS
-- ─────────────────────────────────────────────────────────────

-- Weekly volume by user
CREATE MATERIALIZED VIEW weekly_volume_by_muscle AS
SELECT
  w.user_id,
  DATE_TRUNC('week', w.date) AS week_start,
  e.primary_muscle,
  SUM(ws.volume)              AS total_volume,
  COUNT(ws.id)                AS total_sets
FROM workout_sets ws
JOIN workout_exercises we ON ws.workout_exercise_id = we.id
JOIN workouts w           ON we.workout_id = w.id
JOIN exercises e          ON we.exercise_id = e.id
WHERE ws.completed = TRUE AND w.is_deleted = FALSE
GROUP BY w.user_id, week_start, e.primary_muscle;

CREATE INDEX idx_wvbm_user ON weekly_volume_by_muscle(user_id, week_start DESC);

-- Auto-refresh materialized view nightly
CREATE OR REPLACE FUNCTION refresh_analytics()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_volume_by_muscle;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────
-- TRIGGERS
-- ─────────────────────────────────────────────────────────────

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at     BEFORE UPDATE ON users     FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER workouts_updated_at  BEFORE UPDATE ON workouts  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER programs_updated_at  BEFORE UPDATE ON programs  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER exercises_updated_at BEFORE UPDATE ON exercises FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─────────────────────────────────────────────────────────────
-- SEED DATA: Built-in exercises
-- ─────────────────────────────────────────────────────────────
INSERT INTO exercises (id, name, primary_muscle, secondary_muscles, equipment, category, is_custom) VALUES
  ('00000000-0000-0000-0001-000000000001', 'Barbell Back Squat',     'quads',      '{glutes,hamstrings,abs}',    'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000002', 'Conventional Deadlift',  'back',       '{hamstrings,glutes,traps}',  'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000003', 'Barbell Bench Press',    'chest',      '{shoulders,triceps}',        'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000004', 'Overhead Press',         'shoulders',  '{triceps,traps,abs}',        'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000005', 'Barbell Row',            'back',       '{biceps,lats,traps}',        'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000006', 'Pull-up',                'lats',       '{biceps,back}',              'bodyweight', 'compound', FALSE),
  ('00000000-0000-0000-0001-000000000007', 'Romanian Deadlift',      'hamstrings', '{glutes,back}',              'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000008', 'Hip Thrust',             'glutes',     '{hamstrings}',               'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000009', 'Front Squat',            'quads',      '{glutes,abs,back}',          'barbell',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000010', 'Incline Dumbbell Press', 'chest',      '{shoulders,triceps}',        'dumbbell',   'compound', FALSE),
  ('00000000-0000-0000-0001-000000000011', 'Lateral Raise',          'shoulders',  '{}',                         'dumbbell',   'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000012', 'Barbell Curl',           'biceps',     '{forearms}',                 'barbell',    'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000013', 'Leg Press',              'quads',      '{glutes,hamstrings}',        'machine',    'compound', FALSE),
  ('00000000-0000-0000-0001-000000000014', 'Cable Row',              'back',       '{biceps,lats}',              'cable',      'compound', FALSE),
  ('00000000-0000-0000-0001-000000000015', 'Dips',                   'triceps',    '{chest,shoulders}',          'bodyweight', 'compound', FALSE),
  ('00000000-0000-0000-0001-000000000016', 'Leg Curl',               'hamstrings', '{}',                         'machine',    'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000017', 'Leg Extension',          'quads',      '{}',                         'machine',    'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000018', 'Cable Fly',              'chest',      '{}',                         'cable',      'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000019', 'Face Pull',              'traps',      '{shoulders}',                'cable',      'isolation',FALSE),
  ('00000000-0000-0000-0001-000000000020', 'Calf Raise',             'calves',     '{}',                         'machine',    'isolation',FALSE)
ON CONFLICT (id) DO NOTHING;
