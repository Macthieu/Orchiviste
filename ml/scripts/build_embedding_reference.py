from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Construit un index JSONL de references semantiques a partir des règles de nommage et du plan de classification."
    )
    parser.add_argument("--rules-dir", default="OrchivisteAPI/configs/naming/rules")
    parser.add_argument("--taxonomy", default="OrchivisteAPI/configs/analysis/taxonomy/syged_2026.json")
    parser.add_argument("--output", default="ml/datasets/labeled/embedding_reference.jsonl")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    records = []
    records.extend(load_rule_records(Path(args.rules_dir)))
    records.extend(load_taxonomy_records(Path(args.taxonomy)))
    records.extend(default_document_type_records())

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"Références écrites : {len(records)}")
    print(f"Fichier de sortie  : {output}")
    return 0


def load_rule_records(rules_dir: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not rules_dir.exists():
        return records

    for path in sorted(rules_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        metadata = raw.get("metadata") or {}
        conditions = raw.get("conditions") or {}
        signals = conditions.get("signals_any") or []
        text = " ".join(
            part for part in [
                raw.get("label"),
                raw.get("document_family"),
                raw.get("template"),
                " ".join(signals),
            ] if part
        )
        records.append({
            "reference_id": raw["id"],
            "reference_kind": "naming_rule",
            "text": text,
            "label": raw.get("label"),
            "class_code": metadata.get("suggested_class_code"),
            "rule_id": raw["id"],
            "preset_id": None,
            "path_hint": str(path),
            "metadata_type_document": infer_type_from_family(raw.get("document_family")),
        })
    return records


def load_taxonomy_records(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    raw = json.loads(path.read_text(encoding="utf-8"))
    records: list[dict[str, Any]] = []

    def walk(nodes: list[dict[str, Any]], trail: list[str]) -> None:
        for node in nodes:
            code = str(node.get("code") or "").strip()
            title = str(node.get("title") or node.get("label") or "").strip()
            if not code:
                continue
            current_trail = trail + ([title] if title else [])
            path_hint = " > ".join(part for part in current_trail if part)
            text = " ".join(part for part in [code, title, path_hint] if part)
            records.append({
                "reference_id": code,
                "reference_kind": "class_code",
                "text": text,
                "label": title,
                "class_code": code,
                "rule_id": None,
                "preset_id": None,
                "path_hint": path_hint,
                "metadata_type_document": infer_type_from_title(title),
            })
            children = node.get("children") or []
            if children:
                walk(children, current_trail)

    walk(raw.get("root") or [], [])
    return records


def default_document_type_records() -> list[dict[str, Any]]:
    return [
        {
            "reference_id": "Resolution",
            "reference_kind": "document_type",
            "text": "resolution extrait du proces-verbal conseil municipal decision gouvernance",
            "label": "Résolution",
            "class_code": "ADM-RES",
            "rule_id": "rule_resolution_conseil_municipal",
            "preset_id": "preset_resolution",
            "path_hint": "",
            "metadata_type_document": "Resolution",
        },
        {
            "reference_id": "Entente",
            "reference_kind": "document_type",
            "text": "entente contrat convention bail protocole avenant partenariat",
            "label": "Entente",
            "class_code": "ADM-ENT",
            "rule_id": "rule_entente_uniformisee",
            "preset_id": "preset_default",
            "path_hint": "",
            "metadata_type_document": "Entente",
        },
        {
            "reference_id": "ProcesVerbal",
            "reference_kind": "document_type",
            "text": "proces-verbal pv seance comite conseil municipal",
            "label": "Procès-verbal",
            "class_code": "ADM-PV",
            "rule_id": None,
            "preset_id": "preset_pv",
            "path_hint": "",
            "metadata_type_document": "ProcesVerbal",
        },
    ]


def infer_type_from_family(family: str | None) -> str | None:
    value = (family or "").casefold()
    if "resolution" in value:
        return "Resolution"
    if "entente" in value:
        return "Entente"
    return None


def infer_type_from_title(title: str | None) -> str | None:
    value = (title or "").casefold()
    if "résolution" in value or "resolution" in value:
        return "Resolution"
    if "procès-verbal" in value or "proces-verbal" in value:
        return "ProcesVerbal"
    if "entente" in value or "contrat" in value:
        return "Entente"
    if "facture" in value:
        return "Facture"
    if "permis" in value:
        return "Permis"
    return None


if __name__ == "__main__":
    raise SystemExit(main())
