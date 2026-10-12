# E-Commerce Web Analytics & Conversion Funnel Optimization (SQL)

End-to-end data analytics projekt zaměřený na profilování, čištění, relační modelování a pokročilé analytické zpracování databáze e-commerce webového provozu (*Fuzzy Factory*). Projekt demonstruje transformaci surových webových a transakčních logů do produkčního relačního schématu a tvorbu analytických Views připravených pro reportingovou vrstvu v Power BI.

---

## Použité technologie & Zdroj dat
- **Databázový systém:** MySQL (CTEs, okenní funkce `ROW_NUMBER()`, podmíněná agregace `MAX(CASE WHEN...)`, DDL/DML operace, explicitní cizí klíče `FOREIGN KEY`, analytická Views).
- **Vývojové prostředí:** MySQL / DBeaver / VS Code.
- **Zdroj dat:** [Toy Store E-Commerce Database](https://mavenanalytics.io/data-playground/toy-store-e-commerce-database) (472 871 návštěv, 32 313 objednávek).

---

## Struktura repozitáře
- `01_data_cleaning.sql` – profilování dat, ošetření `NULL` a prázdných řetězců, validace finančních rozsahů, deduplikace přes `ROW_NUMBER()` a tvorba cizích klíčů (`FOREIGN KEY`).
- `02_analytical_views.sql` – sada produkčních analytických SQL pohledů (Views) řešících atribuci kanálů, bounce rate, nákupní trychtýř, produktové marže a cross-sell.
- `README.md` – technická, metodická a byznysová dokumentace projektu.
- *(Plánováno)* `reports/` – soubor `.pbix` a interaktivní vizualizace z Power BI.

---

## Datová architektura & Model

Data pokrývají 6 vzájemně provázaných entit:
- **Zdrojové tabulky:** `website_sessions`, `website_pageviews`, `orders`, `order_items`, `order_item_refunds`, `products`.
- **Čištění dat & Integrita (`01_data_cleaning.sql`):**
  - Validace chybějících hodnot a finančních rozsahů (`MIN`/`MAX` check, `refund_amount_usd <= 0`).
  - Deduplikace transakčních záznamů pomocí okenní funkce `ROW_NUMBER() OVER (PARTITION BY ...)`.
  - Zajištění referenční integrity pomocí explicitních cizích klíčů (`FOREIGN KEY`).
  - Správná interpretace `NULL` hodnot v UTM parametrech jako přirozené organické a přímé návštěvnosti (SEO / Direct).
- **Analytická Views (`02_analytical_views.sql`):**
  - `vw_channel_performance`: Sledování návštěvnosti, konverzí, tržeb a zisku podle zdroje a zařízení (`desktop` vs. `mobile`).
  - `vw_landing_page_bounce_rates`: Výpočet míry okamžitého opuštění (Bounce Rate) pro jednotlivé vstupní stránky.
  - `vw_conversion_funnel`: Kompletní nákupní trychtýř a identifikace propadů (Drop-off) mezi jednotlivými fázemi webu.
  - `vw_product_yearly_performance`: Vývoj tržeb, COGS, hrubé marže a dynamický meziroční žebříček ziskovosti produktů (`ROW_NUMBER()`).
  - `vw_cross_sell_performance`: Úspěšnost doporučování doplňkového zboží v košíku a podíl sekundárních položek.

---

## 🔍 Příklad zjištění: Úzká hrdla konverzního trychtýře (Funnel Bottlenecks)

Analýzou průchodnosti návštěvníků nákupním procesem (472 871 relací) byly pomocí techniky podmíněné agregace `MAX(CASE WHEN...)` lokalizovány dva zásadní propady:
- **Kritický bod 1 (Detail produktu ➔ Košík):** Ze zákazníků, kteří si prohlédnou detail plyšáka (210 214 relací), jich do košíku vloží zboží pouze 45,17 %. Více než **54,83 % zájemců v této fázi web opouští**. Zde vzniká hlavní prostor pro A/B testování sociálních důkazů (recenze) a úpravy CTA tlačítek.
- **Kritický bod 2 (Platební brána ➔ Dokončení):** Téměř **37,93 % uživatelů**, kteří již vyplnili doručovací adresu a pokračovali k platbě, transakci nedokončí. Tento vysoký propad přímo inicioval vývoj a A/B testování optimalizované pokladny `/billing-2`.

### Výsledná data nákupního trychtýře:

| Krok trychtýře | Počet relací | Mezikroková průchodnost | Ztráta (Drop-off) |
| :--- | :--- | :--- | :--- |
| **1. Vstup na web** | 472 871 | — | — |
| **2. Katalog produktů** (`/products`) | 261 231 | 55,24 % | -44,76 % |
| **3. Detail plyšáka** (konkrétní produkt) | 210 214 | 80,47 % | -19,53 % |
| **4. Vložení do košíku** (`/cart`) | 94 953 | **45,17 %** *(Kritický bod 1)* | **-54,83 %** |
| **5. Způsob dopravy** (`/shipping`) | 64 484 | 67,91 % | -32,09 % |
| **6. Platební brána** (`/billing` & `/billing-2`) | 52 058 | 80,73 % | -19,27 % |
| **7. Dokončený nákup** (`/thank-you`) | 32 313 | **62,07 %** *(Kritický bod 2)* | **-37,93 %** |
| **Celková konverze webu (End-to-End)** | **32 313** | **6,83 %** | — |

### SQL dotaz pro výpočet konverzního trychtýře:
```sql
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
