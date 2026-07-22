#!/usr/bin/env bash
set -euo pipefail

echo "== 1/3: chargement des CSV bruts vers BigQuery =="
python ingestion/load_to_bigquery.py

echo "== 2/3: tests dbt sur les sources brutes =="
dbt test --project-dir dbt --profiles-dir dbt --select "source:raw_instacart"

echo "== 3/3: construction du datamart gold_instacart =="
dbt run --project-dir dbt --profiles-dir dbt --select product_performance
