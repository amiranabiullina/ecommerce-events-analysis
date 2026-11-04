-- Проверка качества событийных данных магазина (таблица events).
-- Запуск: python run_sql.py sql/01_quality.sql


-- 1. Полнота: процент пропусков по столбцам
SELECT
    COUNT(*) AS total_rows,
    ROUND(100.0 * (COUNT(*) - COUNT(category_code)) / COUNT(*), 2) AS category_code_missing_pct,
    ROUND(100.0 * (COUNT(*) - COUNT(category_id))   / COUNT(*), 2) AS category_id_missing_pct,
    ROUND(100.0 * (COUNT(*) - COUNT(brand))         / COUNT(*), 2) AS brand_missing_pct,
    ROUND(100.0 * (COUNT(*) - COUNT(price))         / COUNT(*), 2) AS price_missing_pct,
    ROUND(100.0 * (COUNT(*) - COUNT(user_id))       / COUNT(*), 2) AS user_id_missing_pct,
    COUNT(*) - COUNT(user_session)                                 AS user_session_missing_rows
FROM events;


-- 2. Отличаются ли события с брендом и без: цена и доли типов событий
SELECT
    CASE WHEN brand IS NULL THEN 'бренд неизвестен' ELSE 'бренд указан' END AS brand_group,
    COUNT(*)                     AS events,
    ROUND(AVG(price), 2)         AS avg_price,
    ROUND(MEDIAN(price), 2)      AS median_price,
    ROUND(100.0 * SUM(CASE WHEN event_type = 'view'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS view_pct,
    ROUND(100.0 * SUM(CASE WHEN event_type = 'cart'     THEN 1 ELSE 0 END) / COUNT(*), 1) AS cart_pct,
    ROUND(100.0 * SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) / COUNT(*), 2) AS purchase_pct,
    COUNT(DISTINCT category_id)  AS categories
FROM events
GROUP BY brand_group;


-- 3. Пропуск бренда — свойство товара или сбой записи?
--    Сначала одна строка на товар, потом товары делятся на три группы.
WITH products AS (
    SELECT
        product_id,
        COUNT(*)              AS events,       -- всего событий с товаром
        COUNT(brand)          AS with_brand,   -- из них с указанным брендом
        COUNT(DISTINCT brand) AS brands        -- сколько разных брендов у товара
    FROM events
    GROUP BY product_id
)
SELECT
    CASE
        WHEN with_brand = 0      THEN 'бренд не указан никогда'
        WHEN with_brand = events THEN 'бренд указан всегда'
        ELSE 'то указан, то нет'
    END                  AS product_group,
    COUNT(*)             AS products,
    SUM(events)          AS events,
    MAX(brands)          AS max_brands_per_product   -- больше 1 = у товара несколько брендов, ошибка
FROM products
GROUP BY product_group
ORDER BY products DESC;


-- 4. Сколько пропусков бренда можно восстановить по тому же товару
WITH products AS (
    SELECT
        product_id,
        COUNT(*)     AS events,
        COUNT(brand) AS with_brand
    FROM events
    GROUP BY product_id
)
SELECT
    COUNT(*)                 AS mixed_products,
    SUM(events)              AS mixed_events,
    SUM(events - with_brand) AS recoverable_missing_events,
    ROUND(100.0 * SUM(events - with_brand)
          / (SELECT COUNT(*) - COUNT(brand) FROM events), 2) AS pct_of_all_missing
FROM products
WHERE with_brand > 0 AND with_brand < events;   -- бренд указан хотя бы раз, но не всегда


-- 5. Товары с двумя разными брендами
SELECT
    product_id,
    STRING_AGG(DISTINCT brand, ', ') AS brands,
    COUNT(*)                         AS events
FROM events
WHERE brand IS NOT NULL
GROUP BY product_id
HAVING COUNT(DISTINCT brand) > 1
ORDER BY events DESC;


-- 6. Когда у этих товаров встречается каждый бренд
WITH multi AS (
    SELECT product_id
    FROM events
    WHERE brand IS NOT NULL
    GROUP BY product_id
    HAVING COUNT(DISTINCT brand) > 1
)
SELECT
    e.product_id,
    e.brand,
    MIN(e.event_time)::date AS first_seen,
    MAX(e.event_time)::date AS last_seen,
    COUNT(*)                AS events
FROM events e
JOIN multi m ON m.product_id = e.product_id
WHERE e.brand IS NOT NULL
GROUP BY e.product_id, e.brand
ORDER BY e.product_id, first_seen;


-- 7. Проверка гипотезы: candy — настоящий бренд, а на «двухбрендовых» товарах это ошибочная метка?
SELECT
    CASE WHEN product_id IN (
             SELECT product_id
             FROM events
             WHERE brand IS NOT NULL
             GROUP BY product_id
             HAVING COUNT(DISTINCT brand) > 1)
         THEN 'товары с двумя брендами'
         ELSE 'остальные товары'
    END                        AS products,
    COUNT(DISTINCT product_id) AS n_products,
    COUNT(*)                   AS events,
    MIN(event_time)::date      AS first_seen,
    MAX(event_time)::date      AS last_seen
FROM events
WHERE brand = 'candy'
GROUP BY products;


-- 8. Дубли: сколько лишних строк
WITH grouped AS (
    SELECT
        event_time, event_type, product_id, category_id,
        category_code, brand, price, user_id, user_session,
        COUNT(*) AS copies
    FROM events
    GROUP BY ALL
    HAVING copies > 1
)
SELECT
    COUNT(*)        AS duplicated_events,
    SUM(copies - 1) AS extra_rows,
    ROUND(100.0 * SUM(copies - 1) / (SELECT COUNT(*) FROM events), 2) AS extra_rows_pct
FROM grouped;


-- 9. Нулевые и отрицательные цены
SELECT
    CASE WHEN price < 0 THEN 'отрицательная' ELSE 'нулевая' END AS price_group,
    COUNT(*)                                                    AS events,
    COUNT(DISTINCT product_id)                                  AS products,
    SUM(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END)    AS purchases,
    ROUND(SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END), 2) AS purchase_sum
FROM events
WHERE price <= 0
GROUP BY price_group;


-- 10. Покупки без добавления товара в корзину, по неделям покупки
WITH purchases AS (
    SELECT user_id, product_id, MIN(event_time) AS first_purchase
    FROM events
    WHERE event_type = 'purchase'
    GROUP BY user_id, product_id
),
carts AS (
    SELECT DISTINCT user_id, product_id
    FROM events
    WHERE event_type = 'cart'
)
SELECT
    DATE_TRUNC('week', p.first_purchase)::date AS week,
    COUNT(*) AS purchased_pairs,
    ROUND(100.0 * SUM(CASE WHEN c.user_id IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS without_cart_pct
FROM purchases p
LEFT JOIN carts c
       ON c.user_id = p.user_id
      AND c.product_id = p.product_id
GROUP BY week
ORDER BY week;
