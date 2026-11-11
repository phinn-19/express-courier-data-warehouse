"""ExpressCourierDW - safe incremental LaDe Raw ingestion (v2.1).

Builds on 02_Load_Raw_ExpressCourierDW.py. Works with the EXISTING tables:
    raw.PickupTasks, raw.DeliveryTasks, audit.ETLRunLog.

Scope: one FULL CSV snapshot per process and city, not CDC/upserts.
IMPORTANT: do NOT run multiple copies of this loader concurrently.

Commands (from D:\\ExpressCourierDW):
    python scripts/03_Load_Raw_Idempotent_v2.py --help
    python scripts/03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin \
        --file data/pickup_jl.csv --check
    python scripts/03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin \
        --file data/pickup_jl.csv --register-existing
    python scripts/03_Load_Raw_Idempotent_v2.py --process pickup --city Hangzhou \
        --file data/pickup_hz.csv --load

No DROP / DELETE / TRUNCATE / REPLACE. Data INSERT is all-or-nothing per file.
Legacy Jilin can only be registered after a full CSV-vs-Raw multiset check.
"""
from __future__ import annotations

import argparse
from collections import Counter
import csv
import hashlib
import json
import os
from pathlib import Path
import sys

PICKUP_COLS = (
    "order_id", "region_id", "city", "courier_id", "accept_time",
    "time_window_start", "time_window_end", "lng", "lat", "aoi_id",
    "aoi_type", "pickup_time", "pickup_gps_time", "pickup_gps_lng",
    "pickup_gps_lat", "accept_gps_time", "accept_gps_lng", "accept_gps_lat", "ds",
)
DELIVERY_COLS = (
    "order_id", "region_id", "city", "courier_id", "lng", "lat",
    "aoi_id", "aoi_type", "accept_time", "accept_gps_time",
    "accept_gps_lng", "accept_gps_lat", "delivery_time",
    "delivery_gps_time", "delivery_gps_lng", "delivery_gps_lat", "ds",
)
# Fixed trusted identifiers; no user-supplied SQL table names.
PROCESSES = {
    "pickup": {"code": "P", "table": "[raw].[PickupTasks]", "sql_name": "PickupTasks", "cols": PICKUP_COLS},
    "delivery": {"code": "D", "table": "[raw].[DeliveryTasks]", "sql_name": "DeliveryTasks", "cols": DELIVERY_COLS},
}
AUDIT_TABLE = "[audit].[ETLRunLog]"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def iter_csv(path: Path, cols: tuple[str, ...]):
    """Read values exactly as v1: original order, UTF-8 BOM, empty strings kept."""
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        header = next(reader, None)
        if header != list(cols):
            raise ValueError(
                f"CSV header khong khop voi Raw. File: {path.name}\n"
                f"  Expected: {list(cols)}\n  Received: {header}"
            )
        for line_number, row in enumerate(reader, start=2):
            if len(row) != len(cols):
                raise ValueError(
                    f"CSV dong {line_number}: co {len(row)} cot, can {len(cols)} cot"
                )
            yield line_number, tuple(row)


def check_csv(path: Path, cols: tuple[str, ...], city: str) -> int:
    """Validate every row BEFORE writing anything to Raw."""
    seen_orders: set[str] = set()
    total = 0
    city_index = cols.index("city")
    order_index = cols.index("order_id")
    for line, row in iter_csv(path, cols):
        if row[city_index].strip().upper() != city:
            raise ValueError(
                f"Dong {line}: city={row[city_index]!r}, nhung --city={city!r}"
            )
        order_id = row[order_index].strip()
        if not order_id:
            raise ValueError(f"Dong {line}: order_id rong")
        if order_id in seen_orders:
            raise ValueError(f"Dong {line}: order_id trung trong file: {order_id!r}")
        seen_orders.add(order_id)
        total += 1
    if not total:
        raise ValueError("CSV khong co dong du lieu")
    return total


