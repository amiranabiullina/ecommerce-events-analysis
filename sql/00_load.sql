-- Загрузка сырых событий REES46 (декабрь 2019 + январь 2020) в одну таблицу events.
-- Время в исходных файлах в UTC, формат '2019-12-01 00:00:00 UTC'.
CREATE OR REPLACE TABLE events AS
SELECT
    strptime(replace(event_time, ' UTC', ''), '%Y-%m-%d %H:%M:%S') AS event_time,
    event_type,
    product_id,
    category_id,
    category_code,
    brand,
    price,
    user_id,
    user_session
FROM read_csv(['data/raw/2019-Dec.csv', 'data/raw/2020-Jan.csv'],
              header = true,
              all_varchar = false,
              types = {'event_time': 'VARCHAR', 'category_id': 'BIGINT'});
