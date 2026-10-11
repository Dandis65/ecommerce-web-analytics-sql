# 📊 E-Commerce Web Analytics & Conversion Funnel Optimization

Komplexní SQL projekt zaměřený na relační modelování, datový audit a byznysovou analytiku webového provozu fiktivního e-shopu s plyšovými hračkami (*Fuzzy Factory*). Projekt pokrývá analýzu **472 871 návštěv**, **32 313 objednávek** a generovaných tržeb přes **1,9 mil. USD**.

---

## 📌 Přehled projektu a cíle

Hlavním cílem projektu bylo převzít surová transakční data a webové logy, zajistit jejich referenční integritu, odstranit analytické pasti (Simpsonův paradox, chybějící UTM parametry) a vybudovat strukturované SQL views pro strategické rozhodování vedení e-shopu:
1. **Marketing Attribution:** Identifikace nejziskovějších akvizičních kanálů a odhalení výkonnostní propasti mezi desktopem a mobilem.
2. **A/B Testing & UX Audit:** Vyhodnocení efektivity nových vstupních stránek (`/home` vs. `/lander-1`) a platebních bran (`/billing` vs. `/billing-2`).
3. **Conversion Funnel Optimization:** Identifikace přesných míst v nákupním košíku, kde zákazníci nejvíce odpadávají.
4. **Product Economics & Cross-Sell:** Analýza maržovosti jednotlivých produktů a měření úspěšnosti doporučování druhého kusu v košíku (Attach Rate).

---

## 🗄️ Datová architektura a integrita

Dataset se skládá ze 6 provázaných relačních tabulek:
* `website_sessions` – metadata o relaci (kanál, UTM parametry, typ zařízení, čas).
* `website_pageviews` – log zobrazení jednotlivých URL adres v rámci návštěvy.
* `orders` – dokončené nákupy navázané na session a uživatele.
* `order_items` – jednotlivé položky v objednávce (rozlišení primárního a sekundárního kusu).
* `order_item_refunds` – refundace a vrácené platby.
* `products` – katalog produktů s uvedením základní ceny a nákladů (COGS).

### Relační integrita a Data Quality Audit (`01_data_cleaning.sql`)
Před spuštěním analytických dotazů proběhl kompletní audit datové kvality:
* **Deduplikace:** Pomocí okenní funkce `ROW_NUMBER() OVER (PARTITION BY ...)` bylo ověřeno, že transakční tabulky neobsahují duplicitní zápisy (`rn > 1` = 0).
* **Cizí klíče (Foreign Keys):** Schéma bylo provázáno pomocí `ALTER TABLE ... ADD FOREIGN KEY`, což garantuje referenční integritu (nemožnost existence sirotčích záznamů) a vytváří indexy pro optimalizaci rychlosti `JOIN` operací.
* **Správná interpretace `NULL` hodnot v UTM:** `NULL` hodnoty ve sloupcích `utm_source`, `utm_campaign` a `utm_content` nebyly chybou měření, ale reprezentují přirozenou návštěvnost. Zachování těchto řádků umožnilo přesnou segmentaci na:
  * **Organické vyhledávání (SEO):** UTM jsou `NULL`, ale `http_referer` odkazuje na vyhledávač (43 411 návštěv).
  * **Přímá návštěvnost (Direct):** Všechny parametry jsou `NULL`, zákazník zadal URL ručně (39 917 návštěv).

---

## 🔍 Klíčová analytická zjištění

### 1. Akviziční kanály a propast mezi zařízeními
* **Google (`gsearch`)** je primárním tahounem tržeb (1,27 mil. USD, konverze **6,75 %**).
* **Organická/přímá návštěvnost** má nejvyšší konverzi (**7,34 %**), což potvrzuje vysokou lojalitu vracejících se zákazníků.
* **Sociální sítě (`socialbook`)** vykazují podprůměrnou konverzi (**3,21 %**) a představují neefektivně alokovaný rozpočet.
* **Propast v zařízeních:** Desktop dosahuje konverzního poměru **8,50 %**, zatímco mobilní zařízení pouze **3,09 %**. Mobilní verze webu vyžaduje kompletní přepracování UX.

