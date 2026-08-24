#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

manifest="${AEROSPACE_CUSTOM_PATCH_MANIFEST:-custom/patches.toml}"
regression_index="${AEROSPACE_CUSTOM_REGRESSION_INDEX:?Set AEROSPACE_CUSTOM_REGRESSION_INDEX}"
run_tests=1
if test "${1:-}" = "--skip-tests"; then
    run_tests=0
    shift
fi
test $# -eq 0 || {
    printf 'Usage: %s [--skip-tests]\n' "$0" >&2
    exit 2
}

base="$(
    sed -n "s/^upstream-base = '\\([^']*\\)'$/\\1/p" "$manifest"
)"
test -n "$base" || {
    printf 'Missing upstream-base in %s\n' "$manifest" >&2
    exit 1
}
git rev-parse --verify "$base^{commit}" >/dev/null
script/verify-regression-references.sh "$manifest" "$regression_index"

subjects_file="$(mktemp)"
expected_file="$(mktemp)"
tests_file="$(mktemp)"
unmapped_file="$(mktemp)"
cleanup() {
    rm -f "$subjects_file" "$expected_file" "$tests_file" "$unmapped_file"
}
trap cleanup EXIT INT TERM

git log --reverse --format='%s' "$base..HEAD" > "$subjects_file"
sed -n "s/^commit-subject = '\\([^']*\\)'$/\\1/p" "$manifest" > "$expected_file"

if grep -Eq '^(WIP|fixup!|squash!)' "$subjects_file"; then
    printf 'Custom patch range contains WIP/fixup/squash commits:\n' >&2
    grep -E '^(WIP|fixup!|squash!)' "$subjects_file" >&2
    exit 1
fi

previous_line=0
while IFS= read -r expected; do
    count="$(grep -Fxc "$expected" "$subjects_file" || true)"
    test "$count" = 1 || {
        printf 'Expected exactly one commit with subject: %s (found %s)\n' \
            "$expected" "$count" >&2
        exit 1
    }
    line="$(
        grep -Fnx "$expected" "$subjects_file" |
            cut -d: -f1
    )"
    test "$line" -gt "$previous_line" || {
        printf 'Patch commits are not in manifest order: %s\n' "$expected" >&2
        exit 1
    }
    previous_line="$line"
done < "$expected_file"

commit_is_productive() {
    local commit="$1"
    local path
    while IFS= read -r path; do
        case "$path" in
            docs/* | dev-docs/*) ;;
            custom/README.md | custom/patches.toml) ;;
            script/verify-custom-patch-stack.sh) ;;
            script/verify-regression-references.sh) ;;
            Sources/AppBundleTests/config/CustomPatchManifestTest.swift) ;;
            *) return 0 ;;
        esac
    done < <(git diff-tree --no-commit-id --name-only -r "$commit")
    return 1
}

while IFS=$'\t' read -r commit subject; do
    if grep -Fqx "$subject" "$expected_file"; then
        continue
    fi
    if commit_is_productive "$commit"; then
        printf '%s\t%s\n' "$commit" "$subject" >> "$unmapped_file"
    fi
done < <(git log --reverse --format='%H%x09%s' "$base..HEAD")

if test -s "$unmapped_file"; then
    printf 'Unmapped productive commit(s):\n' >&2
    sed 's/^/  /' "$unmapped_file" >&2
    exit 1
fi

if test "$run_tests" = 1; then
    sed -n "s/^tests = \\[\\(.*\\)\\]$/\\1/p" "$manifest" |
        tr ',' '\n' |
        sed -e "s/^[[:space:]]*'//" -e "s/'[[:space:]]*$//" |
        sed '/^$/d' |
        sort -u > "$tests_file"

    while IFS= read -r filter; do
        swift test --filter "$filter"
    done < "$tests_file"
fi

printf 'Custom patch stack verified against %s\n' "$base"
