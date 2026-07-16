#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

manifest="${AEROSPACE_CUSTOM_PATCH_MANIFEST:-custom/patches.toml}"
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

subjects_file="$(mktemp)"
expected_file="$(mktemp)"
tests_file="$(mktemp)"
cleanup() {
    rm -f "$subjects_file" "$expected_file" "$tests_file"
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
