"""Выполнить SQL-файл или запрос против базы проекта и напечатать результат.

python run_sql.py sql/01_quality.sql
python run_sql.py --write sql/00_load.sql
python run_sql.py -q "SELECT COUNT(*) FROM events"
"""
import sys

import duckdb

# По умолчанию только чтение, чтобы не мешать открытому ноутбуку; --write нужен для 00_load.sql
write = '--write' in sys.argv
args = [a for a in sys.argv[1:] if a != '--write']
con = duckdb.connect('data/processed/shop.duckdb', read_only=not write)

if args[0] == '-q':
    statements = [args[1]]
else:
    statements = open(args[0], encoding='utf-8').read().split(';')

for stmt in statements:
    code = [line for line in stmt.splitlines() if line.strip() and not line.strip().startswith('--')]
    if not code:
        continue
    result = con.sql(stmt)
    if result is not None:
        print(result.show(max_rows=60) or '')
