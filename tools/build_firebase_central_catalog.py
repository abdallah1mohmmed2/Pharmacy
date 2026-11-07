#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build privacy-safe Firebase Hosting JSON shards for the central drug catalogue.

Usage:
  python tools/build_firebase_central_catalog.py \
    --input merged_19points_drugs.json \
    --output firebase_public/v1/catalog \
    --catalog-version 20261108

The input is a reference catalogue only. Operational ERP values are stripped
recursively before any public JSON is written.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

PAGE_SIZE = 30
BARCODE_RE = re.compile(r"^\d{8,14}$")

# Keys are normalized before comparison; the list intentionally errs on the
# side of removing operational/financial data from a public reference source.
OPERATIONAL_KEYS = {
    "cost_price_pack", "cost_price", "purchase_price", "buy_price",
    "sell_price_pack", "sell_price", "sale_price", "retail_price",
    "wholesale_price", "price", "prices", "unit_price", "pack_price",
    "stock_total_units", "stock", "quantity", "qty", "available_quantity",
    "reserved_quantity", "on_hand", "inventory", "inventory_balance",
    "batches", "batch", "batch_no", "batch_number", "lot", "lot_number",
    "expiry", "expiry_date", "expiration_date", "warehouse", "warehouse_id",
    "shelf", "shelf_id", "supplier", "supplier_id", "supplier_name",
    "purchase_invoice", "purchase_invoice_id", "sales_invoice",
    "sales_invoice_id", "movement", "stock_movements", "inventory_movements",
    "branch_id", "pharmacy_id", "account_id", "balance", "credit", "debit",
    "receivable", "payable", "ledger", "lah_alayh_ledger", "sync_queue",
    "audit_logs", "cashbox", "cash_balance", "profit", "margin",
    "discount", "tax", "bonus_quantity", "reorder_level", "minimum_stock",
    "maximum_stock", "last_purchase", "last_sale", "average_cost",
    "weighted_average_cost", "opening_balance", "financial_status",
}

def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.casefold())

BLOCKED_KEYS = {normalize_key(key) for key in OPERATIONAL_KEYS}

def strip_operational(value: Any) -> Any:
    if isinstance(value, dict):
        cleaned = {}
        for key, child in value.items():
            if normalize_key(str(key)) in BLOCKED_KEYS:
                continue
            cleaned[str(key)] = strip_operational(child)
        return cleaned
    if isinstance(value, list):
        return [strip_operational(item) for item in value]
    return value

def normalize_text(value: Any) -> str:
    text = str(value or "").strip().casefold()
    for source, target in (("أ", "ا"), ("إ", "ا"), ("آ", "ا"),
                           ("ى", "ي"), ("ة", "ه")):
        text = text.replace(source, target)
    text = re.sub(r"[\u064b-\u065f\u0670]", "", text)
    return re.sub(r"\s+", " ", text)

