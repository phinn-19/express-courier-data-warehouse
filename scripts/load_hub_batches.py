"""ExpressCourierDW - Hub SIMULATED batch loader (HUB_DATA_CONTRACT v1.1, mục 7).

Nạp output của generate_hub_simulation.py vào sim_raw.Hubs / Shipments / HubEvents
và ghi audit.HubETLBatchLog. Mỗi đơn vị nạp (Hubs, Shipments, từng batch event)
là MỘT transaction: lỗi thì rollback toàn bộ đơn vị đó, không nạp dở dang.

Quy tắc idempotent:
- Cùng khóa + cùng payload  => SKIP (replay không nhân đôi).
- Cùng khóa + payload khác  => REJECT: rollback, log FAILED, dừng. Không ghi đè.
- sim_raw đã chứa simulation_run_id KHÁC => từ chối, không trộn 2 dataset.
- Chỉ ghi SUCCESS sau khi commit.

KHÔNG dùng cho LaDe Pickup/Delivery (đó là 03_Load_Raw_Idempotent_v2.py).
KHÔNG chạy nhiều bản loader cùng lúc. Không DROP / DELETE / TRUNCATE / UPDATE dữ liệu.

Cách chạy (Windows, project root; chạy sql/10_Create_Hub_SimRaw.sql trước):
    $PY = ".\\.venv-dbt\\Scripts\\python.exe"
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --check
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --load --until-batch HUB-V1-B002
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --load      # nạp tiếp phần còn lại
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --load      # replay: toàn SKIP
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --conflict-test
    & $PY scripts\\load_hub_batches.py --input-dir data\\hub\\generated --status
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import sys

DATA_ORIGIN = "SIMULATED"
HUBS_UNIT = "HUB-V1-HUBS"
SHIPMENTS_UNIT = "HUB-V1-SHIPMENTS"
CONFLICT_UNIT = "HUB-V1-CONFLICT-TEST"

# Định danh cố định trong code, không nhận tên bảng từ người dùng.
TABLES = {
    "hubs.csv": {
        "target": "[sim_raw].[Hubs]",
        "key": ["hub_id"],
        "columns": ["hub_id", "city_code", "hub_name", "data_origin"],
        "timestamps": [],
    },
    "shipments.csv": {
        "target": "[sim_raw].[Shipments]",
        "key": ["sim_shipment_id"],
        "columns": ["sim_shipment_id", "origin_pickup_task_key", "city_code", "hub_id",
                    "pickup_completed_at", "simulation_run_id", "data_origin"],
        "timestamps": ["pickup_completed_at"],
    },
    "hub_events.csv": {
        "target": "[sim_raw].[HubEvents]",
        "key": ["event_id"],
        # batch_id trong CSV được nạp vào cột batch_id của HubEvents.
        "columns": ["event_id", "sim_shipment_id", "event_type", "event_ts", "batch_id",
                    "simulation_run_id", "data_origin"],
        "timestamps": ["event_ts"],
    },
}


class LoadError(RuntimeError):
    pass


class ConflictError(LoadError):
    """Cùng khóa nhưng payload khác dữ liệu đã nạp."""


# ---------------------------------------------------------------- files
def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_dataset(input_dir: Path) -> tuple[dict, dict[str, list[dict]], dict[str, str]]:
    """Đọc manifest + 3 CSV, kiểm tra SHA256/số dòng/header TRƯỚC khi đụng DB."""
    manifest_path = input_dir / "manifest.json"
    if not manifest_path.exists():
        raise LoadError(f"Không thấy {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("data_origin") != DATA_ORIGIN:
        raise LoadError("manifest.data_origin phải là SIMULATED")
    run_id = manifest["simulation_run_id"]

    data: dict[str, list[dict]] = {}
    hashes: dict[str, str] = {}
    by_name = {item["name"]: item for item in manifest["files"]}
    for name, spec in TABLES.items():
        meta = by_name.get(name)
        if meta is None:
            raise LoadError(f"manifest thiếu file {name}")
        path = input_dir / name
        actual_sha = sha256_file(path)
        if actual_sha != meta["sha256"]:
            raise LoadError(f"{name}: SHA256 {actual_sha} khác manifest {meta['sha256']}")
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != meta["header"] or reader.fieldnames != spec["columns"]:
                raise LoadError(f"{name}: header {reader.fieldnames} khác contract {spec['columns']}")
            rows = list(reader)
        if len(rows) != meta["rows"]:
            raise LoadError(f"{name}: {len(rows)} dòng, manifest ghi {meta['rows']}")
        for row in rows:
            if row["data_origin"] != DATA_ORIGIN:
                raise LoadError(f"{name}: có dòng data_origin != SIMULATED")
            if "simulation_run_id" in row and row["simulation_run_id"] != run_id:
                raise LoadError(f"{name}: simulation_run_id khác manifest")
        data[name] = rows
        hashes[name] = actual_sha

    manifest_batches = [b["batch_id"] for b in manifest["batches"]]
    file_batches = {r["batch_id"] for r in data["hub_events.csv"]}
    if set(manifest_batches) != file_batches:
        raise LoadError("Danh sách batch trong hub_events.csv khác manifest")
    return manifest, data, hashes


# ---------------------------------------------------------------- database
def connect(server: str, database: str):
    try:
        import pyodbc
    except ImportError as exc:
        raise LoadError("Chưa cài pyodbc trong Python hiện tại. Dùng .venv-dbt") from exc
    drivers = pyodbc.drivers()
    driver = next((d for d in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")
                   if d in drivers), None)
    if not driver:
        raise LoadError(f"Cần ODBC Driver 17/18 for SQL Server. Có sẵn: {drivers}")
    conn = pyodbc.connect(
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
        "Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;Connection Timeout=15;",
        autocommit=False,
    )
    return conn


def verify_structure(cur) -> None:
    needed = [("sim_raw", "Hubs"), ("sim_raw", "Shipments"), ("sim_raw", "HubEvents"),
              ("audit", "HubETLBatchLog")]
    for schema, table in needed:
        found = cur.execute(
            "SELECT 1 FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id "
            "WHERE s.name = ? AND t.name = ?", schema, table,
        ).fetchone()
        if not found:
            raise LoadError(f"Chưa có {schema}.{table}. Chạy sql/10_Create_Hub_SimRaw.sql trước.")


def verify_single_run(cur, run_id: str) -> None:
    others = cur.execute(
        "SELECT DISTINCT simulation_run_id FROM [sim_raw].[Shipments] WHERE simulation_run_id <> ? "
        "UNION SELECT DISTINCT simulation_run_id FROM [sim_raw].[HubEvents] WHERE simulation_run_id <> ?",
        run_id, run_id,
    ).fetchall()
    if others:
        raise LoadError(
            f"sim_raw đã chứa simulation_run_id khác: {[r[0] for r in others]}. "
            "Không trộn 2 dataset; dùng DB dev sạch hoặc xin ý kiến nhóm trước."
        )


def start_log(conn, unit: str, target: str, source_file: str, file_sha: str,
              payload_sha: str | None, run_id: str, rows_read: int) -> int:
    cur = conn.cursor()
    log_id = cur.execute(
        "INSERT INTO [audit].[HubETLBatchLog] (batch_id, target_table, source_file, source_file_sha256, "
        "batch_payload_sha256, simulation_run_id, rows_read, status) "
        "OUTPUT INSERTED.log_id VALUES (?, ?, ?, ?, ?, ?, ?, 'RUNNING')",
        unit, target, source_file, file_sha, payload_sha, run_id, rows_read,
    ).fetchone()[0]
    conn.commit()
    return int(log_id)


def finish_log(conn, log_id: int, status: str, inserted=None, skipped=None, rejected=None,
               error: str | None = None) -> None:
    cur = conn.cursor()
    cur.execute(
        "UPDATE [audit].[HubETLBatchLog] SET status = ?, rows_inserted = ?, rows_skipped = ?, "
        "rows_rejected = ?, error_message = ?, finished_at = SYSDATETIME() WHERE log_id = ?",
        status, inserted, skipped, rejected, (error or "")[:2000] or None, log_id,
    )
    conn.commit()


def typed(column: str, spec: dict, alias: str) -> str:
    if column in spec["timestamps"]:
        return f"CONVERT(DATETIME2(0), {alias}.[{column}], 126)"
    return f"{alias}.[{column}]"


def load_unit(conn, unit: str, file_name: str, rows: list[dict], file_sha: str,
              payload_sha: str | None, run_id: str) -> tuple[int, int]:
    """Nạp một đơn vị trong một transaction. Trả về (inserted, skipped)."""
    spec = TABLES[file_name]
    columns = spec["columns"]
    target = spec["target"]
    log_id = start_log(conn, unit, target, file_name, file_sha, payload_sha, run_id, len(rows))
    cur = conn.cursor()
    try:
        cur.execute("DROP TABLE IF EXISTS #stage;")
        cur.execute("CREATE TABLE #stage (" + ", ".join(f"[{c}] NVARCHAR(200) COLLATE DATABASE_DEFAULT NOT NULL" for c in columns) + ");")
        cur.fast_executemany = True
        cur.executemany(
            "INSERT INTO #stage (" + ", ".join(f"[{c}]" for c in columns) + ") VALUES ("
            + ", ".join("?" for _ in columns) + ")",
            [tuple(row[c] for c in columns) for row in rows],
        )
        cur.fast_executemany = False

        key_join = " AND ".join(f"t.[{k}] = s.[{k}]" for k in spec["key"])
        payload_cols = [c for c in columns if c not in spec["key"]]
        same_payload = " AND ".join(f"t.[{c}] = {typed(c, spec, 's')}" for c in payload_cols)

        conflicts = cur.execute(
            f"SELECT COUNT(*) FROM #stage s JOIN {target} t ON {key_join} WHERE NOT ({same_payload})"
        ).fetchone()[0]
        if conflicts:
            raise ConflictError(f"{conflicts} dòng cùng khóa nhưng payload khác dữ liệu đã nạp")
        skipped = cur.execute(
            f"SELECT COUNT(*) FROM #stage s JOIN {target} t ON {key_join}"
        ).fetchone()[0]

        insert_cols = columns + (["source_batch_id"] if file_name != "hub_events.csv" else [])
        select_cols = [typed(c, spec, "s") for c in columns] + (
            ["?"] if file_name != "hub_events.csv" else []
        )
        params = [unit] if file_name != "hub_events.csv" else []
        cur.execute(
            f"INSERT INTO {target} (" + ", ".join(f"[{c}]" for c in insert_cols) + ") "
            "SELECT " + ", ".join(select_cols) + " FROM #stage s "
            f"WHERE NOT EXISTS (SELECT 1 FROM {target} t WHERE {key_join})",
            *params,
        )
        inserted = cur.rowcount
        if inserted + skipped != len(rows):
            raise LoadError(f"inserted {inserted} + skipped {skipped} != rows_read {len(rows)}")
        cur.execute("DROP TABLE IF EXISTS #stage;")
        conn.commit()
    except Exception as exc:
        conn.rollback()
        rejected = len(rows) if isinstance(exc, ConflictError) else None
        finish_log(conn, log_id, "FAILED", inserted=0, rejected=rejected, error=str(exc))
        raise
    finish_log(conn, log_id, "SUCCESS", inserted=inserted, skipped=skipped, rejected=0)
    return inserted, skipped


def print_status(cur, run_id: str) -> None:
    print("--- sim_raw row counts ---")
    for table in ("[sim_raw].[Hubs]", "[sim_raw].[Shipments]", "[sim_raw].[HubEvents]"):
        print(f"{table}: {cur.execute(f'SELECT COUNT_BIG(*) FROM {table}').fetchone()[0]}")
    print("--- HubEvents theo event_type ---")
    for event_type, count in cur.execute(
        "SELECT event_type, COUNT_BIG(*) FROM [sim_raw].[HubEvents] GROUP BY event_type ORDER BY event_type"
    ).fetchall():
        print(f"{event_type}: {count}")
    print("--- audit.HubETLBatchLog (20 dòng mới nhất) ---")
    for row in cur.execute(
        "SELECT TOP (20) log_id, batch_id, status, rows_read, rows_inserted, rows_skipped, rows_rejected, "
        "CONVERT(VARCHAR(19), started_at, 126) FROM [audit].[HubETLBatchLog] "
        "WHERE simulation_run_id = ? ORDER BY log_id DESC", run_id,
    ).fetchall():
        print(" | ".join("" if v is None else str(v) for v in row))


# ---------------------------------------------------------------- main
def run(args: argparse.Namespace) -> int:
    manifest, data, hashes = read_dataset(args.input_dir)
    run_id = manifest["simulation_run_id"]
    batches = manifest["batches"]
    print(f"[OK] Manifest + SHA256 + header + số dòng khớp. simulation_run_id = {run_id}")
    for name, rows in data.items():
        print(f"[OK] {name}: {len(rows)} dòng")
    print(f"[OK] {len(batches)} batch event: {batches[0]['batch_id']} .. {batches[-1]['batch_id']}")
    if args.check:
        print("[OK] --check: không kết nối DB.")
        return 0

    conn = connect(args.server, args.database)
    cur = conn.cursor()
    verify_structure(cur)
    print(f"[OK] Kết nối {args.server} / {args.database}")

    if args.status:
        print_status(cur, run_id)
        return 0

    if args.conflict_test:
        first = sorted(data["hub_events.csv"], key=lambda r: r["event_id"])[0]
        exists = cur.execute("SELECT 1 FROM [sim_raw].[HubEvents] WHERE event_id = ?", first["event_id"]).fetchone()
        if not exists:
            raise LoadError("Cần nạp event trước khi chạy --conflict-test")
        before = cur.execute("SELECT COUNT_BIG(*) FROM [sim_raw].[HubEvents]").fetchone()[0]
        tampered = dict(first)
        # Đổi payload nhưng giữ nguyên event_id: phải bị REJECT.
        tampered["event_ts"] = tampered["event_ts"][:-2] + ("00" if tampered["event_ts"][-2:] != "00" else "01")
        try:
            load_unit(conn, CONFLICT_UNIT, "hub_events.csv", [tampered], hashes["hub_events.csv"], None, run_id)
        except ConflictError as exc:
            after = cur.execute("SELECT COUNT_BIG(*) FROM [sim_raw].[HubEvents]").fetchone()[0]
            ts_now = cur.execute(
                "SELECT CONVERT(VARCHAR(19), event_ts, 126) FROM [sim_raw].[HubEvents] WHERE event_id = ?",
                first["event_id"],
            ).fetchone()[0]
            ok = before == after and ts_now == first["event_ts"]
            print(f"[{'PASS' if ok else 'FAIL'}] Payload khác cùng event_id bị từ chối: {exc}. "
                  f"Số event trước/sau = {before}/{after}; event_ts giữ nguyên = {ts_now}")
            return 0 if ok else 1
        print("[FAIL] Payload khác KHÔNG bị từ chối")
        return 1

    # --load
    verify_single_run(cur, run_id)
    selected = batches
    if args.until_batch:
        ids = [b["batch_id"] for b in batches]
        if args.until_batch not in ids:
            raise LoadError(f"Không có batch {args.until_batch}. Có: {ids}")
        selected = batches[: ids.index(args.until_batch) + 1]

    total_inserted = 0
    for unit, name in ((HUBS_UNIT, "hubs.csv"), (SHIPMENTS_UNIT, "shipments.csv")):
        inserted, skipped = load_unit(conn, unit, name, data[name], hashes[name], None, run_id)
        total_inserted += inserted
        print(f"[SUCCESS] {unit}: inserted {inserted}, skipped {skipped}")

    events_by_batch: dict[str, list[dict]] = {}
    for row in data["hub_events.csv"]:
        events_by_batch.setdefault(row["batch_id"], []).append(row)
    for batch in selected:
        rows = events_by_batch[batch["batch_id"]]
        inserted, skipped = load_unit(conn, batch["batch_id"], "hub_events.csv", rows,
                                      hashes["hub_events.csv"], batch.get("payload_sha256"), run_id)
        total_inserted += inserted
        print(f"[SUCCESS] {batch['batch_id']} ({batch['first_event_ts']} .. {batch['last_event_ts']}): "
              f"inserted {inserted}, skipped {skipped}")

    remaining = len(batches) - len(selected)
    print(f"[DONE] Tổng inserted {total_inserted}. Batch chưa nạp: {remaining}.")
    print_status(cur, run_id)
    return 0


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Nạp Hub SIMULATED vào sim_raw theo batch, có audit/replay")
    parser.add_argument("--input-dir", type=Path, default=Path("data/hub/generated"))
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="Chỉ kiểm tra file/manifest, không kết nối DB")
    action.add_argument("--load", action="store_true", help="Nạp Hubs, Shipments và các batch event")
    action.add_argument("--status", action="store_true", help="Xem số dòng sim_raw và audit log")
    action.add_argument("--conflict-test", action="store_true",
                        help="Chứng minh cùng event_id khác payload bị REJECT (không ghi gì)")
    parser.add_argument("--until-batch", help="Chỉ nạp tới batch này (demo nạp tăng dần)")
    parser.add_argument("--server", default=os.getenv("SQL_SERVER", r".\SQLEXPRESS"))
    parser.add_argument("--database", default=os.getenv("SQL_DATABASE", "ExpressCourierDW"))
    args = parser.parse_args()
    try:
        return run(args)
    except LoadError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
