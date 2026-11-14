"""ExpressCourierDW - Hub simulation generator (HUB_DATA_CONTRACT v1.1).

Đọc mẫu Pickup THẬT (pickup_reference.csv do B xuất, không commit) và sinh dữ
liệu Hub GIẢ LẬP: hubs.csv, shipments.csv, hub_events.csv, manifest.json.

Tính chất bắt buộc theo contract:
- Deterministic: cùng pickup_reference + seed + config + version => CSV trùng byte.
  Không dùng đồng hồ hệ thống, không phụ thuộc thứ tự dòng input.
- ID: sim_shipment_id = SIMSHIP- + SHA256("hub-v1|<task_key>")
      event_id        = SIMEVT-  + SHA256("hub-v1|<sim_shipment_id>|<event_type>")
- Mọi dòng mới có data_origin = SIMULATED.
- UTF-8 không BOM, newline \\n, header cố định, sort theo PK, timestamp tới giây.

Cách chạy (Windows, từ project root):
    .\\.venv-dbt\\Scripts\\python.exe scripts\\generate_hub_simulation.py `
        --input data\\hub\\pickup_reference.csv `
        --config config\\hub_simulation.example.yml

    # Chỉ kiểm tra input + config, không ghi file
    ... --check-only

    # Chứng minh tái lập: sinh lại vào bộ nhớ và so SHA256 với manifest đã có
    ... --verify data\\hub\\generated\\manifest.json

Script không kết nối database.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
import re
import sys

GENERATOR_VERSION = "hub-generator-1.0.0"
ID_NAMESPACE = "hub-v1"
DATA_ORIGIN = "SIMULATED"
TS_FORMAT = "%Y-%m-%dT%H:%M:%S"
ALLOWED_CITIES = ("JILIN", "YANTAI")
MODEL_YEAR = 2022  # dw.dim_date chỉ chứa năm 2022

REFERENCE_HEADER = ["task_key", "city_code", "completed_at", "quality_status"]
HUBS_HEADER = ["hub_id", "city_code", "hub_name", "data_origin"]
SHIPMENTS_HEADER = [
    "sim_shipment_id", "origin_pickup_task_key", "city_code", "hub_id",
    "pickup_completed_at", "simulation_run_id", "data_origin",
]
EVENTS_HEADER = [
    "event_id", "sim_shipment_id", "event_type", "event_ts", "batch_id",
    "simulation_run_id", "data_origin",
]
# (event_type, delay key trong config). Thứ tự = thứ tự nghiệp vụ.
EVENT_STEPS = (
    ("HUB_RECEIVED", "pickup_to_received"),
    ("SORTING_COMPLETED", "received_to_sorted"),
    ("HUB_DEPARTED", "sorted_to_departed"),
)
HUB_ID_PATTERN = re.compile(r"^SIMHUB-(JILIN|YANTAI)-\d{2}$")

SCOPE_NOTE = (
    "Du lieu Hub la SIMULATED (kich ban kiem chung kha nang mo rong DW). "
    "Moi shipment gia lap gan voi toi da 1 Pickup task that theo GIA DINH 1 task -> 1 shipment; "
    "task_key khong phai shipment ID that. Delay la phan bo gia dinh de test, "
    "khong phai so lieu Hub thuc te. Mau Pickup can bang theo City, khong dai dien ty trong thuc."
)


class ContractError(ValueError):
    """Input/config/output vi phạm Data Contract."""


# ---------------------------------------------------------------- helpers
def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def hash_unit(*parts: object) -> float:
    """Số thực deterministic trong [0, 1) từ SHA256 của các thành phần."""
    digest = sha256_hex("|".join(str(p) for p in parts))
    return int(digest[:16], 16) / float(1 << 64)


def parse_ts(value: str, where: str) -> datetime:
    try:
        return datetime.strptime(value, TS_FORMAT)
    except (TypeError, ValueError) as exc:
        raise ContractError(
            f"{where}: timestamp '{value}' phải đúng dạng YYYY-MM-DDTHH:MM:SS (local-naive)"
        ) from exc


def fmt_ts(value: datetime) -> str:
    return value.strftime(TS_FORMAT)


def csv_bytes(header: list[str] | None, rows: list[list[str]]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    if header is not None:
        writer.writerow(header)
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


# ---------------------------------------------------------------- config
def load_config(path: Path) -> dict:
    """Đọc config theo đúng cấu trúc file B soạn (config/hub_simulation.example.yml)
    và chuyển về dạng phẳng dùng nội bộ. Sai cấu trúc/giá trị => dừng."""
    try:
        import yaml  # PyYAML có sẵn trong .venv-dbt (dependency của dbt-core)
    except ImportError as exc:
        raise RuntimeError(
            "Cần PyYAML. Dùng .venv-dbt hoặc chạy: python -m pip install pyyaml"
        ) from exc
    with path.open("r", encoding="utf-8") as stream:
        raw = yaml.safe_load(stream)
    if not isinstance(raw, dict) or not raw:
        raise ContractError(f"Config rỗng hoặc sai định dạng: {path}")
    return normalize_config(raw)


def _section(raw: dict, name: str) -> dict:
    value = raw.get(name)
    if not isinstance(value, dict):
        raise ContractError(f"Config thiếu mục '{name}'")
    return value


def normalize_config(raw: dict) -> dict:
    for key in ("contract_version", "rules_version", "seed"):
        if key not in raw:
            raise ContractError(f"Config thiếu khóa '{key}'")
    source, scenario = _section(raw, "source"), _section(raw, "scenario")
    batching, output = _section(raw, "batching"), _section(raw, "output")

    if not isinstance(raw["seed"], int):
        raise ContractError("seed phải là số nguyên")

    cities = source.get("cities")
    if not isinstance(cities, list) or not cities or any(c not in ALLOWED_CITIES for c in cities):
        raise ContractError(f"source.cities phải là danh sách con của {ALLOWED_CITIES}")
    if source.get("filter_quality_status") != "VALID":
        raise ContractError("source.filter_quality_status phải là VALID theo contract")
    target = source.get("target_per_city")
    if not isinstance(target, int) or target <= 0:
        raise ContractError("source.target_per_city phải là số nguyên dương")
    max_completion = parse_ts(str(source.get("max_completion_exclusive")), "source.max_completion_exclusive")

    as_of = parse_ts(str(scenario.get("as_of_ts")), "scenario.as_of_ts")
    if as_of.year != MODEL_YEAR:
        raise ContractError(f"as_of_ts phải thuộc năm {MODEL_YEAR} (dw.dim_date chỉ có {MODEL_YEAR})")
    hubs_per_city = scenario.get("hubs_per_city")
    if not isinstance(hubs_per_city, int) or not 1 <= hubs_per_city <= 99:
        raise ContractError("scenario.hubs_per_city phải là số nguyên 1..99")
    expected_types = [step for step, _ in EVENT_STEPS]
    if scenario.get("event_types") != expected_types:
        raise ContractError(f"scenario.event_types phải đúng {expected_types} (rules MVP)")
    delays = scenario.get("delays_hours")
    if not isinstance(delays, dict):
        raise ContractError("Config thiếu scenario.delays_hours")
    for _, key in EVENT_STEPS:
        bounds = delays.get(key)
        if (not isinstance(bounds, list) or len(bounds) != 2
                or not all(isinstance(b, (int, float)) for b in bounds)
                or bounds[0] < 0 or bounds[0] > bounds[1]):
            raise ContractError(f"delays_hours.{key} phải là [min, max] với 0 <= min <= max")

    batch_size = batching.get("event_rows_per_batch")
    if not isinstance(batch_size, int) or batch_size <= 0:
        raise ContractError("batching.event_rows_per_batch phải là số nguyên dương")
    prefix = batching.get("batch_id_prefix")
    if not isinstance(prefix, str) or not prefix:
        raise ContractError("Config thiếu batching.batch_id_prefix")

    # Các tham số output phải trùng cách generator ghi file (không tự đổi định dạng).
    fixed = {"encoding": "utf-8", "newline": "LF", "datetime_format": TS_FORMAT,
             "data_origin": DATA_ORIGIN}
    for key, value in fixed.items():
        if str(output.get(key)) != value:
            raise ContractError(f"output.{key} phải là '{value}' (generator chỉ hỗ trợ giá trị này)")

    # Hub giả lập: SIMHUB-<CITY>-01..NN, tên giả lập (không dùng tên Hub thực).
    hubs = [
        {"hub_id": f"SIMHUB-{city}-{n:02d}", "city_code": city,
         "hub_name": f"{city.title()} Simulated Hub {n:02d}"}
        for city in sorted(cities) for n in range(1, hubs_per_city + 1)
    ]
    for hub in hubs:
        if not HUB_ID_PATTERN.match(hub["hub_id"]):
            raise ContractError(f"hub_id sinh ra sai mẫu: {hub['hub_id']}")

    return {
        "contract_version": str(raw["contract_version"]),
        "rules_version": str(raw["rules_version"]),
        "seed": raw["seed"],
        "as_of_ts": fmt_ts(as_of),
        "cities": sorted(cities),
        "target_per_city": target,
        "max_completion_exclusive": max_completion,
        "hubs": hubs,
        "delays_hours": {key: list(delays[key]) for _, key in EVENT_STEPS},
        "batch_size": batch_size,
        "batch_prefix": prefix,
        "output_directory": str(output.get("directory") or "data/hub/generated"),
        "_config_sha": config_fingerprint(raw),
    }


def config_fingerprint(cfg: dict) -> str:
    """SHA256 của config đã parse (JSON chuẩn hóa) - không phụ thuộc comment/khoảng trắng."""
    canonical = json.dumps(cfg, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)
    return sha256_hex(canonical)


# ---------------------------------------------------------------- input
def read_reference(path: Path, cfg: dict) -> list[dict]:
    rows: list[dict] = []
    seen: set[str] = set()
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        header = next(reader, None)
        if header != REFERENCE_HEADER:
            raise ContractError(
                f"Header pickup_reference sai.\n  Cần: {REFERENCE_HEADER}\n  Nhận: {header}"
            )
        for line_no, row in enumerate(reader, start=2):
            if not row:
                continue
            if len(row) != len(REFERENCE_HEADER):
                raise ContractError(f"Dòng {line_no}: có {len(row)} cột, cần {len(REFERENCE_HEADER)}")
            task_key, city, completed_raw, quality = (v.strip() for v in row)
            where = f"pickup_reference dòng {line_no}"
            if not task_key.startswith("LADE-P|"):
                raise ContractError(f"{where}: task_key phải có tiền tố 'LADE-P|'")
            if city not in cfg["cities"]:
                raise ContractError(f"{where}: city_code '{city}' không thuộc source.cities {cfg['cities']}")
            if not task_key.startswith(f"LADE-P|{city}|"):
                raise ContractError(f"{where}: city trong task_key không khớp city_code '{city}'")
            if quality != "VALID":
                raise ContractError(f"{where}: quality_status phải là VALID")
            completed = parse_ts(completed_raw, where)
            if completed.year != MODEL_YEAR:
                raise ContractError(f"{where}: completed_at phải thuộc năm {MODEL_YEAR}")
            if completed >= cfg["max_completion_exclusive"]:
                raise ContractError(f"{where}: completed_at phải < source.max_completion_exclusive")
            if task_key in seen:
                raise ContractError(f"{where}: task_key bị trùng: {task_key}")
            seen.add(task_key)
            rows.append({"task_key": task_key, "city_code": city, "completed_at": completed})
    if not rows:
        raise ContractError("pickup_reference không có dòng dữ liệu nào")
    for city, count in Counter(r["city_code"] for r in rows).items():
        if count > cfg["target_per_city"]:
            raise ContractError(f"{city} có {count} task > source.target_per_city {cfg['target_per_city']}")
    return rows


# ---------------------------------------------------------------- generation
def reference_content_sha(reference: list[dict]) -> str:
    """SHA256 nội dung reference đã chuẩn hóa và sort theo task_key.

    Dùng cho simulation_run_id để kết quả KHÔNG phụ thuộc thứ tự dòng, BOM hay
    kiểu xuống dòng của file B xuất. SHA256 byte của file vẫn ghi trong manifest.
    """
    lines = [
        f"{r['task_key']},{r['city_code']},{fmt_ts(r['completed_at'])},VALID"
        for r in sorted(reference, key=lambda r: r["task_key"])
    ]
    return sha256_hex("\n".join([",".join(REFERENCE_HEADER)] + lines))


def generate(reference: list[dict], cfg: dict, reference_sha: str) -> dict:
    seed = cfg["seed"]
    rules_version = cfg["rules_version"]
    as_of = parse_ts(str(cfg["as_of_ts"]), "config.as_of_ts")
    config_sha = cfg["_config_sha"]

    run_id = "SIMRUN-" + sha256_hex("|".join([
        ID_NAMESPACE, reference_content_sha(reference), str(seed), config_sha, GENERATOR_VERSION, rules_version,
    ]))

    hubs_by_city: dict[str, list[dict]] = defaultdict(list)
    for hub in sorted(cfg["hubs"], key=lambda h: h["hub_id"]):
        hubs_by_city[hub["city_code"]].append(hub)
    for city in {r["city_code"] for r in reference}:
        if not hubs_by_city.get(city):
            raise ContractError(f"Config không có Hub nào cho City {city}")

    shipments: list[list[str]] = []
    events: list[dict] = []
    truncated_events = 0

    for ref in reference:
        task_key = ref["task_key"]
        city = ref["city_code"]
        sim_shipment_id = "SIMSHIP-" + sha256_hex(f"{ID_NAMESPACE}|{task_key}")

        city_hubs = hubs_by_city[city]
        hub_index = int(sha256_hex(f"{seed}|{rules_version}|hub|{task_key}")[:16], 16) % len(city_hubs)
        hub_id = city_hubs[hub_index]["hub_id"]

        shipments.append([
            sim_shipment_id, task_key, city, hub_id, fmt_ts(ref["completed_at"]), run_id, DATA_ORIGIN,
        ])

        current = ref["completed_at"]
        for event_type, delay_key in EVENT_STEPS:
            low, high = cfg["delays_hours"][delay_key]
            unit = hash_unit(seed, rules_version, sim_shipment_id, event_type)
            delay_seconds = int(round((low + unit * (high - low)) * 3600))
            current = current + timedelta(seconds=delay_seconds)
            if current > as_of:
                if event_type == "HUB_RECEIVED":
                    raise ContractError(
                        f"HUB_RECEIVED của {task_key} vượt as_of_ts {cfg['as_of_ts']}; "
                        "B cần chọn as_of_ts muộn hơn hoặc lọc mẫu Pickup sớm hơn"
                    )
                # Sự kiện sau as_of chưa xảy ra trong kịch bản: shipment vẫn nằm trong Hub.
                truncated_events += 1
                break
            events.append({
                "event_id": "SIMEVT-" + sha256_hex(f"{ID_NAMESPACE}|{sim_shipment_id}|{event_type}"),
                "sim_shipment_id": sim_shipment_id,
                "event_type": event_type,
                "event_ts": current,
            })

    # Batch theo thứ tự thời gian sự kiện (event time), tie-break bằng event_id.
    batch_size = cfg["batch_size"]
    prefix = cfg["batch_prefix"]
    events_by_time = sorted(events, key=lambda e: (e["event_ts"], e["event_id"]))
    batches: list[dict] = []
    for start in range(0, len(events_by_time), batch_size):
        chunk = events_by_time[start:start + batch_size]
        batch_id = f"{prefix}{len(batches) + 1:03d}"
        for event in chunk:
            event["batch_id"] = batch_id
        batches.append({
            "batch_id": batch_id,
            "rows": len(chunk),
            "first_event_ts": fmt_ts(chunk[0]["event_ts"]),
            "last_event_ts": fmt_ts(chunk[-1]["event_ts"]),
        })

    hub_rows = [[h["hub_id"], h["city_code"], h["hub_name"], DATA_ORIGIN]
                for h in sorted(cfg["hubs"], key=lambda h: h["hub_id"])]
    shipment_rows = sorted(shipments, key=lambda r: r[0])
    event_rows = [
        [e["event_id"], e["sim_shipment_id"], e["event_type"], fmt_ts(e["event_ts"]),
         e["batch_id"], run_id, DATA_ORIGIN]
        for e in sorted(events, key=lambda e: e["event_id"])
    ]

    # SHA256 payload của từng batch (dòng CSV của batch, theo thứ tự PK) để audit.
    lines_by_batch: dict[str, list[bytes]] = defaultdict(list)
    for row in event_rows:
        lines_by_batch[row[4]].append(csv_bytes(None, [row]))
    for batch in batches:
        batch["payload_sha256"] = sha256_bytes(b"".join(lines_by_batch[batch["batch_id"]]))

    return {
        "run_id": run_id,
        "config_sha": config_sha,
        "files": {
            "hubs.csv": (HUBS_HEADER, hub_rows),
            "shipments.csv": (SHIPMENTS_HEADER, shipment_rows),
            "hub_events.csv": (EVENTS_HEADER, event_rows),
        },
        "batches": batches,
        "truncated_events": truncated_events,
        "as_of": as_of,
    }


# ---------------------------------------------------------------- self-check
def self_check(result: dict, reference: list[dict], cfg: dict) -> None:
    """Kiểm tra lại output theo các test trong mục 10 của contract. Lỗi => dừng."""
    hubs = {r[0]: r for r in result["files"]["hubs.csv"][1]}
    shipments = {r[0]: r for r in result["files"]["shipments.csv"][1]}
    events = result["files"]["hub_events.csv"][1]
    ref_by_key = {r["task_key"]: r for r in reference}
    as_of = result["as_of"]
    problems: list[str] = []

    if len(shipments) != len(result["files"]["shipments.csv"][1]):
        problems.append("sim_shipment_id không unique")
    origin_keys = [r[1] for r in shipments.values()]
    if len(set(origin_keys)) != len(origin_keys) or len(origin_keys) != len(reference):
        problems.append("Shipment count != số Pickup reference (MVP 1:1) hoặc origin task bị trùng")

    for sid, row in shipments.items():
        ref = ref_by_key.get(row[1])
        if ref is None:
            problems.append(f"{sid}: origin task không có trong reference")
            continue
        if row[2] != ref["city_code"]:
            problems.append(f"{sid}: city khác city của Pickup nguồn")
        if row[4] != fmt_ts(ref["completed_at"]):
            problems.append(f"{sid}: pickup_completed_at khác completed_at nguồn")
        hub = hubs.get(row[3])
        if hub is None or hub[1] != row[2]:
            problems.append(f"{sid}: Hub không tồn tại hoặc khác City")

    event_ids = [r[0] for r in events]
    if len(set(event_ids)) != len(event_ids):
        problems.append("event_id không unique")
    per_shipment: dict[str, dict[str, datetime]] = defaultdict(dict)
    for row in events:
        sid, event_type = row[1], row[2]
        if sid not in shipments:
            problems.append(f"{row[0]}: sim_shipment_id không tồn tại")
            continue
        if event_type in per_shipment[sid]:
            problems.append(f"{sid}: trùng event_type {event_type}")
        ts = parse_ts(row[3], "event_ts")
        if ts > as_of or ts.year != MODEL_YEAR:
            problems.append(f"{row[0]}: event_ts ngoài phạm vi as_of/năm {MODEL_YEAR}")
        per_shipment[sid][event_type] = ts

    order = [step for step, _ in EVENT_STEPS]
    for sid, row in shipments.items():
        stamps = per_shipment.get(sid, {})
        if "HUB_RECEIVED" not in stamps:
            problems.append(f"{sid}: thiếu HUB_RECEIVED")
            continue
        previous = parse_ts(row[4], "pickup_completed_at")
        for index, step in enumerate(order):
            if step not in stamps:
                if any(later in stamps for later in order[index + 1:]):
                    problems.append(f"{sid}: có sự kiện sau {step} nhưng thiếu {step}")
                break
            if stamps[step] < previous:
                problems.append(f"{sid}: {step} xảy ra trước mốc trước đó")
            previous = stamps[step]

    for name, (header, rows) in result["files"].items():
        if "data_origin" in header:
            col = header.index("data_origin")
            if any(r[col] != DATA_ORIGIN for r in rows):
                problems.append(f"{name}: có dòng data_origin khác {DATA_ORIGIN}")

    if sum(b["rows"] for b in result["batches"]) != len(events):
        problems.append("Tổng dòng các batch != số event")

    if problems:
        preview = "\n  - ".join(problems[:20])
        raise ContractError(f"Self-check FAIL ({len(problems)} lỗi):\n  - {preview}")


# ---------------------------------------------------------------- manifest
def build_manifest(result: dict, reference: list[dict], cfg: dict, reference_sha: str,
                   file_bytes: dict[str, bytes], include_generated_at: bool) -> dict:
    events = result["files"]["hub_events.csv"][1]
    shipments = result["files"]["shipments.csv"][1]
    manifest = {
        "contract_version": str(cfg["contract_version"]),
        "rules_version": cfg["rules_version"],
        "generator_version": GENERATOR_VERSION,
        "seed": cfg["seed"],
        "as_of_ts": str(cfg["as_of_ts"]),
        "pickup_reference_sha256": reference_sha,
        "pickup_reference_content_sha256": reference_content_sha(reference),
        "simulation_run_id_method": (
            "SIMRUN- + sha256('hub-v1|<content_sha256>|<seed>|<config_sha256>|"
            "<generator_version>|<rules_version>')"
        ),
        "config_sha256": result["config_sha"],
        "config_sha256_method": "sha256 of canonical JSON (sort_keys) of parsed YAML config",
        "hubs": [h["hub_id"] for h in cfg["hubs"]],
        "simulation_run_id": result["run_id"],
        "data_origin": DATA_ORIGIN,
        "scope_note": SCOPE_NOTE,
        "files": [
            {
                "name": name,
                "rows": len(rows),
                "sha256": sha256_bytes(file_bytes[name]),
                "header": header,
            }
            for name, (header, rows) in result["files"].items()
        ],
        "source_city_counts": dict(sorted(Counter(r["city_code"] for r in reference).items())),
        "shipment_city_counts": dict(sorted(Counter(r[2] for r in shipments).items())),
        "shipment_hub_counts": dict(sorted(Counter(r[3] for r in shipments).items())),
        "events_by_type": {step: sum(1 for e in events if e[2] == step) for step, _ in EVENT_STEPS},
        "events_truncated_after_as_of": result["truncated_events"],
        "delays_hours": cfg["delays_hours"],
        "batches": result["batches"],
        "load_order": ["hubs.csv", "shipments.csv"] + [b["batch_id"] for b in result["batches"]],
    }
    if include_generated_at:
        # Metadata phi quyết định: không dùng để sinh ID/CSV.
        manifest["generated_at"] = datetime.now().strftime(TS_FORMAT)
    return manifest


# ---------------------------------------------------------------- main
def run(args: argparse.Namespace) -> int:
    cfg = load_config(args.config)
    reference_sha = sha256_file(args.input)
    reference = read_reference(args.input, cfg)
    city_counts = Counter(r["city_code"] for r in reference)
    print(f"[OK] pickup_reference: {len(reference)} dòng, theo City {dict(sorted(city_counts.items()))}")
    print(f"[OK] pickup_reference_sha256 = {reference_sha}")
    for city, count in sorted(city_counts.items()):
        if count < cfg["target_per_city"]:
            print(f"[NOTE] {city} chỉ có {count} task (< {cfg['target_per_city']} mục tiêu); không tự tạo thêm task.")

    if args.check_only:
        print("[OK] --check-only: input và config hợp lệ, không ghi file.")
        return 0

    result = generate(reference, cfg, reference_sha)
    self_check(result, reference, cfg)
    file_bytes = {name: csv_bytes(header, rows) for name, (header, rows) in result["files"].items()}

    if args.verify:
        expected = json.loads(args.verify.read_text(encoding="utf-8"))
        expected_files = {f["name"]: f["sha256"] for f in expected["files"]}
        ok = expected.get("simulation_run_id") == result["run_id"]
        print(f"[{'OK' if ok else 'DIFF'}] simulation_run_id")
        for name, data in file_bytes.items():
            same = expected_files.get(name) == sha256_bytes(data)
            ok = ok and same
            print(f"[{'OK' if same else 'DIFF'}] {name} sha256 {sha256_bytes(data)}")
        print("[PASS] Sinh lại trùng byte với manifest." if ok else "[FAIL] Output khác manifest.")
        return 0 if ok else 1

    out_dir: Path = args.out_dir or Path(cfg["output_directory"])
    out_dir.mkdir(parents=True, exist_ok=True)
    targets = list(file_bytes) + ["manifest.json"]
    existing = [name for name in targets if (out_dir / name).exists()]
    if existing and not args.overwrite:
        raise ContractError(
            f"Thư mục {out_dir} đã có {existing}. Dùng --verify để so sánh, "
            "hoặc thêm --overwrite nếu chắc chắn muốn sinh đè."
        )
    for name, data in file_bytes.items():
        (out_dir / name).write_bytes(data)
    manifest = build_manifest(result, reference, cfg, reference_sha, file_bytes,
                              include_generated_at=not args.no_generated_at)
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n"
    )

    print(f"[OK] simulation_run_id = {result['run_id']}")
    for item in manifest["files"]:
        print(f"[OK] {item['name']}: {item['rows']} dòng, sha256 {item['sha256']}")
    print(f"[OK] events_by_type = {manifest['events_by_type']}")
    print(f"[OK] {len(result['batches'])} batch, sự kiện cắt sau as_of = {result['truncated_events']}")
    print(f"[PASS] Self-check theo contract mục 10 đạt. Output: {out_dir}")
    return 0


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")  # tránh lỗi in tiếng Việt khi pipe/Tee-Object
    parser = argparse.ArgumentParser(description="Sinh dữ liệu Hub SIMULATED theo HUB_DATA_CONTRACT v1.1")
    parser.add_argument("--input", type=Path, default=Path("data/hub/pickup_reference.csv"))
    parser.add_argument("--config", type=Path, default=Path("config/hub_simulation.example.yml"))
    parser.add_argument("--out-dir", type=Path, default=None,
                        help="Mặc định lấy output.directory trong config (data/hub/generated)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-only", action="store_true", help="Chỉ kiểm tra input/config")
    mode.add_argument("--verify", type=Path, metavar="MANIFEST",
                      help="Sinh lại trong bộ nhớ và so SHA256 với manifest có sẵn")
    parser.add_argument("--overwrite", action="store_true", help="Cho phép ghi đè output cũ")
    parser.add_argument("--no-generated-at", action="store_true",
                        help="Không ghi generated_at vào manifest (manifest cũng trùng byte)")
    args = parser.parse_args()
    try:
        return run(args)
    except (ContractError, FileNotFoundError) as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
