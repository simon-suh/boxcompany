-- ─────────────────────────────────────────────
--  BoxCo Sales DB — initial schema
--  Runs automatically when Postgres container
--  starts for the first time.
-- ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS customers (
  id            TEXT PRIMARY KEY,
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255),
  phone         VARCHAR(50),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
  id              TEXT PRIMARY KEY,
  order_number    VARCHAR(20) UNIQUE NOT NULL,
  customer_id     TEXT NOT NULL,
  payment_method  VARCHAR(50) NOT NULL,
  status          VARCHAR(50) NOT NULL DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
  id           TEXT PRIMARY KEY,
  order_id     TEXT NOT NULL,
  product_id   VARCHAR(50) NOT NULL,
  product_name VARCHAR(100) NOT NULL,
  quantity     INTEGER NOT NULL CHECK (quantity > 0),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS error_reports (
  id            TEXT PRIMARY KEY,
  order_number  VARCHAR(20),
  reported_by   VARCHAR(50) NOT NULL,
  issue_type    VARCHAR(100) NOT NULL,
  description   TEXT NOT NULL,
  notify_teams  TEXT[],
  status        VARCHAR(50) NOT NULL DEFAULT 'open',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_error_reports_order_number ON error_reports(order_number);

-- No seed data — completely fresh start
-- All customers and orders will be created through the Sales frontend