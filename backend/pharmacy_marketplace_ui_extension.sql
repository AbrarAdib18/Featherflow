-- Pharmacy marketplace product-card fields ------------------------------------
--
-- The marketplace/catalogue product card (pharmacy staff + farmer) needs an
-- optional "was" price (for the struck-through discount display) and a
-- minimum order quantity, mirroring feed_catalogue_products.min_order_quantity
-- which already does the same job for feed products. Both are optional/
-- default-safe so every existing row keeps working unchanged.

ALTER TABLE pharmacy_catalogue_medicines
    ADD COLUMN IF NOT EXISTS previous_price NUMERIC(10, 2);

ALTER TABLE pharmacy_catalogue_medicines
    ADD COLUMN IF NOT EXISTS min_order_quantity INTEGER NOT NULL DEFAULT 1;

COMMENT ON COLUMN pharmacy_catalogue_medicines.previous_price IS
    'Optional pre-discount/MRP price. Only rendered struck-through when '
    'actually higher than the current price - never fabricated.';
COMMENT ON COLUMN pharmacy_catalogue_medicines.min_order_quantity IS
    'Minimum quantity a farmer can order in one line item. Mirrors '
    'feed_catalogue_products.min_order_quantity.';
