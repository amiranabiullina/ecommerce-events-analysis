-- Очищенная таблица events_clean. Правила и допущения — в notebooks/02_cleaning.ipynb.
-- Запуск: python run_sql.py sql/02_clean.sql --write

CREATE OR REPLACE TABLE events_clean AS
WITH dedup AS (                       -- правило 1: точные дубли
    SELECT DISTINCT *
    FROM events
),
multi_user_sessions AS (              -- правило 7: сессии с несколькими user_id
    SELECT user_session
    FROM dedup
    WHERE user_session IS NOT NULL
    GROUP BY user_session
    HAVING COUNT(DISTINCT user_id) > 1
),
product_brand AS (                    -- правила 2 и 3: последний известный бренд товара
    SELECT product_id, ARG_MAX(brand, event_time) AS brand
    FROM dedup
    WHERE brand IS NOT NULL
    GROUP BY product_id
)
SELECT
    d.event_time,
    d.event_type,
    d.product_id,
    d.category_id,
    d.category_code,
    COALESCE(pb.brand, d.brand) AS brand,
    d.price,
    d.user_id,
    d.user_session,
    m.user_session IS NOT NULL AS is_multi_user_session
FROM dedup d
LEFT JOIN product_brand pb       ON pb.product_id = d.product_id
LEFT JOIN multi_user_sessions m  ON m.user_session = d.user_session;
-- правило 5: таблицу по дате не обрезаю. Окно анализа (с 16 декабря) задаётся в запросах анализа,
-- а события 1–15 декабря остаются историей: по ним видно корзины, из которых потом покупали.
