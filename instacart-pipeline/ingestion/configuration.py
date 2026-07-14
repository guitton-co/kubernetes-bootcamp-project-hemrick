"""Configuration centralisée du pipeline d'ingestion Instacart -> BigQuery."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

REPO_ROOT = Path(__file__).parent.parent
load_dotenv(REPO_ROOT / ".env")


@dataclass(frozen=True)
class IngestionConfig:
    project: str = "analytics-with-emeric"
    location: str = "US"
    tables_dir: Path = Path(__file__).parent / "tables"
    credentials_path: Path = REPO_ROOT / os.environ["GCP_SERVICE_ACCOUNT_LOAD_AND_DBT"]


CONFIG = IngestionConfig()
