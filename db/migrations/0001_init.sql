-- Initial budgeting schema.
-- Money is stored in integer cents to avoid floating-point rounding.

CREATE TABLE IF NOT EXISTS accounts (
  id          BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'checking', -- checking | savings | credit | cash
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS categories (
  id          BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  -- planned monthly allocation, in cents ("give every dollar a job")
  budgeted    BIGINT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
  id           BIGSERIAL PRIMARY KEY,
  account_id   BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
  category_id  BIGINT REFERENCES categories(id) ON DELETE SET NULL,
  payee        TEXT NOT NULL DEFAULT '',
  -- negative = outflow (spend), positive = inflow (income), in cents
  amount       BIGINT NOT NULL,
  occurred_on  DATE NOT NULL DEFAULT CURRENT_DATE,
  note         TEXT NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_transactions_occurred_on
  ON transactions (occurred_on DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category
  ON transactions (category_id);

-- Seed a few starter categories so the UI isn't empty on first deploy.
INSERT INTO categories (name, budgeted) VALUES
  ('Groceries', 60000),
  ('Rent', 150000),
  ('Transportation', 20000),
  ('Dining Out', 25000),
  ('Savings', 40000)
ON CONFLICT (name) DO NOTHING;

-- A default account.
INSERT INTO accounts (name, type)
SELECT 'Everyday Checking', 'checking'
WHERE NOT EXISTS (SELECT 1 FROM accounts);
