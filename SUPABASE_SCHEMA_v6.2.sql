
-- ══════════════════════════════════════════════════════════════
--  WhatsApp AI Agent v6 — Multi-Tenant Database Schema
--  Run this in: Supabase → SQL Editor → New query
--
--  v6 Changes:
--    ✅ RLS policies added (service_role full access)
--    ✅ phone_number column added to users table
--    ✅ Retry-safe task marking via idempotent PATCH
--    ✅ Gemini model pinned in config table
-- ══════════════════════════════════════════════════════════════

-- 1. Tenants (clients/customers)
CREATE TABLE IF NOT EXISTS tenants (
  tenant_id    TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  phone_number TEXT,
  bot_name     TEXT DEFAULT 'مساعد ذكي',
  plan         TEXT DEFAULT 'starter',
  is_active    BOOLEAN DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- 2. Users (per tenant)
CREATE TABLE IF NOT EXISTS users (
  user_id        TEXT PRIMARY KEY,
  tenant_id      TEXT REFERENCES tenants(tenant_id),
  user_name      TEXT,
  phone_number   TEXT,              -- ✅ v6: stored explicitly — never parsed from user_id
  language       TEXT DEFAULT 'ar',
  total_messages INTEGER DEFAULT 0,
  notes          TEXT,
  first_seen     TIMESTAMPTZ DEFAULT now(),
  last_seen      TIMESTAMPTZ DEFAULT now()
);

-- 3. Conversations
CREATE TABLE IF NOT EXISTS conversations (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(user_id),
  tenant_id     TEXT REFERENCES tenants(tenant_id),
  message       TEXT,
  intent        TEXT,
  confidence    TEXT,
  reply         TEXT,
  message_count INTEGER DEFAULT 1,
  duration_ms   INTEGER DEFAULT 0,
  timestamp     TIMESTAMPTZ DEFAULT now()
);

-- 4. Tasks
CREATE TABLE IF NOT EXISTS tasks (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(user_id),
  tenant_id  TEXT REFERENCES tenants(tenant_id),
  task       TEXT NOT NULL,
  summary    TEXT,
  due_at     TIMESTAMPTZ,
  sent       BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Errors
CREATE TABLE IF NOT EXISTS errors (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id  TEXT,
  user_id    TEXT,
  message    TEXT,
  error_type TEXT,
  node_name  TEXT,
  details    JSONB,
  timestamp  TIMESTAMPTZ DEFAULT now()
);

-- 6. Tenant daily stats (for dashboard)
CREATE TABLE IF NOT EXISTS tenant_stats (
  tenant_id  TEXT REFERENCES tenants(tenant_id),
  date       DATE,
  messages   INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (tenant_id, date)
);

-- ── Indexes ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_conversations_tenant    ON conversations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user      ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_timestamp ON conversations(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_intent    ON conversations(intent);
CREATE INDEX IF NOT EXISTS idx_tasks_due_unsent        ON tasks(due_at) WHERE sent = false;
CREATE INDEX IF NOT EXISTS idx_tasks_tenant            ON tasks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_tenant            ON users(tenant_id);

-- ── Auto-increment total_messages ───────────────────────────
CREATE OR REPLACE FUNCTION increment_user_messages()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE users
  SET total_messages = total_messages + 1,
      last_seen = NEW.timestamp
  WHERE user_id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_increment_messages ON conversations;
CREATE TRIGGER trg_increment_messages
  AFTER INSERT ON conversations
  FOR EACH ROW EXECUTE FUNCTION increment_user_messages();

-- ── Auto-increment tenant_stats ──────────────────────────────
CREATE OR REPLACE FUNCTION increment_tenant_stats()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO tenant_stats (tenant_id, date, messages)
  VALUES (NEW.tenant_id, DATE(NEW.timestamp), 1)
  ON CONFLICT (tenant_id, date)
  DO UPDATE SET messages = tenant_stats.messages + 1, updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenant_stats ON conversations;
CREATE TRIGGER trg_tenant_stats
  AFTER INSERT ON conversations
  FOR EACH ROW EXECUTE FUNCTION increment_tenant_stats();

-- ── Dashboard views ──────────────────────────────────────────

-- Overall stats per tenant
CREATE OR REPLACE VIEW tenant_overview AS
SELECT
  t.tenant_id,
  t.name AS tenant_name,
  t.plan,
  COUNT(DISTINCT u.user_id)         AS total_users,
  COUNT(c.id)                       AS total_messages,
  AVG(c.duration_ms)                AS avg_response_ms,
  COUNT(c.id) FILTER (WHERE DATE(c.timestamp) = CURRENT_DATE) AS messages_today,
  MAX(c.timestamp)                  AS last_activity
FROM tenants t
LEFT JOIN users u        ON u.tenant_id = t.tenant_id
LEFT JOIN conversations c ON c.tenant_id = t.tenant_id
GROUP BY t.tenant_id, t.name, t.plan;

-- Daily stats last 30 days
CREATE OR REPLACE VIEW daily_stats AS
SELECT
  tenant_id,
  DATE(timestamp)                    AS day,
  COUNT(*)                           AS total_messages,
  COUNT(DISTINCT user_id)            AS unique_users,
  ROUND(AVG(duration_ms))            AS avg_response_ms,
  COUNT(*) FILTER (WHERE intent = 'task')     AS tasks,
  COUNT(*) FILTER (WHERE intent = 'question') AS questions,
  COUNT(*) FILTER (WHERE intent = 'greeting') AS greetings,
  COUNT(*) FILTER (WHERE intent = 'command')  AS commands,
  COUNT(*) FILTER (WHERE intent = 'unknown')  AS unknown,
  ROUND(AVG(message_count), 1)       AS avg_messages_per_reply
FROM conversations
WHERE timestamp >= now() - interval '30 days'
GROUP BY tenant_id, DATE(timestamp)
ORDER BY day DESC;

-- ── Row Level Security ───────────────────────────────────────
-- ✅ v6: RLS enabled WITH policies — service_role gets full access,
--         anon/authenticated roles are blocked by default.
--         Without policies, even service_role is blocked in some
--         Supabase configurations.

ALTER TABLE conversations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE errors         ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_stats   ENABLE ROW LEVEL SECURITY;

-- conversations
DROP POLICY IF EXISTS "service_role_all_conversations" ON conversations;
CREATE POLICY "service_role_all_conversations" ON conversations
  TO service_role USING (true) WITH CHECK (true);

-- tasks
DROP POLICY IF EXISTS "service_role_all_tasks" ON tasks;
CREATE POLICY "service_role_all_tasks" ON tasks
  TO service_role USING (true) WITH CHECK (true);

-- users
DROP POLICY IF EXISTS "service_role_all_users" ON users;
CREATE POLICY "service_role_all_users" ON users
  TO service_role USING (true) WITH CHECK (true);

-- errors
DROP POLICY IF EXISTS "service_role_all_errors" ON errors;
CREATE POLICY "service_role_all_errors" ON errors
  TO service_role USING (true) WITH CHECK (true);

-- tenant_stats
DROP POLICY IF EXISTS "service_role_all_tenant_stats" ON tenant_stats;
CREATE POLICY "service_role_all_tenant_stats" ON tenant_stats
  TO service_role USING (true) WITH CHECK (true);

-- ══════════════════════════════════════════════════════════════
--  v5 Addition: Business Knowledge Table
--  معلومات العمل التي يستخدمها البوت للرد
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS business_knowledge (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tenant_id   TEXT REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  category    TEXT NOT NULL DEFAULT 'general',
              -- general | products | schedule | policies | team | faq | promotions | contact
  content     TEXT NOT NULL,
  priority    INTEGER DEFAULT 10,   -- كلما قل الرقم، كلما ظهر أول
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Index للأداء
CREATE INDEX IF NOT EXISTS idx_bk_tenant_active
  ON business_knowledge(tenant_id, is_active);

CREATE INDEX IF NOT EXISTS idx_bk_category
  ON business_knowledge(tenant_id, category);

-- Trigger لتحديث updated_at تلقائياً
CREATE OR REPLACE FUNCTION update_bk_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_bk_updated_at ON business_knowledge;
CREATE TRIGGER trg_bk_updated_at
  BEFORE UPDATE ON business_knowledge
  FOR EACH ROW EXECUTE FUNCTION update_bk_timestamp();

-- Row Level Security
ALTER TABLE business_knowledge ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_bk" ON business_knowledge;
CREATE POLICY "service_role_all_bk" ON business_knowledge
  TO service_role USING (true) WITH CHECK (true);

-- ══════════════════════════════════════════════════════════════
--  v6 Addition: Bot Config Table
--  ✅ يحدد الـ Gemini model صراحةً — يمنع تغيير السلوك بصمت
--     لو Gemini غيّر الـ default model
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS bot_config (
  tenant_id    TEXT PRIMARY KEY REFERENCES tenants(tenant_id) ON DELETE CASCADE,
  gemini_model TEXT NOT NULL DEFAULT 'gemini-2.0-flash',
              -- ✅ pin the model explicitly — options: gemini-2.0-flash | gemini-1.5-pro
  system_prompt TEXT,
  max_tokens   INTEGER DEFAULT 1024,
  temperature  NUMERIC(3,2) DEFAULT 0.7,
  updated_at   TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE bot_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role_all_bot_config" ON bot_config;
CREATE POLICY "service_role_all_bot_config" ON bot_config
  TO service_role USING (true) WITH CHECK (true);

-- بيانات تجريبية كمثال (يمكن حذفها)
-- INSERT INTO business_knowledge (tenant_id, category, content, priority) VALUES
-- ('default', 'general',  'متجر النور للإلكترونيات — نخدمكم منذ 2015', 1),
-- ('default', 'products', 'آيفون 15 برو — السعر 4500 ريال — متوفر', 2),
-- ('default', 'products', 'سامسونج S24 — السعر 3200 ريال — نفذ من المخزون', 3),
-- ('default', 'schedule', 'ساعات العمل: 9 صباحاً حتى 10 مساءً — كل أيام الأسبوع', 4),
-- ('default', 'policies', 'الشحن مجاني للطلبات فوق 500 ريال — يصل خلال 3 أيام', 5),
-- ('default', 'policies', 'سياسة الإرجاع: 14 يوم من تاريخ الاستلام', 6),
-- ('default', 'contact',  'للتواصل المباشر: 0501234567 — أو راسلنا على الإيميل', 7);



-- ══════════════════════════════════════════════════════════════
--  v6.2 Addition: Human Review Table
--  يخزن المراجعات البشرية بشكل دائم بدل Redis فقط
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS human_reviews (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  review_id    TEXT UNIQUE NOT NULL,   -- نفس الـ reviewId في Redis
  tenant_id    TEXT REFERENCES tenants(tenant_id),
  user_id      TEXT,
  phone_number TEXT,
  message      TEXT,
  bot_reply    TEXT,
  intent       TEXT,
  confidence   TEXT,
  status       TEXT DEFAULT 'pending', -- pending | approved | rejected | edited
  final_reply  TEXT,                   -- الرد بعد التعديل (إن وُجد)
  reviewed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reviews_status    ON human_reviews(status);
CREATE INDEX IF NOT EXISTS idx_reviews_tenant    ON human_reviews(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created   ON human_reviews(created_at DESC);

ALTER TABLE human_reviews ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role_all_reviews" ON human_reviews;
CREATE POLICY "service_role_all_reviews" ON human_reviews
  TO service_role USING (true) WITH CHECK (true);

-- View للمراجعات المعلقة
CREATE OR REPLACE VIEW pending_reviews AS
SELECT
  review_id,
  tenant_id,
  user_id,
  phone_number,
  LEFT(message, 100)   AS message_preview,
  LEFT(bot_reply, 200) AS reply_preview,
  intent,
  confidence,
  created_at,
  EXTRACT(EPOCH FROM (now() - created_at))/60 AS minutes_waiting
FROM human_reviews
WHERE status = 'pending'
ORDER BY created_at ASC;
