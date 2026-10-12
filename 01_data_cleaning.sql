-- 1. KONTROLA CHYBĚJÍCÍCH A PRÁZDNÝCH HODNOT (NULL & Empty String Check)

SELECT 
    COUNT(CASE WHEN order_item_refund_id IS NULL THEN 1 END) AS null_refund_id,
    COUNT(CASE WHEN created_at IS NULL THEN 1 END)           AS null_created_at,
    COUNT(CASE WHEN order_item_id IS NULL THEN 1 END)        AS null_order_item_id,
    COUNT(CASE WHEN order_id IS NULL THEN 1 END)             AS null_order_id,
    COUNT(CASE WHEN refund_amount_usd IS NULL OR TRIM(refund_amount_usd) = '' THEN 1 END) AS invalid_refund_amount
FROM order_item_refunds;


-- 2. KONTROLA DUPLICIT (Deduplication Check)

WITH rn_check AS (
    SELECT 
        order_item_refund_id,
        created_at,
        order_item_id,
        order_id,
        refund_amount_usd,
        ROW_NUMBER() OVER (
            PARTITION BY created_at, order_item_id, order_id, refund_amount_usd 
            ORDER BY order_item_refund_id
        ) AS rn
    FROM order_item_refunds
)
SELECT 
    order_item_refund_id,
    created_at,
    order_item_id,
    order_id,
    refund_amount_usd
FROM rn_check
WHERE rn > 1;

-- 3. VALIDACE FINANČNÍCH ROZSAHŮ (Boundary & Logic Check)

SELECT 
    SUM(CASE WHEN refund_amount_usd <= 0 THEN 1 ELSE 0 END) AS minus_check,
    MIN(refund_amount_usd)                                  AS min_refund,
    MAX(refund_amount_usd)                                  AS max_refund
FROM order_item_refunds;

-- 4. ZAJIŠTĚNÍ REFERENČNÍ INTEGRITY (Foreign Keys)

ALTER TABLE order_item_refunds
    ADD FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id),
    ADD FOREIGN KEY (order_id) REFERENCES orders(order_id)  



-- =============================================================================
-- ČIŠTĚNÍ A KONTROLA: order_items
-- =============================================================================

-- 1. Kontrola NULL hodnot, prázdných řetězců a finančních rozsahů
SELECT 
    SUM(CASE WHEN order_item_id IS NULL THEN 1 ELSE 0 END) AS order_item_id_null,
    SUM(CASE WHEN created_at IS NULL THEN 1 ELSE 0 END) AS created_at_null,
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_null,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_null,
    SUM(CASE WHEN is_primary_item IS NULL THEN 1 ELSE 0 END) AS is_primary_item_null,
    SUM(CASE WHEN price_usd IS NULL OR TRIM(price_usd) = '' THEN 1 ELSE 0 END) AS price_usd_null,
    SUM(CASE WHEN cogs_usd IS NULL OR TRIM(cogs_usd) = '' THEN 1 ELSE 0 END) AS cogs_usd_null,
    MAX(price_usd), 
    MIN(price_usd),
    MAX(cogs_usd), 
    MIN(cogs_usd)
FROM order_items;


-- 2. Kontrola duplicit

WITH rn_count AS (
    SELECT 
        order_item_id,
        created_at,
        order_id,
        product_id,
        is_primary_item,
        price_usd,
        cogs_usd,
        ROW_NUMBER() OVER (
            PARTITION BY order_item_id, created_at, order_id, product_id, is_primary_item, price_usd, cogs_usd
        ) AS rn
    FROM order_items
)
SELECT 
    order_item_id,
    created_at,
    order_id,
    product_id,
    is_primary_item,
    price_usd,
    cogs_usd
FROM rn_count
WHERE rn > 1;


-- 3. Propojení vazeb (Foreign Keys)
-- Provázání položky s objednávkou (orders) a produktovým katalogem (products)
ALTER TABLE order_items
    ADD FOREIGN KEY (order_id) REFERENCES orders(order_id),
    ADD FOREIGN KEY (product_id) REFERENCES products(product_id);

    -- =============================================================================
-- OSTATNÍ TABULKY: orders, products, website_sessions, website_pageviews
-- =============================================================================
-- U všech zbývajících tabulek proběhl identický proces auditu dat:
-- 1. Kontrola NULL hodnot a prázdných znaků (SUM CASE WHEN ... IS NULL)
-- 2. Deduplikace pomocí okenní funkce ROW_NUMBER()
-- 3. Provázání cizích klíčů (Foreign Keys) mezi sessions, orders a pageviews
-- Výsledek: Data byla validována bez nalezených duplicit a integrita schématu je zajištěna.