def first_value(item: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = item.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""

def searchable_text(item: dict[str, Any]) -> str:
    fields = (
        "trade_name_ar", "trade_name_en", "scientific_name",
        "active_ingredient", "active_ingredient_name",
        "chemical_composition", "atc_code", "therapeutic_class",
        "pharmacologic_class", "dosage_form", "strength_text",
        "manufacturer_name", "manufacturer",
    )
    values = [str(item.get(key, "")) for key in fields]
    values.append(str(item.get("search_text", "")))
    return normalize_text(" ".join(values))

def load_records(path: Path) -> tuple[list[dict[str, Any]], int | None]:
    with path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    version = None
    if isinstance(payload, dict):
        raw_version = payload.get("catalog_version")
        if isinstance(raw_version, int) and raw_version > 0:
            version = raw_version
        records = payload.get("items", payload.get("data", payload.get("drugs")))
    else:
        records = payload
    if not isinstance(records, list):
        raise ValueError("Input JSON must be an array or an object containing items[], data[], or drugs[].")
    cleaned = []
    for index, raw in enumerate(records):
        if not isinstance(raw, dict):
            raise ValueError(f"Record #{index + 1} is not a JSON object.")
        item = strip_operational(raw)
        if not first_value(item, "catalog_uuid", "uuid"):
            raise ValueError(f"Record #{index + 1} has no catalog_uuid/uuid.")
        try:
            record_version = int(item.get("catalog_version", item.get("version", 0)))
        except (TypeError, ValueError):
            record_version = 0
        if record_version < 1:
            raise ValueError(f"Record #{index + 1} has no positive catalog_version.")
        if not first_value(item, "trade_name_ar", "tradeNameAr"):
            raise ValueError(f"Record #{index + 1} has no trade_name_ar.")
        item["catalog_uuid"] = first_value(item, "catalog_uuid", "uuid")
        item["catalog_version"] = record_version
        item["search_text"] = searchable_text(item)
        cleaned.append(item)
    return cleaned, version

def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("merged_19points_drugs.json"))
    parser.add_argument("--output", type=Path, default=Path("firebase_public/v1/catalog"))
    parser.add_argument("--catalog-version", type=int, default=None)
    args = parser.parse_args()

    if not args.input.is_file():
        print(f"ERROR: source catalogue not found: {args.input}", file=sys.stderr)
        print("Provide the reviewed merged_19points_drugs.json file with --input.", file=sys.stderr)
        return 2

    try:
        records, input_version = load_records(args.input)
        version = args.catalog_version or input_version or 0
        if version < 1:
            raise ValueError("Set --catalog-version or provide catalog_version in the input JSON.")
        if not records:
            raise ValueError("Refusing to publish an empty catalogue.")

        output = args.output
        if output.exists():
            # Remove only generated JSON files; do not delete unrelated Hosting assets.
            for generated in output.rglob("*.json"):
                generated.unlink()

        grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
        barcode_index: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for item in records:
            name = first_value(item, "trade_name_ar", "tradeNameAr")
            prefix = "".join(list(normalize_text(name))[:2])
            if not prefix:
                raise ValueError(f"Cannot derive a search prefix for {item['catalog_uuid']}.")
            grouped[prefix].append(item)
            for key in ("barcode_international", "barcode_local", "barcode"):
                barcode = first_value(item, key)
                if BARCODE_RE.fullmatch(barcode):
                    barcode_index[barcode].append(item)

        search_dir = output / "search"
        for prefix, entries in sorted(grouped.items()):
            entries.sort(key=lambda row: (normalize_text(row.get("trade_name_ar")), row["catalog_uuid"]))
            pages = [entries[i:i + PAGE_SIZE] for i in range(0, len(entries), PAGE_SIZE)]
            for page_number, page_items in enumerate(pages, start=1):
                shard_name = prefix if page_number == 1 else f"{prefix}_p{page_number}"
                next_cursor = f"{prefix}_p{page_number + 1}" if page_number < len(pages) else None
                write_json(search_dir / f"{shard_name}.json", {
                    "ok": True,
                    "catalog_version": version,
                    "count": len(page_items),
                    "next_cursor": next_cursor,
                    "items": page_items,
                })

        for barcode, matches in sorted(barcode_index.items()):
            if len(matches) > 1:
                raise ValueError(f"Duplicate exact barcode {barcode}: {len(matches)} records.")
            write_json(output / "barcodes" / f"{barcode}.json", {
                "ok": True,
                "catalog_version": version,
                "count": 1,
                "next_cursor": None,
                "items": matches,
            })

        digest = hashlib.sha256()
        for path in sorted(output.rglob("*.json")):
            digest.update(path.relative_to(output).as_posix().encode("utf-8"))
            digest.update(path.read_bytes())
        etag = f'W/"cat-v{version}-{digest.hexdigest()[:16]}"'
        write_json(output / "manifest.json", {
            "ok": True,
            "catalog_version": version,
            "etag": etag,
            "record_count": len(records),
            "barcode_count": len(barcode_index),
            "prefix_count": len(grouped),
            "page_size": PAGE_SIZE,
            "search_prefix_length": 2,
        })
        print(
            f"Built {len(records)} records, {len(grouped)} prefixes, "
            f"{len(barcode_index)} exact barcodes at {output}"
        )
        print(f"catalog_version={version} etag={etag}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
