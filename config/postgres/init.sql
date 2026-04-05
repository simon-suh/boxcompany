-- ─────────────────────────────────────────────
--  BoxCo Sales DB — initial schema
--  Runs automatically when Postgres container
--  starts for the first time.
-- ─────────────────────────────────────────────

-- Customers table
-- Stores contact info provided at time of order.
-- A customer can place many orders.
CREATE TABLE IF NOT EXISTS customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          VARCHAR(255) NOT NULL,
  email         VARCHAR(255),
  phone         VARCHAR(50),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Orders table
-- One row per submitted order.
-- Links to customer, stores payment method and status.
CREATE TABLE IF NOT EXISTS orders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number    VARCHAR(20) UNIQUE NOT NULL,
  customer_id     UUID NOT NULL REFERENCES customers(id),
  payment_method  VARCHAR(50) NOT NULL,
  status          VARCHAR(50) NOT NULL DEFAULT 'pending',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Order items table
-- One row per product line within an order.
-- An order can contain multiple box sizes.
CREATE TABLE IF NOT EXISTS order_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id  VARCHAR(50) NOT NULL,  -- e.g. 'small-box', 'medium-box', 'large-box'
  product_name VARCHAR(100) NOT NULL,
  quantity    INTEGER NOT NULL CHECK (quantity > 0),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Error reports table
-- Stores issues reported by any team.
-- Routes to responsible team via Kafka errors.reported topic.
CREATE TABLE IF NOT EXISTS error_reports (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number  VARCHAR(20),
  reported_by   VARCHAR(50) NOT NULL,  -- 'sales', 'shipment', 'inventory'
  issue_type    VARCHAR(100) NOT NULL,
  description   TEXT NOT NULL,
  notify_teams  TEXT[],               -- array of teams to notify
  status        VARCHAR(50) NOT NULL DEFAULT 'open',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast order number lookups
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_error_reports_order_number ON error_reports(order_number);

-- ─────────────────────────────────────────────
--  Scenario 1 seed data
--  A few existing orders to populate the
--  shipment team dashboard on first run.
-- ─────────────────────────────────────────────

INSERT INTO customers (id, name, email, phone) VALUES
  ('a1000000-0000-0000-0000-000000000001', 'Sarah Mitchell', 'sarah.mitchell@email.com', '+15550001001'),
  ('a1000000-0000-0000-0000-000000000002', 'James Okafor',   'james.okafor@email.com',   '+15550001002'),
  ('a1000000-0000-0000-0000-000000000003', 'Linda Chow',     'linda.chow@email.com',     '+15550001003'),
  ('a1000000-0000-0000-0000-000000000004', 'Marcus Reed',    'marcus.reed@email.com',    '+15550001004')
ON CONFLICT DO NOTHING;

INSERT INTO orders (id, order_number, customer_id, payment_method, status) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'ORD-10421', 'a1000000-0000-0000-0000-000000000001', 'credit_card',  'pending'),
  ('b1000000-0000-0000-0000-000000000002', 'ORD-10388', 'a1000000-0000-0000-0000-000000000002', 'invoice_net30','pending'),
  ('b1000000-0000-0000-0000-000000000003', 'ORD-10374', 'a1000000-0000-0000-0000-000000000003', 'ach_transfer', 'pending'),
  ('b1000000-0000-0000-0000-000000000004', 'ORD-10361', 'a1000000-0000-0000-0000-000000000004', 'credit_card',  'pending')
ON CONFLICT DO NOTHING;

INSERT INTO order_items (order_id, product_id, product_name, quantity) VALUES
  ('b1000000-0000-0000-0000-000000000001', 'medium-box', 'Medium box', 10),
  ('b1000000-0000-0000-0000-000000000002', 'small-box',  'Small box',  50),
  ('b1000000-0000-0000-0000-000000000002', 'large-box',  'Large box',  20),
  ('b1000000-0000-0000-0000-000000000003', 'medium-box', 'Medium box', 5),
  ('b1000000-0000-0000-0000-000000000004', 'small-box',  'Small box',  100)
ON CONFLICT DO NOTHING;
