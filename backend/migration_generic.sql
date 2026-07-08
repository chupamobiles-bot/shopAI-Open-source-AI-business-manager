-- ─────────────────────────────────────────────────────────────────────────────
-- ShopAI — Generic Business Migration
-- Run this ONCE on your existing MobileKhata database to add generic support.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add business_type to shops table
ALTER TABLE shops
  ADD COLUMN IF NOT EXISTS business_type  VARCHAR(100) DEFAULT 'Mobile Shop',
  ADD COLUMN IF NOT EXISTS currency       VARCHAR(10)  DEFAULT 'PKR',
  ADD COLUMN IF NOT EXISTS currency_symbol VARCHAR(10) DEFAULT 'Rs';

-- 2. Add generic fields JSON to products table
--    This stores any extra fields (brand/model for phones, batch/expiry for pharmacy, etc.)
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS fields JSON NULL COMMENT 'Generic product fields as JSON';

-- 3. Update existing products — move brand/model/storage/color into fields JSON
UPDATE products
SET fields = JSON_OBJECT(
  'brand',   COALESCE(brand, ''),
  'model',   COALESCE(model, ''),
  'storage', COALESCE(storage, ''),
  'color',   COALESCE(color, '')
)
WHERE fields IS NULL;

-- 4. Add identifier field to inventory (generic IMEI/serial/batch)
ALTER TABLE inventory
  ADD COLUMN IF NOT EXISTS identifier VARCHAR(100) NULL COMMENT 'IMEI, serial no, batch no, etc.';

-- Migrate existing IMEI values to identifier
UPDATE inventory SET identifier = imei WHERE imei IS NOT NULL AND identifier IS NULL;

-- 5. Create a shop_config table for storing business preset config
CREATE TABLE IF NOT EXISTS shop_config (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  shop_id     INT NOT NULL,
  config_key  VARCHAR(100) NOT NULL,
  config_val  TEXT,
  UNIQUE KEY uq_shop_key (shop_id, config_key),
  FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Optional: Insert default shop config for existing shops
-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT INTO shop_config (shop_id, config_key, config_val)
-- SELECT id, 'business_type', 'Mobile Shop' FROM shops
-- ON DUPLICATE KEY UPDATE config_val=VALUES(config_val);
