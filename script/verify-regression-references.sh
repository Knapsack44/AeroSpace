#!/bin/bash

set -euo pipefail

test $# -eq 2 || {
    printf 'Usage: %s PATCH_MANIFEST REGRESSION_INDEX\n' "$0" >&2
    exit 2
}

python3 - "$1" "$2" <<'PY'
import json
import pathlib
import re
import sys
import tomllib


class VerificationError(RuntimeError):
    pass


FEATURE_CLASSES_BY_PATCH_ID = {
    "custom-app-bundle": "product-identity",
    "custom-cli-routing": "runtime-target-selection",
}


def fail(message):
    raise VerificationError(message)


def load_toml(path):
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot parse patch manifest {path}: {error}")


def load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"cannot parse regression index {path}: {error}")


def require_string(value, field):
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be a non-empty string")
    return value


def load_cases(index):
    if not isinstance(index, dict) or index.get("schema-version") != 1:
        fail("regression index must use schema-version 1")
    cases = index.get("cases")
    if not isinstance(cases, list) or any(not isinstance(case, dict) for case in cases):
        fail("regression index cases must be an array of objects")
    cases_by_id = {}
    for case in cases:
        case_id = require_string(case.get("id"), "regression case id")
        if case_id in cases_by_id:
            fail(f"duplicate regression ID {case_id}")
        cases_by_id[case_id] = case
    return cases_by_id


def require_patch_back_reference(case, case_id, patch_id):
    relations = case.get("relations")
    patch_ids = relations.get("patch-ids") if isinstance(relations, dict) else None
    if not isinstance(patch_ids, list) or patch_id not in patch_ids:
        fail(f"regression {case_id} does not reference patch {patch_id}")


def validate_regressions(patch, patch_id, cases_by_id):
    regressions = patch.get("regressions")
    if not isinstance(regressions, list) or not regressions:
        fail(f"patch {patch_id} regressions must be a non-empty array")
    seen = set()
    for case_id in regressions:
        if not isinstance(case_id, str) or re.fullmatch(r"ASR-[0-9]{4}", case_id) is None:
            fail(f"patch {patch_id} has malformed regression ID {case_id!r}")
        if case_id in seen:
            fail(f"patch {patch_id} repeats regression ID {case_id}")
        seen.add(case_id)
        if case_id not in cases_by_id:
            fail(f"patch {patch_id} references unknown regression ID {case_id}")
        require_patch_back_reference(cases_by_id[case_id], case_id, patch_id)


def validate_feature_contract(patch, patch_id):
    feature_class = require_string(patch.get("feature-class"), f"patch {patch_id} feature-class")
    known_feature_classes = set(FEATURE_CLASSES_BY_PATCH_ID.values())
    if feature_class not in known_feature_classes:
        fail(f"patch {patch_id} has unknown feature-class {feature_class}")
    expected_feature_class = FEATURE_CLASSES_BY_PATCH_ID.get(patch_id)
    if expected_feature_class is None:
        fail(f"patch {patch_id} is not registered as a feature-only patch")
    if feature_class != expected_feature_class:
        fail(f"patch {patch_id} feature-class must be {expected_feature_class}")
    rationale = patch.get("feature-rationale")
    require_string(rationale, f"patch {patch_id} feature-rationale")


def validate_patch(patch, cases_by_id):
    if not isinstance(patch, dict):
        fail("patch entries must be tables")
    patch_id = require_string(patch.get("id"), "patch id")
    require_string(patch.get("commit-subject"), f"patch {patch_id} commit-subject")
    has_regressions = "regressions" in patch
    has_feature_class = "feature-class" in patch
    has_rationale = "feature-rationale" in patch
    if has_regressions:
        if has_feature_class or has_rationale:
            fail(
                f"patch {patch_id} requires regressions or a feature-class with "
                "feature-rationale, but not both"
            )
        validate_regressions(patch, patch_id, cases_by_id)
    else:
        if not has_feature_class or not has_rationale:
            fail(
                f"patch {patch_id} requires regressions or a feature-class with "
                "feature-rationale"
            )
        validate_feature_contract(patch, patch_id)
    return patch_id


def verify(manifest_path, index_path):
    manifest = load_toml(manifest_path)
    if not isinstance(manifest, dict) or manifest.get("schema-version") != 1:
        fail("patch manifest must use schema-version 1")
    patches = manifest.get("patch")
    if not isinstance(patches, list) or not patches:
        fail("patch manifest must contain at least one patch")
    cases_by_id = load_cases(load_json(index_path))
    seen_patch_ids = set()
    for patch in patches:
        patch_id = validate_patch(patch, cases_by_id)
        if patch_id in seen_patch_ids:
            fail(f"duplicate patch ID {patch_id}")
        seen_patch_ids.add(patch_id)


try:
    verify(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
except VerificationError as error:
    print(f"Regression reference verification: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
