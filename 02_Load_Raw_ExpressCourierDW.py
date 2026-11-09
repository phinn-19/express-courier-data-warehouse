"""ExpressCourierDW / Step 02: Load original LaDe CSVs into SQL Server Raw.

Expected local folder layout (script location is the project root):
    ExpressCourierDW/
        data/pickup_jl.csv
        data/delivery_jl.csv
        00_Create_ExpressCourierDW.sql
        02_Load_Raw_ExpressCourierDW.py

Run in the VS Code terminal opened in the project root:
    python -m pip install pyodbc
    python 02_Load_Raw_ExpressCourierDW.py

Safety: no DROP, DELETE, TRUNCATE or overwrite. On first load, either all
rows in ONE target are committed or the load is rolled back; rerunning with
already-populated tables skips matching counts and refuses partial tables.
"""

from __future__ import annotations

import csv
from pathlib import Path
import sys

try:
    import pyodbc
except ImportError:
    sys.exit("[ERROR] Chua co pyodbc. Cai bang: python -m pip install pyodbc")

# Works with the local SQL Server Express instance from SSMS.

import os

SERVER = os.getenv("SQL_SERVER", r".\SQLEXPRESS")
DATABASE = os.getenv("SQL_DATABASE", "ExpressCourierDW")

PROJECT_DIR = Path(__file__).resolve().parent
DATA_DIR = PROJECT_DIR / "data"
BATCH_SIZE = 2000

SOURCES = (
    {
        "process": "Pickup",
        "path": DATA_DIR / "pickup_jl.csv",
        "table": "[raw].[PickupTasks]",
        "expected_count": 261801,
        "columns": (
            "order_id", "region_id", "city", "courier_id", "accept_time",
            "time_window_start", "time_window_end", "lng", "lat", "aoi_id",
            "aoi_type", "pickup_time", "pickup_gps_time", "pickup_gps_lng",
            "pickup_gps_lat", "accept_gps_time", "accept_gps_lng",
            "accept_gps_lat", "ds",
        ),
    },
    {
        "process": "Delivery",
        "path": DATA_DIR / "delivery_jl.csv",
        "table": "[raw].[DeliveryTasks]",
        "expected_count": 31415,
        "columns": (
            "order_id", "region_id", "city", "courier_id", "lng", "lat",
            "aoi_id", "aoi_type", "accept_time", "accept_gps_time",
            "accept_gps_lng", "accept_gps_lat", "delivery_time",
            "delivery_gps_time", "delivery_gps_lng", "delivery_gps_lat", "ds",
        ),
    },
)


def open_connection():
    installed = pyodbc.drivers()
    driver = next(
        (d for d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")
         if d in installed),
        None,
    )
    if driver is None:
        raise RuntimeError(
            "Chua co Microsoft ODBC Driver 17/18 for SQL Server. "
            f"ODBC drivers tren may: {installed}"
        )
    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER={SERVER};DATABASE={DATABASE};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;"
        "Connection Timeout=15;"
    )
    return pyodbc.connect(connection_string, autocommit=False)


def row_count(cursor, table):
    return int(cursor.execute(f"SELECT COUNT_BIG(*) FROM {table}").fetchval())


def check_contract(cursor, source):
    path = source["path"]
    expected_columns = list(source["columns"])

    if not path.is_file():
        raise FileNotFoundError(f"Khong tim thay CSV: {path}")

    with path.open("r", encoding="utf-8-sig", newline="") as f:
        file_columns = next(csv.reader(f), None)
    if file_columns != expected_columns:
        raise RuntimeError(
            f"Header CSV sai: {path.name}\n"
            f"  Can: {expected_columns}\n"
            f"  Co:  {file_columns}"
        )

    schema, table = source["table"].replace("[", "").replace("]", "").split(".")
    sql_columns = [r[0] for r in cursor.execute(
        """SELECT c.name
           FROM sys.columns AS c
           JOIN sys.tables AS t ON c.object_id = t.object_id
           JOIN sys.schemas AS s ON t.schema_id = s.schema_id
           WHERE s.name = ? AND t.name = ?
           ORDER BY c.column_id""",
        schema, table,
    ).fetchall()]
    if sql_columns != expected_columns:
        raise RuntimeError(
            f"Cau truc {source['table']} khong trung 100% voi CSV.\n"
            f"  Can: {expected_columns}\n"
            f"  Co:  {sql_columns}"
        )


