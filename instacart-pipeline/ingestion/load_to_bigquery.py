"""Charge les CSV bruts Instacart depuis GCS vers BigQuery, sans transformation.

Le schéma de chaque table est défini dans ingestion/tables/*.yaml (voir
specifications/instacard_data_integration.md pour la spec détaillée). Le
projet/dataset cible et le chemin de la clé de service account sont définis
dans ingestion/configuration.py (par défaut: service-account.json à la racine
du repo).

Usage: python ingestion/load_to_bigquery.py (aucun paramètre).
"""

import sys
from pathlib import Path

import yaml
from google.cloud import bigquery
from google.oauth2 import service_account

from configuration import CONFIG


def build_client() -> bigquery.Client:
    credentials = service_account.Credentials.from_service_account_file(
        str(CONFIG.credentials_path)
    )
    return bigquery.Client(project=CONFIG.project, credentials=credentials)


def load_table_spec(path: Path) -> dict:
    with path.open() as f:
        return yaml.safe_load(f)["table"]


def build_schema(columns: list[dict]) -> list[bigquery.SchemaField]:
    return [
        bigquery.SchemaField(
            name=col["name"],
            field_type=col["type"],
            mode=col["mode"],
            description=col.get("description", ""),
        )
        for col in columns
    ]


def load_one_table(client: bigquery.Client, spec: dict) -> int:
    dataset_id = spec["bigquery"]["dataset"]
    table_id = spec["bigquery"]["table"]

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1 if spec["source"]["has_header"] else 0,
        schema=build_schema(spec["columns"]),
        write_disposition=spec["bigquery"]["write_disposition"],
    )

    destination = f"{CONFIG.project}.{dataset_id}.{table_id}"
    job = client.load_table_from_uri(
        spec["source"]["bucket_uri"],
        destination,
        job_config=job_config,
        location=CONFIG.location,
    )
    job.result()
    return client.get_table(destination).num_rows


def main() -> int:
    client = build_client()

    results: dict[str, str] = {}
    for path in sorted(CONFIG.tables_dir.glob("*.yaml")):
        spec = load_table_spec(path)
        name = spec["name"]
        print(f"[{name}] chargement de {spec['source']['bucket_uri']} ...")
        try:
            num_rows = load_one_table(client, spec)
            print(f"[{name}] OK — {num_rows} lignes dans {spec['bigquery']['dataset']}.{spec['bigquery']['table']}")
            results[name] = "OK"
        except Exception as exc:  # noqa: BLE001 - on veut logguer puis continuer les autres tables
            print(f"[{name}] ECHEC — {exc}", file=sys.stderr)
            results[name] = "ECHEC"

    print("\nRésumé:")
    for name, status in results.items():
        print(f"  {name}: {status}")

    return 1 if any(status == "ECHEC" for status in results.values()) else 0


if __name__ == "__main__":
    sys.exit(main())