### 2. A/B Test Landing Page a Simpsonův paradox
Při plošném pohledu na celý web vykazoval starý `/home` konverzi 7,06 % a nový `/lander-1` zdánlivě slabších 4,53 %. 

Při očištění dat o kontext (izolace placené kampaně `gsearch nonbrand` v testovacím období) se ukázalo, že:
* `/home` konvertoval pouze na **3,22 %**.
* `/lander-1` dosáhl konverze **4,41 %**.
* **Výsledek:** Nový lander zvedl prodeje o **+37 %** na studené návštěvnosti. Plošné číslo bylo zkresleno tím, že na `/home` přicházeli i věrní a přímí zákazníci.

### 3. Konverzní trychtýř (Funnel Bottlenecks)

Z celkového počtu 472 871 návštěv dokončilo nákup 32 313 lidí (celková konverze **6,83 %**).

| Krok trychtýře | Unikátní relace | Průchodnost krokem | Ztráta (Drop-off) |
| :--- | :--- | :--- | :--- |
| 1. Vstup na web | 472 871 | — | — |
| 2. Katalog produktů (`/products`) | 261 231 | 55,24 % | -44,76 % |
| 3. Detail produktu (konkrétní hračka) | 210 214 | 80,47 % | -19,53 % |
| 4. Vložení do košíku (`/cart`) | 94 953 | **45,17 %** | **-54,83 % (Úzké hrdlo 1)** |
| 5. Volba dopravy (`/shipping`) | 64 484 | 67,91 % | -32,09 % |
| 6. Platební brána (`/billing`) | 52 058 | 80,73 % | -19,27 % |
| 7. Dokončený nákup (`/thank-you`) | 32 313 | **62,07 %** | **-37,93 % (Úzké hrdlo 2)** |

* **Kritický bod 1 (Produkt $\rightarrow$ Košík):** Více než polovina zájemců (54,83 %) opouští detail produktu bez nákupního záměru. Doporučuje se zavést sociální důkazy (hvězdičky, recenze) a zvýraznit garanci vrácení peněz.
* **Kritický bod 2 (Pokladna $\rightarrow$ Zaplacení):** Téměř 38 % uživatelů, kteří již vyplnili doručovací adresu, nedokončilo platbu. Tento problém vyřešilo nasazení redesignované pokladny `/billing-2`.

### 4. Produktová ekonomika a Cross-Sell (Attach Rate)
* Postupné rozšiřování portfolia z jednoho produktu (*Mr. Fuzzy*) na 4 plyšáky stabilizovalo marži e-shopu na **62–64 %**.
* Zavedení doporučení druhého kusu v košíku vytvořilo nový zdroj příjmů bez dodatečných akvizičních nákladů. Podíl objednávek s doplňkovým produktem (**Attach Rate**) dosáhl stabilních dvouciferných hodnot, což zásadním způsobem navýšilo průměrnou hodnotu objednávky (AOV).

---

## 🛠️ Použité SQL techniky
* **Common Table Expressions (CTE):** Logické rozdělení vícekrokových výpočtů pro zachování čitelnosti kódu.
* **Podmíněná agregace (`MAX(CASE WHEN ...)`):** Agregace webových logů na úroveň jednotlivých session ID pro sestavení trychtýře.
* **Okenní funkce (`ROW_NUMBER()`):** Deduplikace dat a dynamický ranking ziskovosti produktů v čase.
* **Databázové pohledy (`CREATE VIEW`):** Příprava datových struktur pro přímé napojení do BI nástrojů (Power BI / Tableau).

---

## 📁 Struktura repozitáře
```text
├── 01_data_cleaning.sql        # Audit dat, deduplikace, vazby cizích klíčů
├── 02_analytics_views.sql       # Produkční analytické pohledy a metriky
└── README.md                   # Manažerské shrnutí a dokumentace projektu