def load_one(connection, source):
    cursor = connection.cursor()
    target = source["table"]
    expected = source["expected_count"]
    path = source["path"]
    process = source["process"]
    columns = source["columns"]

    check_contract(cursor, source)
    existing = row_count(cursor, target)
    if existing > 0:
        if existing == expected:
            print(f"[SKIP] {target}: da co {existing:,} dong. Khong nap trung.")
            return
        raise RuntimeError(
            f"[STOP] {target} da co {existing:,} dong, khac {expected:,}. "
            "Khong tu y xoa; kiem tra trang thai nap truoc."
        )

    print(f"[START] {path.name} -> {target}", flush=True)

    # The initial log record is committed separately from the data load so
    # a failed data transaction can be rolled back and still have a log entry.
    run_id = cursor.execute(
        """INSERT INTO [audit].[ETLRunLog]
              ([pipeline_name], [source_file], [rows_read], [rows_loaded],
               [rows_rejected], [run_status])
           OUTPUT INSERTED.run_id
           VALUES (?, ?, 0, 0, 0, 'RUNNING')""",
        f"LoadRaw{process}", str(path),
    ).fetchval()
    connection.commit()

    quoted = ", ".join(f"[{col}]" for col in columns)
    marks = ", ".join("?" for _ in columns)
    insert_sql = f"INSERT INTO {target} ({quoted}) VALUES ({marks})"

    loaded = 0
    batch = []
    try:
        insert_cursor = connection.cursor()
        insert_cursor.fast_executemany = True

        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.reader(stream)
            next(reader)  # Header already validated above.
            for row in reader:
                if len(row) != len(columns):
                    raise ValueError(
                        f"CSV loi o ban ghi thu {loaded + 1}: "
                        f"co {len(row)} gia tri, can {len(columns)}"
                    )
                # Preserve CSV fields as-is, including empty strings.
                # Raw will not assume a year or convert GPS coordinates yet.
                batch.append(tuple(row))
                loaded += 1
                if len(batch) == BATCH_SIZE:
                    insert_cursor.executemany(insert_sql, batch)
                    batch.clear()
                    if loaded % 20000 == 0:
                        print(f"  Da xu ly {loaded:,} dong...", flush=True)
            if batch:
                insert_cursor.executemany(insert_sql, batch)

        if loaded != expected:
            raise ValueError(
                f"CSV co {loaded:,} dong, khac so dong da khao sat {expected:,}."
            )
        stored = row_count(cursor, target)
        if stored != expected:
            raise RuntimeError(
                f"SQL Server co {stored:,} dong, can {expected:,}."
            )

        cursor.execute(
            """UPDATE [audit].[ETLRunLog]
               SET [finished_at] = SYSDATETIME(), [rows_read] = ?,
                   [rows_loaded] = ?, [rows_rejected] = 0,
                   [run_status] = 'SUCCESS', [error_message] = NULL
               WHERE [run_id] = ?""",
            loaded, stored, run_id,
        )
        connection.commit()
        print(f"[SUCCESS] {target}: {stored:,} dong (run_id={run_id})", flush=True)
    except Exception as exc:
        connection.rollback()
        try:
            cursor.execute(
                """UPDATE [audit].[ETLRunLog]
                   SET [finished_at] = SYSDATETIME(), [rows_read] = ?,
                       [rows_loaded] = 0, [rows_rejected] = 0,
                       [run_status] = 'FAILED', [error_message] = ?
                   WHERE [run_id] = ?""",
                loaded, str(exc)[:2000], run_id,
            )
            connection.commit()
        except Exception:
            connection.rollback()
        print(f"[FAILED] {target}: da rollback du lieu chua commit.", flush=True)
        raise


def main():
    print("=== EXPRESS COURIER DW | STEP 02: RAW LOAD ===")
    print(f"Project:  {PROJECT_DIR}")
    print(f"Data dir: {DATA_DIR}")
    print(f"Server:   {SERVER}")
    print(f"Database: {DATABASE}\n")

    connection = open_connection()
    try:
        cursor = connection.cursor()
        actual_db = cursor.execute("SELECT DB_NAME()").fetchval()
        if actual_db != DATABASE:
            raise RuntimeError(f"Ket noi sai database: {actual_db}")

        # Verify everything before inserting anything.
        for source in SOURCES:
            check_contract(cursor, source)

        for source in SOURCES:
            load_one(connection, source)

        print("\n=== FINAL COUNTS ===")
        for source in SOURCES:
            count = row_count(cursor, source["table"])
            target = source["expected_count"]
            status = "OK" if count == target else "CHECK"
            print(f"{source['table']}: {count:,} / {target:,} [{status}]")
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\n[ERROR] {e}", file=sys.stderr)
        sys.exit(1)
