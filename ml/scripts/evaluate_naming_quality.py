from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Évalue localement la qualité du ranking de règles de nommage "
            "sur un corpus JSONL (sans envoyer ni versionner les PDF)."
        )
    )
    parser.add_argument(
        "--dataset",
        required=True,
        help="Corpus JSONL à évaluer (ex: ml/datasets/labeled/classification_external_eval.jsonl).",
    )
    parser.add_argument(
        "--rules-dir",
        default="OrchivisteAPI/configs/naming/rules",
        help="Dossier des règles déclaratives actives.",
    )
    parser.add_argument(
        "--embedding-index",
        default="",
        help="Index JSON/JSONL de références sémantiques (optionnel).",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=8,
        help="Top-K des références sémantiques considérées par document.",
    )
    parser.add_argument(
        "--max-records",
        type=int,
        default=0,
        help="Nombre max d'enregistrements (0 = tous).",
    )
    parser.add_argument(
        "--output-report",
        default="ml/datasets/labeled/naming_quality_report.json",
        help="Rapport JSON de synthèse.",
    )
    parser.add_argument(
        "--output-details-csv",
        default="ml/datasets/labeled/naming_quality_details.csv",
        help="Détails ligne à ligne (CSV).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rules = load_rules(Path(args.rules_dir))
    if not rules:
        raise SystemExit(f"Aucune règle trouvée dans: {args.rules_dir}")

    records = load_jsonl(Path(args.dataset))
    if args.max_records > 0:
        records = records[: args.max_records]
    if not records:
        raise SystemExit("Corpus vide.")

    embedding_records = load_embedding_index(Path(args.embedding_index)) if args.embedding_index else []
    enable_semantic = len(embedding_records) > 0
    if enable_semantic:
        print(f"Index sémantique chargé: {len(embedding_records)} entrées")
    else:
        print("Index sémantique inactif: score déterministe uniquement.")

    by_rule_id = {rule["id"]: rule for rule in rules}
    type_to_rule_ids = build_type_to_rule_ids(rules)

    details: list[dict[str, Any]] = []
    count_with_expected = 0
    top1_hits = 0
    top3_hits = 0
    deterministic_hits = 0
    semantic_improvements = 0
    validation_passes = 0
    validation_total = 0
    sum_final = 0.0
    sum_deterministic = 0.0
    sum_semantic = 0.0

    for record in records:
        filename = resolved_filename(record)
        text = f"{record.get('text') or ''}\n{filename}".strip()
        if not text:
            text = filename
        if not text:
            continue

        deterministic_scores = {
            rule["id"]: deterministic_score(rule, text, filename) for rule in rules
        }
        semantic_scores = (
            semantic_scores_for_record(
                text=text,
                rules=rules,
                embedding_records=embedding_records,
                top_k=max(1, args.top_k),
            )
            if enable_semantic
            else {}
        )

        ranked = rank_rules(
            rules=rules,
            deterministic_scores=deterministic_scores,
            semantic_scores=semantic_scores,
        )
        if not ranked:
            continue

        predicted_rule = ranked[0]["rule_id"]
        expected_rule = resolve_expected_rule(record, by_rule_id, type_to_rule_ids)
        if expected_rule:
            count_with_expected += 1
            if predicted_rule == expected_rule:
                top1_hits += 1
            if expected_rule in [row["rule_id"] for row in ranked[:3]]:
                top3_hits += 1
            deterministic_top = max(
                deterministic_scores.items(),
                key=lambda item: (item[1], item[0]),
            )[0]
            if deterministic_top == expected_rule:
                deterministic_hits += 1
            if deterministic_top != expected_rule and predicted_rule == expected_rule:
                semantic_improvements += 1

            expected_rule_payload = by_rule_id.get(expected_rule)
            if expected_rule_payload:
                issues = validate_filename_against_rule(filename, expected_rule_payload)
                validation_total += 1
                if not issues:
                    validation_passes += 1

        top = ranked[0]
        sum_final += top["final_score"]
        sum_deterministic += top["deterministic_score"]
        sum_semantic += top["semantic_score"]

        details.append(
            {
                "document_id": str(record.get("document_id") or ""),
                "type_document": str(record.get("type_document") or ""),
                "class_code": str(record.get("class_code") or ""),
                "filename": filename,
                "expected_rule": expected_rule or "",
                "predicted_rule": predicted_rule,
                "predicted_final_score": round(top["final_score"], 4),
                "predicted_deterministic_score": round(top["deterministic_score"], 4),
                "predicted_semantic_score": round(top["semantic_score"], 4),
                "top3_rule_ids": "|".join(row["rule_id"] for row in ranked[:3]),
                "top3_scores": "|".join(f"{row['final_score']:.4f}" for row in ranked[:3]),
            }
        )

    evaluated = len(details)
    report = {
        "dataset": args.dataset,
        "rules_dir": args.rules_dir,
        "embedding_index": args.embedding_index or None,
        "records_total": len(records),
        "records_evaluated": evaluated,
        "records_with_expected_rule": count_with_expected,
        "top1_accuracy": safe_ratio(top1_hits, count_with_expected),
        "top3_accuracy": safe_ratio(top3_hits, count_with_expected),
        "deterministic_top1_accuracy": safe_ratio(deterministic_hits, count_with_expected),
        "semantic_improvements": semantic_improvements,
        "mean_top_final_score": safe_ratio(sum_final, evaluated),
        "mean_top_deterministic_score": safe_ratio(sum_deterministic, evaluated),
        "mean_top_semantic_score": safe_ratio(sum_semantic, evaluated),
        "filename_validation_pass_rate": safe_ratio(validation_passes, validation_total),
    }

    output_report = Path(args.output_report)
    output_report.parent.mkdir(parents=True, exist_ok=True)
    output_report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    output_csv = Path(args.output_details_csv)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    write_details_csv(output_csv, details)

    print(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"Détails CSV: {output_csv}")
    return 0


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def load_rules(rules_dir: Path) -> list[dict[str, Any]]:
    if not rules_dir.exists():
        return []
    rules: list[dict[str, Any]] = []
    for path in sorted(rules_dir.glob("*.json")):
        try:
            rules.append(json.loads(path.read_text(encoding="utf-8")))
        except Exception:
            continue
    return rules


def load_embedding_index(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    if path.suffix.lower() == ".jsonl":
        records: list[dict[str, Any]] = []
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except Exception:
                    continue
        return records
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def build_type_to_rule_ids(rules: list[dict[str, Any]]) -> dict[str, list[str]]:
    mapping: dict[str, list[str]] = {}
    for rule in rules:
        rule_id = str(rule.get("id") or "").strip()
        if not rule_id:
            continue
        candidates = [
            canonical_type(str(rule.get("document_family") or "")),
            canonical_type(str(rule.get("label") or "")),
        ]
        for family in (rule.get("conditions") or {}).get("source_document_families") or []:
            candidates.append(canonical_type(str(family)))
        for key in candidates:
            if not key:
                continue
            mapping.setdefault(key, [])
            if rule_id not in mapping[key]:
                mapping[key].append(rule_id)
    return mapping


def resolve_expected_rule(
    record: dict[str, Any],
    by_rule_id: dict[str, dict[str, Any]],
    type_to_rule_ids: dict[str, list[str]],
) -> str | None:
    metadata = record.get("metadata") or {}
    metadata_rule = str(metadata.get("rule_id") or "").strip()
    if metadata_rule and metadata_rule in by_rule_id:
        return metadata_rule

    type_document = canonical_type(str(record.get("type_document") or ""))
    candidates = type_to_rule_ids.get(type_document or "", [])
    if len(candidates) == 1:
        return candidates[0]

    class_code = normalize_key(str(record.get("class_code") or ""))
    if class_code:
        scoped = [
            rule_id
            for rule_id in candidates
            if normalize_key(
                str(
                    ((by_rule_id.get(rule_id) or {}).get("metadata") or {}).get("suggested_class_code") or ""
                )
            )
            == class_code
        ]
        if len(scoped) == 1:
            return scoped[0]

    return candidates[0] if candidates else None


def deterministic_score(rule: dict[str, Any], text: str, filename: str) -> float:
    conditions = rule.get("conditions") or {}
    haystack = normalize_text(f"{text}\n{filename}")
    score = 0.0

    signals = [normalize_text(str(item)) for item in (conditions.get("signals_any") or [])]
    signal_hits = [signal for signal in signals if signal and signal in haystack]
    if signal_hits:
        score += min(0.45, len(signal_hits) * 0.12)

    regex_hits = 0
    for pattern in conditions.get("regex_any") or []:
        try:
            if re.search(str(pattern), text, flags=re.IGNORECASE | re.MULTILINE):
                regex_hits += 1
        except re.error:
            continue
    if regex_hits > 0:
        score += min(0.40, regex_hits * 0.20)

    families = [normalize_text(str(item)) for item in (conditions.get("source_document_families") or [])]
    family_hits = [family for family in families if family and family in haystack]
    if family_hits:
        score += min(0.15, len(family_hits) * 0.08)

    return max(0.0, min(1.0, score))


def semantic_scores_for_record(
    text: str,
    rules: list[dict[str, Any]],
    embedding_records: list[dict[str, Any]],
    top_k: int,
) -> dict[str, float]:
    if not embedding_records:
        return {}
    scored = []
    for record in embedding_records:
        ref_text = str(record.get("text") or "").strip()
        if not ref_text:
            continue
        score = token_similarity(text, ref_text)
        if score <= 0:
            continue
        scored.append((record, score))
    scored.sort(key=lambda item: (-item[1], str(item[0].get("reference_id") or "")))
    top_matches = scored[: max(1, top_k)]
    if not top_matches:
        return {}

    by_rule: dict[str, float] = {}
    for record, score in top_matches:
        for rule_id, weight in semantic_targets(record, rules):
            weighted = max(0.0, min(1.0, score * weight))
            if weighted > by_rule.get(rule_id, 0.0):
                by_rule[rule_id] = weighted
    return by_rule


def semantic_targets(record: dict[str, Any], rules: list[dict[str, Any]]) -> list[tuple[str, float]]:
    result: dict[str, float] = {}

    def upsert(rule_id: str, weight: float) -> None:
        if not rule_id:
            return
        result[rule_id] = max(result.get(rule_id, 0.0), max(0.0, min(1.0, weight)))

    direct_rule_id = str(record.get("rule_id") or "").strip()
    if direct_rule_id:
        upsert(direct_rule_id, 1.0)

    reference_kind = normalize_key(str(record.get("reference_kind") or ""))
    reference_id = str(record.get("reference_id") or "").strip()
    if reference_kind == "namingrule" and reference_id:
        upsert(reference_id, 0.96)

    class_code = normalize_key(str(record.get("class_code") or ""))
    if class_code:
        for rule in rules:
            rule_id = str(rule.get("id") or "").strip()
            rule_code = normalize_key(
                str(((rule.get("metadata") or {}).get("suggested_class_code") or ""))
            )
            if rule_id and rule_code == class_code:
                upsert(rule_id, 0.80)

    document_hint = canonical_type(
        str(record.get("metadata_type_document") or "")
        or str(record.get("label") or "")
    )
    if document_hint:
        for rule in rules:
            rule_id = str(rule.get("id") or "").strip()
            if not rule_id:
                continue
            signatures = [
                canonical_type(str(rule.get("document_family") or "")),
                canonical_type(str(rule.get("label") or "")),
            ] + [
                canonical_type(str(value))
                for value in ((rule.get("conditions") or {}).get("source_document_families") or [])
            ]
            if document_hint in {value for value in signatures if value}:
                upsert(rule_id, 0.72)

    return sorted(result.items(), key=lambda item: (-item[1], item[0]))


def rank_rules(
    rules: list[dict[str, Any]],
    deterministic_scores: dict[str, float],
    semantic_scores: dict[str, float],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for rule in rules:
        rule_id = str(rule.get("id") or "").strip()
        if not rule_id:
            continue
        deterministic = deterministic_scores.get(rule_id, 0.0)
        semantic = semantic_scores.get(rule_id, 0.0)
        if semantic > 0:
            final = min(1.0, deterministic * 0.30 + semantic * 0.70)
        else:
            final = deterministic
        if final <= 0:
            continue
        rows.append(
            {
                "rule_id": rule_id,
                "final_score": final,
                "deterministic_score": deterministic,
                "semantic_score": semantic,
            }
        )
    rows.sort(key=lambda row: (-row["final_score"], row["rule_id"]))
    return rows


def validate_filename_against_rule(filename: str, rule: dict[str, Any]) -> list[str]:
    issues: list[str] = []
    checks = rule.get("validations") or []
    for check in checks:
        kind = str((check or {}).get("kind") or "").strip()
        parameter = str((check or {}).get("parameter") or "")
        if not kind:
            continue
        if kind == "required_prefix":
            if parameter and not filename.startswith(parameter):
                issues.append(f"missing_prefix:{parameter}")
        elif kind == "matches_regex":
            if parameter:
                try:
                    if re.fullmatch(parameter, filename) is None:
                        issues.append("regex_mismatch")
                except re.error:
                    issues.append("regex_invalid")
        elif kind == "max_length":
            try:
                max_len = int(parameter)
                if len(filename) > max_len:
                    issues.append(f"too_long:{len(filename)}>{max_len}")
            except ValueError:
                pass
        elif kind == "exclude_phrase":
            phrase = parameter.strip()
            if phrase and normalize_text(phrase) in normalize_text(filename):
                issues.append(f"forbidden_phrase:{phrase}")
    return issues


def resolved_filename(record: dict[str, Any]) -> str:
    validated = str(record.get("validated_filename") or "").strip()
    if validated:
        return validated
    source_path = str(record.get("source_path") or "").strip()
    if source_path:
        return Path(source_path).name
    metadata = record.get("metadata") or {}
    fallback = str(metadata.get("corrected_filename") or "").strip()
    return fallback


def normalize_text(value: str) -> str:
    lowered = value.casefold().replace("’", "'")
    lowered = re.sub(r"[^\w]+", " ", lowered, flags=re.UNICODE)
    lowered = re.sub(r"\s{2,}", " ", lowered)
    return lowered.strip()


def normalize_key(value: str) -> str:
    return normalize_text(value).replace(" ", "")


def canonical_type(value: str) -> str | None:
    key = normalize_key(value)
    if not key:
        return None
    if "resolution" in key:
        return "resolution"
    if "entente" in key or "contrat" in key or "convention" in key or "bail" in key or "protocole" in key or "avenant" in key:
        return "entente"
    if "procesverbal" in key or key == "pv":
        return "procesverbal"
    if "facture" in key:
        return "facture"
    if "permis" in key:
        return "permis"
    if "avismotion" in key:
        return "avismotion"
    if "depot" in key:
        return "depot"
    return None


def token_similarity(lhs: str, rhs: str) -> float:
    lhs_tokens = set(feature_tokens(lhs))
    rhs_tokens = set(feature_tokens(rhs))
    if not lhs_tokens or not rhs_tokens:
        return 0.0
    intersection = len(lhs_tokens.intersection(rhs_tokens))
    scale = math.sqrt(len(lhs_tokens) * len(rhs_tokens))
    if scale <= 0:
        return 0.0
    return float(intersection / scale)


def feature_tokens(text: str) -> list[str]:
    normalized = normalize_text(text)
    stop_words = {
        "avec",
        "dans",
        "pour",
        "sans",
        "par",
        "sur",
        "aux",
        "des",
        "les",
        "une",
        "que",
        "qui",
        "est",
        "sont",
        "dont",
        "ceci",
        "cela",
        "ville",
        "amos",
        "conseil",
        "municipal",
        "document",
        "fichier",
        "type",
        "objet",
        "resume",
    }
    tokens = [token for token in normalized.split(" ") if token]
    return [token for token in tokens if len(token) >= 3 and token not in stop_words]


def safe_ratio(numerator: float, denominator: float) -> float:
    if denominator <= 0:
        return 0.0
    return float(numerator) / float(denominator)


def write_details_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    headers = [
        "document_id",
        "type_document",
        "class_code",
        "filename",
        "expected_rule",
        "predicted_rule",
        "predicted_final_score",
        "predicted_deterministic_score",
        "predicted_semantic_score",
        "top3_rule_ids",
        "top3_scores",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in headers})


if __name__ == "__main__":
    raise SystemExit(main())
