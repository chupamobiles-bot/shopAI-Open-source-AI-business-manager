-- ============================================================
--  MobileKhata — MySQL Schema
--  Upload to Hostinger via phpMyAdmin
-- ============================================================

CREATE DATABASE IF NOT EXISTS mobilekhata CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE mobilekhata;

-- ── Shops (one account per shop owner) ──────────────────────
CREATE TABLE shops (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    shop_name    VARCHAR(255)  NOT NULL,
    owner_name   VARCHAR(255)  NOT NULL,
    phone        VARCHAR(20),
    email        VARCHAR(255)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    api_token    VARCHAR(64)   UNIQUE,
    created_at   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
);

-- ── Products catalog (phone models) ─────────────────────────
CREATE TABLE products (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    shop_id    INT          NOT NULL,
    brand      VARCHAR(100) NOT NULL,   -- Samsung, Apple, Xiaomi ...
    model      VARCHAR(200) NOT NULL,   -- iPhone 16 Pro, Galaxy S24 Ultra
    storage    VARCHAR(50),             -- 128GB, 256GB
    color      VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE,
    UNIQUE KEY uk_product (shop_id, brand, model, storage, color)
);

-- ── Purchase invoices ────────────────────────────────────────
CREATE TABLE purchases (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    shop_id        INT           NOT NULL,
    supplier_name  VARCHAR(255),
    invoice_number VARCHAR(100),
    invoice_date   DATE,
    total_amount   DECIMAL(12,2) DEFAULT 0,
    image_url      TEXT,                -- Cloudinary URL
    notes          TEXT,
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
);

-- ── Inventory (one row per physical phone unit) ──────────────
CREATE TABLE inventory (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    shop_id        INT           NOT NULL,
    product_id     INT           NOT NULL,
    purchase_id    INT,
    imei           VARCHAR(20)   UNIQUE,
    purchase_price DECIMAL(12,2) NOT NULL,
    status         ENUM('in_stock','sold') DEFAULT 'in_stock',
    created_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (shop_id)    REFERENCES shops(id)    ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (purchase_id) REFERENCES purchases(id)
);

-- ── Sales ────────────────────────────────────────────────────
CREATE TABLE sales (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    shop_id         INT           NOT NULL,
    customer_name   VARCHAR(255),
    customer_phone  VARCHAR(20),
    sale_date       DATE          NOT NULL,
    total_amount    DECIMAL(12,2) NOT NULL,
    total_cost      DECIMAL(12,2) NOT NULL,
    total_profit    DECIMAL(12,2) NOT NULL,
    payment_method  ENUM('cash','card','transfer') DEFAULT 'cash',
    notes           TEXT,
    created_at      TIMESTAMP     DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE
);

-- ── Sale line items ──────────────────────────────────────────
CREATE TABLE sale_items (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    sale_id        INT           NOT NULL,
    inventory_id   INT           NOT NULL,
    sale_price     DECIMAL(12,2) NOT NULL,
    purchase_price DECIMAL(12,2) NOT NULL,
    profit         DECIMAL(12,2) NOT NULL,
    FOREIGN KEY (sale_id)      REFERENCES sales(id)     ON DELETE CASCADE,
    FOREIGN KEY (inventory_id) REFERENCES inventory(id)
);

-- ── Indexes for common queries ───────────────────────────────
CREATE INDEX idx_inventory_shop_status  ON inventory(shop_id, status);
CREATE INDEX idx_inventory_imei         ON inventory(imei);
CREATE INDEX idx_sales_shop_date        ON sales(shop_id, sale_date);
CREATE INDEX idx_purchases_shop_date    ON purchases(shop_id, invoice_date);
