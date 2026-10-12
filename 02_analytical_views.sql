
-- -----------------------------------------------------------------------------
-- VIEW 1: Výkonnost akvizičních kanálů a zařízení (Marketing Attribution)
-- Popis: Konsolidace návštěvnosti, konverzí, tržeb a zisku podle zdroje a zařízení.
-- -----------------------------------------------------------------------------
CREATE VIEW vw_channel_performance AS
SELECT 
    COALESCE(ws.utm_source, 'organic / direct')          AS traffic_source,
    ws.device_type,
    COUNT(ws.website_session_id)                         AS total_sessions,
    COUNT(o.order_id)                                    AS total_orders,
    ROUND(100.0 * COUNT(o.order_id) / COUNT(ws.website_session_id), 2) AS conversion_rate_pct,
    ROUND(SUM(o.price_usd), 2)                           AS total_revenue_usd,
    ROUND(SUM(o.price_usd - o.cogs_usd), 2)              AS total_gross_profit_usd,
    ROUND(AVG(o.price_usd), 2)                           AS avg_order_value_usd
FROM website_sessions ws
LEFT JOIN orders o 
    ON ws.website_session_id = o.website_session_id
GROUP BY 
    COALESCE(ws.utm_source, 'organic / direct'),
    ws.device_type
ORDER BY 
    total_revenue_usd DESC

-- podobny princip se da udělat u reklam/devices


-- -----------------------------------------------------------------------------
-- VIEW 2: Analýza vstupních stránek a Bounce Rate (Landing Page Audit)
-- Popis: Výpočet míry okamžitého opuštění pro všechny vstupní stránky e-shopu.
-- Metodika: Izolace první navštívené URL v session a filtrace relací s délkou 1.
-- -----------------------------------------------------------------------------

WITH visits AS (
SELECT 
    website_session_id,
    MIN(website_pageview_id)    AS first_visit,
    COUNT(website_pageview_id)  AS visit_tx
FROM website_pageviews
GROUP BY website_session_id
)

SELECT 
    w.pageview_url                                                                      AS landing_page, 
    SUM(CASE WHEN v.visit_tx = 1 THEN 1 END)                                            AS bounce,
    ROUND(100*SUM(CASE WHEN v.visit_tx = 1 THEN 1 END)/COUNT(website_pageview_id),2)    AS bounce_rate_pct
FROM visits v 
JOIN website_pageviews w
  ON v.first_visit = w.website_pageview_id
GROUP BY w.pageview_url

-- -----------------------------------------------------------------------------
-- VIEW 3: Kompletní konverzní trychtýř (End-to-End Purchase Funnel)
-- Popis: Kvantifikace průchodnosti mezi jednotlivými fázemi webu a drop-off analýza.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_conversion_funnel AS
WITH page_visits_flags AS (
    SELECT 
        website_session_id,
        MAX(CASE WHEN pageview_url = '/products' THEN 1 ELSE 0 END) AS saw_products,
        MAX(CASE WHEN pageview_url IN (
            '/the-original-mr-fuzzy',
            '/the-forever-love-bear',
            '/the-birthday-sugar-panda',
            '/the-hudson-river-mini-bear'
        ) THEN 1 ELSE 0 END) AS saw_product_detail,
        MAX(CASE WHEN pageview_url = '/cart' THEN 1 ELSE 0 END)     AS saw_cart,
        MAX(CASE WHEN pageview_url = '/shipping' THEN 1 ELSE 0 END) AS saw_shipping,
        MAX(CASE WHEN pageview_url IN ('/billing', '/billing-2') THEN 1 ELSE 0 END) AS saw_billing,
        MAX(CASE WHEN pageview_url = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS saw_thank_you
    FROM website_pageviews
    GROUP BY website_session_id
),
funnel_aggregates AS (
    SELECT 
        COUNT(website_session_id) AS total_sessions,
        SUM(saw_products)         AS step_products,
        SUM(saw_product_detail)   AS step_product_detail,
        SUM(saw_cart)             AS step_cart,
        SUM(saw_shipping)         AS step_shipping,
        SUM(saw_billing)          AS step_billing,
        SUM(saw_thank_you)        AS step_thank_you
    FROM page_visits_flags
)
SELECT 
    total_sessions,
    step_products,
    ROUND(100.0 * step_products / total_sessions, 2)          AS session_to_products_pct,
    step_product_detail,
    ROUND(100.0 * step_product_detail / step_products, 2)      AS products_to_detail_pct,
    step_cart,
    ROUND(100.0 * step_cart / step_product_detail, 2)          AS detail_to_cart_pct,
    step_shipping,
    ROUND(100.0 * step_shipping / step_cart, 2)                AS cart_to_shipping_pct,
    step_billing,
    ROUND(100.0 * step_billing / step_shipping, 2)             AS shipping_to_billing_pct,
    step_thank_you,
    ROUND(100.0 * step_thank_you / step_billing, 2)            AS billing_to_thank_you_pct,
    ROUND(100.0 * step_thank_you / total_sessions, 2)          AS overall_conversion_pct
FROM funnel_aggregates;


-- -----------------------------------------------------------------------------
-- VIEW 4: Produktové portfolio, marže a meziroční žebříček ziskovosti
-- Popis: Sledování tržeb, COGS, hrubé marže a ranking ziskovosti (ROW_NUMBER).
-- -----------------------------------------------------------------------------
CREATE VIEW vw_product_yearly_performance AS
WITH product_financials AS (
    SELECT 
        p.product_id,
        p.product_name,
        YEAR(oi.created_at)                       AS sales_year,
        COUNT(oi.order_item_id)                   AS units_sold,
        ROUND(SUM(oi.price_usd), 2)               AS total_revenue_usd,
        ROUND(SUM(oi.cogs_usd), 2)                AS total_cogs_usd,
        ROUND(SUM(oi.price_usd - oi.cogs_usd), 2) AS gross_profit_usd,
        ROUND(100.0 * SUM(oi.price_usd - oi.cogs_usd) / SUM(oi.price_usd), 2) AS gross_margin_pct
    FROM order_items oi
    JOIN products p 
        USING (product_id)
    GROUP BY 
        p.product_id,
        p.product_name,
        YEAR(oi.created_at)
)
SELECT 
    sales_year,
    product_name,
    units_sold,
    total_revenue_usd,
    total_cogs_usd,
    gross_profit_usd,
    gross_margin_pct,
    ROW_NUMBER() OVER (
        PARTITION BY sales_year 
        ORDER BY gross_profit_usd DESC
    ) AS rank_by_profit
FROM product_financials
ORDER BY 
    sales_year ASC, 
    rank_by_profit ASC;


-- -----------------------------------------------------------------------------
-- VIEW 5: Efektivita Cross-Sellingu a rozšiřování nákupního košíku
-- Popis: Kvantifikace objednávání sekundárních položek
-- -----------------------------------------------------------------------------
CREATE VIEW vw_cross_sell_performance AS
SELECT
    YEAR(created_at)                                                        AS sales_year,
    COUNT(*)                                                                AS tx_order_items,
    SUM(CASE WHEN is_primary_item = 0 THEN 1 END)                           AS tx_secondary_orders,
    ROUND(100*SUM(CASE WHEN is_primary_item = 0 THEN 1 END)/COUNT(*),2)     AS secondary_item_purchase_rate,
    SUM(CASE WHEN is_primary_item = 0 THEN price_usd END)                   AS secondary_orders_revenue
FROM order_items 
GROUP BY sales_year


