"""Export seven validated Gold tables to CSV for Power BI development.

Place at: D:\\ExpressCourierDW\\scripts\\export_powerbi_snapshot.py
Run from project root (PowerShell):
    .\\.venv-dbt\\Scripts\\python.exe .\\scripts\\export_powerbi_snapshot.py

Requires pyodbc in .venv-dbt and ODBC Driver 18 for SQL Server on Windows.
Uses Windows authentication to the local SQL Server Express instance.
Override server if necessary with the DW_SQL_SERVER environment variable.
Does not write or change the SQL Server database.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parents[1]
EXPORT_DIR = ROOT / "bi" / "snapshots"
SERVER = os.getenv("DW_SQL_SERVER", r".\SQLEXPRESS")
DATABASE = "ExpressCourierDW"
FETCH_BATCH = 10_000

# Fixed, intentionally limited contract. Do not expose Raw tables or sensitive
# source fields to Power BI by default. Column names match Gold v1 (with AOI).
TABLE_COLUMNS: dict[str, tuple[str, ...]] = {
    "dim_date": (
        "date_key", "calendar_date", "year_number", "quarter_number",
        "month_number", "day_number", "iso_week_number",
    ),
    "dim_city": ("city_key", "city_code"),
    "dim_courier": ("courier_key", "process_code", "city_code", "source_courier_id"),
    "dim_region": ("region_key", "process_code", "city_code", "source_region_id"),
    "dim_aoi": (
        "aoi_key", "process_code", "city_code", "source_aoi_id",
        "aoi_type", "aoi_type_variant_count", "missing_aoi_type_rows",
    ),
    "fact_pickup": (
        "task_key", "source_order_id", "source_courier_id", "source_region_id",
        "source_aoi_id", "city_key", "courier_key", "region_key", "aoi_key",
        "accepted_date_key", "completed_date_key", "accepted_at", "completed_at",
        "task_count", "duration_seconds", "valid_duration_seconds",
        "window_status", "quality_status", "accept_gps_status", "pickup_gps_status",
    ),
    "fact_delivery": (
        "task_key", "source_order_id", "source_courier_id", "source_region_id",
        "source_aoi_id", "city_key", "courier_key", "region_key", "aoi_key",
        "accepted_date_key", "completed_date_key", "accepted_at", "completed_at",
        "task_count", "duration_seconds", "valid_duration_seconds",
        "quality_status", "gps_status",
    ),
}


def _qualified(name: str) -> str:
    # All identifiers are fixed in source code above (never taken from user input).
    return f"[dw].[{name}]"


def export_one(connection: pyodbc.Connection, table: str, columns: tuple[str, ...]) -> dict:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    dest = EXPORT_DIR / f"{table}.csv"
    temp = EXPORT_DIR / f"{table}.csv.part"
    cols_sql = ", ".join(f"[{col}]" for col in columns)
    sql = f"SELECT {cols_sql} FROM {_qualified(table)}"
    count_query = f"SELECT COUNT_BIG(*) FROM {_qualified(table)}"

    cur = connection.cursor()
    n = 0
    try:
        expected = int(cur.execute(count_query).fetchone()[0])
        cur.execute(sql)
        actual_columns = [c[0] for c in cur.description]
        if actual_columns != list(columns):
            raise ValueError(f"Unexpected columns in {table}: {actual_columns}")
        with temp.open("w", encoding="utf-8-sig", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(actual_columns)
            while True:
                rows = cur.fetchmany(FETCH_BATCH)
                if not rows:
                    break
                writer.writerows(rows)
                n += len(rows)
        if n != expected:
            raise RuntimeError(f"{table}: SQL count={expected} but exported={n}. Please retry.")
        temp.replace(dest)
    finally:
        cur.close()
        if temp.exists():
            temp.unlink()

    # File hashes allow the recipient to verify they received the right snapshot.
    hasher = hashlib.sha256()
    with dest.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            hasher.update(chunk)
    size = dest.stat().st_size
    print(f"  {table:16} {n:>9,} rows  {size / 1048576:>6.1f} MiB")
    return {
        "name": table,
        "file": dest.name,
        "rows": n,
        "columns": list(columns),
        "size_bytes": size,
        "sha256": hasher.hexdigest(),
    }


def main() -> None:
    conn_str = (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;"
    )
    print(f"Exporting Gold v1: {DATABASE}, server={SERVER}")
    print(f"Destination: {EXPORT_DIR}")
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    with pyodbc.connect(conn_str, timeout=15) as connection:
        results = [export_one(connection, table, cols) for table, cols in TABLE_COLUMNS.items()]

    metadata = {
        "database": DATABASE,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "scope": "LaDe / Jilin Gold v1; validate after future city imports",
        "notes": "CSV snapshot for Power BI development, not a live SQL connection",
        "tables": results,
    }
    manifest = EXPORT_DIR / "manifest.json"
    tmp_manifest = EXPORT_DIR / "manifest.json.part"
    tmp_manifest.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_manifest.replace(manifest)
    print(f"\nFinished: {len(results)} CSV files + manifest.json")
    print("Share bi/snapshots privately; keep these files out of GitHub.")


if __name__ == "__main__":
    main()