def connect(server: str, database: str):
    try:
        import pyodbc
    except ImportError as exc:
        raise RuntimeError(
            "Chua cai pyodbc trong Python hien tai. Chay: python -m pip install pyodbc"
        ) from exc
    drivers = pyodbc.drivers()
    driver = next(
        (d for d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server") if d in drivers),
        None,
    )
    if not driver:
        raise RuntimeError(f"Can ODBC Driver 17/18 for SQL Server. Co san: {drivers}")
    conn_string = (
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;"
        "Connection Timeout=15;"
    )
    return pyodbc.connect(conn_string, autocommit=False)


def verify_sql_structure(cur, cfg):
    found = [row[0] for row in cur.execute(
        """SELECT c.name FROM sys.columns c
           JOIN sys.tables t ON c.object_id = t.object_id
           JOIN sys.schemas s ON t.schema_id = s.schema_id
           WHERE s.name = N'raw' AND t.name = ?
           ORDER BY c.column_id""",
        cfg["sql_name"],
    ).fetchall()]
    if found != list(cfg["cols"]):
        raise RuntimeError(
            f"Raw {cfg['table']} khong giong CSV contract.\n"
            f"Expected: {list(cfg['cols'])}\nActual: {found}"
        )
    required = {
        "run_id", "pipeline_name", "source_file", "rows_read", "rows_loaded",
        "rows_rejected", "run_status", "error_message", "finished_at",
        "process_code", "city_code", "file_sha256", "source_bytes",
        "origin_mode", "ingestion_version",
    }
    actual = {row[0] for row in cur.execute(
        "SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(N'audit.ETLRunLog')"
    ).fetchall()}
    missing = required - actual
    if missing:
        raise RuntimeError(
            "Chua chay 03_Upgrade_ETLRunLog_v2.sql hoac audit sai schema. "
            f"Thieu cot: {sorted(missing)}"
        )


def count_city(cur, table: str, city: str) -> int:
    return int(cur.execute(
        f"SELECT COUNT_BIG(*) FROM {table} "
        "WHERE UPPER(LTRIM(RTRIM([city]))) = ?", city,
    ).fetchval())


def successful_city_record(cur, process_code: str, city: str):
    return cur.execute(
        f"""SELECT TOP (1) run_id, file_sha256, rows_read, origin_mode
            FROM {AUDIT_TABLE}
            WHERE process_code = ? AND city_code = ? AND run_status = 'SUCCESS'
            ORDER BY run_id DESC""",
        process_code, city,
    ).fetchone()


def row_fingerprint(values) -> bytes:
    # JSON protects against delimiter ambiguity; preserve order and empty strings.
    payload = json.dumps(list(values), ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).digest()


def verify_legacy_multiset(cur, cfg, city: str, path: Path, expected_rows: int):
    """Exact row multiset check (up to SHA-256 collision resistance).

    No row-order assumption because the original Raw tables have no row number.
    Counter counts duplicates rather than silently collapsing them.
    """
    print("[VERIFY] So sanh noi dung CSV voi Raw, khong chi so dong...", flush=True)
    counts = Counter(row_fingerprint(row) for _, row in iter_csv(path, cfg["cols"]))
    columns = ", ".join(f"[{c}]" for c in cfg["cols"])
    reader = cur.execute(
        f"SELECT {columns} FROM {cfg['table']} "
        "WHERE UPPER(LTRIM(RTRIM([city]))) = ?", city,
    )
    sql_count = 0
    while True:
        rows = reader.fetchmany(1000)
        if not rows:
            break
        for sql_row in rows:
            key = row_fingerprint(sql_row)
            if counts.get(key, 0) <= 0:
                raise RuntimeError(
                    "Raw co dong khong khop CSV (hoac mot dong xuat hien qua so lan). "
                    "Khong dang ky audit; can dieu tra."
                )
            counts[key] -= 1
            if counts[key] == 0:
                del counts[key]
            sql_count += 1
        if sql_count % 50000 < 1000:
            print(f"  Da doi chieu {sql_count:,} dong Raw", flush=True)
    if sql_count != expected_rows or counts:
        raise RuntimeError(
            f"CSV vs Raw khong khop: CSV={expected_rows:,}; Raw={sql_count:,}; "
            f"so ma dong CSV con thieu trong Raw={sum(counts.values()):,}"
        )
    print(f"[VERIFIED] {sql_count:,} dong khop ca noi dung va so lan xuat hien.", flush=True)


def insert_started_run(cur, cfg, path: Path, city: str, file_hash: str, file_size: int) -> int:
    return int(cur.execute(
        f"""INSERT INTO {AUDIT_TABLE}
          (pipeline_name, source_file, rows_read, rows_loaded, rows_rejected,
           run_status, process_code, city_code, file_sha256, source_bytes,
           origin_mode, ingestion_version)
          OUTPUT INSERTED.run_id
          VALUES (?, ?, 0, 0, 0, 'RUNNING', ?, ?, ?, ?, 'NEW_FILE', '2.1')""",
        f"LoadRaw{cfg['code']}V2", path.name, cfg["code"], city, file_hash, file_size,
    ).fetchval())


def register_legacy(conn, cfg, path: Path, city: str, file_hash: str, csv_rows: int):
    cur = conn.cursor()
    if count_city(cur, cfg["table"], city) != csv_rows:
        raise RuntimeError("Jilin Raw/CSV chenh so dong: khong dang ky legacy.")
    verify_legacy_multiset(cur, cfg, city, path, csv_rows)
    if sha256_file(path) != file_hash:
        raise RuntimeError("Noi dung CSV da thay doi trong luc doi chieu. Khong ghi audit.")
    cur.execute(
        f"""INSERT INTO {AUDIT_TABLE}
          (pipeline_name, source_file, rows_read, rows_loaded, rows_rejected,
           run_status, finished_at, process_code, city_code, file_sha256,
           source_bytes, origin_mode, ingestion_version)
          VALUES (?, ?, ?, 0, 0, 'SUCCESS', SYSDATETIME(), ?, ?, ?, ?,
                  'LEGACY_VERIFIED', '2.1')""",
        f"RegisterRaw{cfg['code']}V1", path.name, csv_rows,
        cfg["code"], city, file_hash, path.stat().st_size,
    )
    conn.commit()
    print(f"[REGISTERED] {city}: CSV goc da co trong Raw; chi ghi audit, khong INSERT Raw.")


def load_new_file(conn, cfg, path: Path, city: str, file_hash: str, csv_rows: int,
                  batch_size: int):
    audit_cur = conn.cursor()
    run_id = insert_started_run(audit_cur, cfg, path, city, file_hash, path.stat().st_size)
    conn.commit()  # Keep RUNNING entry if the data transaction later fails.

    loaded = 0
    try:
        cur = conn.cursor()
        if count_city(cur, cfg["table"], city) != 0:
            raise RuntimeError("Thanh pho da co Raw trong luc nap: tu choi ghi de.")
        cols = cfg["cols"]
        insert_sql = (
            f"INSERT INTO {cfg['table']} (" + ", ".join(f"[{c}]" for c in cols) + ") "
            "VALUES (" + ", ".join("?" for _ in cols) + ")"
        )
        inserter = conn.cursor()
        inserter.fast_executemany = True
        batch = []
        for _, row in iter_csv(path, cols):
            batch.append(row)
            loaded += 1
            if len(batch) >= batch_size:
                inserter.executemany(insert_sql, batch)
                batch.clear()
                if loaded % 20000 == 0:
                    print(f"  Inserted {loaded:,} rows...", flush=True)
        if batch:
            inserter.executemany(insert_sql, batch)
        if loaded != csv_rows:
            raise RuntimeError("CSV row_count da thay doi giua lan kiem tra va nap")
        if sha256_file(path) != file_hash:
            raise RuntimeError("CSV da thay doi trong luc nap; rollback")
        stored = count_city(cur, cfg["table"], city)
        if stored != csv_rows:
            raise RuntimeError(f"Raw thuc te {stored:,}, CSV {csv_rows:,}; rollback")
        cur.execute(
            f"""UPDATE {AUDIT_TABLE}
                SET finished_at = SYSDATETIME(), rows_read = ?, rows_loaded = ?,
                    rows_rejected = 0, run_status = 'SUCCESS', error_message = NULL
                WHERE run_id = ?""",
            loaded, stored, run_id,
        )
        conn.commit()  # Atomic: Raw INSERT and SUCCESS audit status together.
        print(f"[SUCCESS] {cfg['table']} / {city}: {stored:,} dong (run_id={run_id}).")
    except Exception as exc:
        conn.rollback()
        try:
            audit_cur.execute(
                f"""UPDATE {AUDIT_TABLE}
                    SET finished_at = SYSDATETIME(), rows_read = ?, rows_loaded = 0,
                        rows_rejected = 0, run_status = 'FAILED', error_message = ?
                    WHERE run_id = ?""",
                loaded, str(exc)[:2000], run_id,
            )
            conn.commit()
        except Exception:
            conn.rollback()
        raise


def main():
    parser = argparse.ArgumentParser(
        description="LaDe ingestion v2.1: full CSV per city, safe legacy registration, audit reuse."
    )
    parser.add_argument("--process", required=True, choices=tuple(PROCESSES))
    parser.add_argument("--city", required=True, help="City as in CSV: Jilin, Hangzhou, ...")
    parser.add_argument("--file", required=True, type=Path, help="CSV path")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="Validate only; no DB changes")
    action.add_argument("--register-existing", action="store_true", help="Verify CSV against existing Raw and register legacy audit")
    action.add_argument("--load", action="store_true", help="Insert a NEW city's complete CSV")
    parser.add_argument("--server", default=os.getenv("SQL_SERVER", r".\SQLEXPRESS"))
    parser.add_argument("--database", default=os.getenv("SQL_DATABASE", "ExpressCourierDW"))
    parser.add_argument("--batch-size", type=int, default=2000)
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error("--batch-size phai > 0")
    city = args.city.strip().upper()
    if not city or len(city) > 100:
        parser.error("--city khong hop le")
    path = args.file.expanduser().resolve()
    if not path.is_file():
        parser.error(f"Khong tim thay file: {path}")
    if len(path.name) > 260:
        parser.error("Ten file vuot 260 ky tu (cot audit.source_file)")
    cfg = PROCESSES[args.process]
    print(f"[START] {cfg['code']} / {city}: {path}", flush=True)
    print("[PREFLIGHT] Kiem tra CSV va order_id...", flush=True)
    csv_rows = check_csv(path, cfg["cols"], city)
    file_hash = sha256_file(path)
    print(f"[OK] CSV={csv_rows:,} dong; SHA256={file_hash}", flush=True)

    conn = connect(args.server, args.database)
    try:
        cur = conn.cursor()
        actual_db = cur.execute("SELECT DB_NAME()").fetchval()
        if actual_db.lower() != args.database.lower():
            raise RuntimeError(f"Ket noi sai DB: {actual_db}")
        verify_sql_structure(cur, cfg)
        existing_rows = count_city(cur, cfg["table"], city)
        audit = successful_city_record(cur, cfg["code"], city)
        conn.commit()  # Release read transaction before next stage.
        print(f"[STATE] Raw city rows={existing_rows:,}; "
              f"audit success={'YES' if audit else 'NO'}", flush=True)

        if args.check:
            if audit:
                print(f"[CHECK] Da co ban SUCCESS: run_id={audit[0]}, "
                      f"origin={audit[3]}, checksum={audit[1]}")
            elif existing_rows:
                print("[CHECK] Raw da co du lieu ma audit v2 chua co: dung --register-existing de xac minh.")
            else:
                print("[CHECK] Thanh pho chua co Raw: co the --load file moi.")
            return

        if audit:
            if str(audit[1]).strip() == file_hash and int(audit[2]) == csv_rows:
                if existing_rows != csv_rows:
                    raise RuntimeError("Audit da SUCCESS nhung so dong Raw khac CSV: STOP.")
                print(f"[SKIP] File da duoc ghi nhan (run_id={audit[0]}); khong nap trung.")
                return
            raise RuntimeError("Thanh pho da co audit SUCCESS nhung checksum/count khac. "
                               "v2 chua ho tro thay the hoac append cung thanh pho.")

        if args.register_existing:
            if existing_rows == 0:
                raise RuntimeError("Khong co Raw de dang ky. File moi phai dung --load.")
            register_legacy(conn, cfg, path, city, file_hash, csv_rows)
        elif args.load:
            if existing_rows:
                raise RuntimeError("Raw thanh pho nay da co du lieu nhung chua ghi audit v2. "
                                   "KHONG nap lai: can --register-existing sau khi doi chieu CSV.")
            load_new_file(conn, cfg, path, city, file_hash, csv_rows, args.batch_size)
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print(f"[ERROR] {err}", file=sys.stderr)
        sys.exit(1)
