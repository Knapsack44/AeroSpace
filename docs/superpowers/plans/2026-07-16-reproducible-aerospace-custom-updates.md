# Reproducible AeroSpace Custom Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible, Codex-guided update and rollback system that reapplies the complete AeroSpace Custom patch stack to the newest published Beta release, installs the result automatically after validation, and preserves exactly one complete rollback version.

**Architecture:** The public fork branch `custom/main` is the authoritative integration branch for all Custom source patches, including experiments. A private repository, `Knapsack44/aerospace-custom-config`, stores the exact personal configuration for host profile `markus-macbook` and provides the `aerospace-custom-manager` command. Updates are transactional: secure current config, rebase a candidate branch onto the newest published Beta, test, build with a stable local signing identity, snapshot the current layout, create one rollback package, install, smoke-test, and only then advance `custom/main` and matching release tags.

**Tech Stack:** Git and GitHub CLI, Bash 3.2-compatible shell scripts, Swift/Xcode AeroSpace build pipeline, `jq`, macOS Keychain `security`, OpenSSL, `codesign`, `launchctl`, and native `aerospace-custom layout-memory` commands.

## Global Constraints

- Upstream updates are started manually only; never install updates from a timer, LaunchAgent, login hook, or background poll.
- Default update target is the newest published AeroSpace Beta release; upstream `main` is used only when explicitly requested.
- `custom/main` may contain experiments, but every successfully installed and smoke-tested state is stable by default until Markus reports otherwise.
- Rewrite `custom/main` only after creating and pushing an immutable backup tag; use `--force-with-lease`, never an unconditional force push.
- Keep upstream contribution branches isolated from `custom/main`; each upstream PR branch contains one contribution only.
- Keep each durable Custom function in its own atomic commit. Fold WIP, build-fix, formatting, and lint-only follow-ups into their owning functional commit.
- Automatically retire a Custom patch only when the new upstream release provides demonstrably equivalent behavior and the retained regression tests pass.
- Store GitHub source, configuration, metadata, and tags only. Never commit app binaries, CLI binaries, layout snapshots, logs, locks, backups, certificates, private keys, or `.p12` files.
- Store the exact original personal files for `markus-macbook`; do not template or normalize absolute paths.
- Commit and push managed personal configuration before every update and normal rollback. Abort on commit, secret-scan, or push failure.
- Block on suspected secrets until Codex verifies the finding or Markus explicitly approves it.
- Keep exactly one local rollback package: the immediately preceding successful installation.
- Roll back automatically only when the immediate post-install smoke test fails. Later rollback requires an explicit command.
- Normal rollback restores app, CLI, and managed configuration. Restore the saved window layout only with `rollback --restore-layout`.
- Create a pinned native layout-memory snapshot before every installation. Never restore it automatically during update.
- Use a stable local code-signing identity for every Custom build. Keep its encrypted `.p12` backup outside Git and its password in macOS Keychain.
- Stop and restart only managed AeroSpace, AeroBar, and AeroMux processes. Preserve whether each process was running and reject duplicate instances.
- Install the manager as `/usr/local/bin/aerospace-custom-manager`.
- First common release tag in both repositories is `custom-v0.21.2-beta.1`.

---

## File Map

### AeroSpace fork

- Create: `custom/patches.toml` — authoritative patch inventory, upstream base, tests, contribution status, and retirement criteria.
- Create: `custom/README.md` — explains branch policy, update policy, and relationship to the private config repository.
- Create: `script/verify-custom-patch-stack.sh` — validates patch subjects, order, upstream base, and required tests.
- Create: `Sources/AppBundle/tree/FailedRegistrationBackoff.swift` — deterministic PID retry backoff used by `MacApp`.
- Create: `Sources/AppBundleTests/tree/FailedRegistrationBackoffTest.swift` — CPU-fix regression coverage without real AX processes.
- Modify: `build-release.sh` — preserve the existing Custom app build and use a named stable signing identity without changing the vanilla release path.
- Modify: `install-custom-from-sources.sh` — delegate production installs to the manager or clearly mark this script as development-only.
- Rewrite branch history: `custom/main` — clean atomic patch stack rebased on `v0.21.2-Beta`.

### Private `aerospace-custom-config` repository

- Create: `README.md` — operator guide and disaster-recovery instructions.
- Create: `.gitignore` — excludes manager state, builds, backups, logs, snapshots, certificates, and keys.
- Create: `manifest/markus-macbook.files` — explicit list of managed source and destination paths.
- Create: `hosts/markus-macbook/home/.aerospace.toml` — exact tracked active configuration.
- Create: `hosts/markus-macbook/home/.config/aerospace/*.sh` — exact tracked AeroSpace helper scripts.
- Create: `hosts/markus-macbook/home/Library/LaunchAgents/com.markus-feilen.aerospace-layout-memory.plist` — tracked disabled legacy agent definition.
- Create: `bin/aerospace-custom-manager` — command dispatcher.
- Create: `lib/common.sh` — logging, locking, prerequisites, state paths, and error handling.
- Create: `lib/config-sync.sh` — byte-exact import/export using the manifest.
- Create: `lib/secret-scan.sh` — blocking secret scan before commits and pushes.
- Create: `lib/signing.sh` — signing identity verification and setup support.
- Create: `lib/processes.sh` — managed process capture, stop, start, and duplicate checks.
- Create: `lib/source-update.sh` — latest Beta lookup, candidate branch creation, rebase, and patch verification.
- Create: `lib/release-package.sh` — build, checksums, metadata, rollback package, install, and rollback.
- Create: `lib/smoke-test.sh` — installed app and CLI validation.
- Create: `scripts/setup-signing-identity.sh` — one-time stable certificate and encrypted backup creation.
- Create: `tests/test-helper.sh` — isolated fake HOME, commands, and assertions.
- Create: `tests/config-sync-test.sh`
- Create: `tests/secret-scan-test.sh`
- Create: `tests/processes-test.sh`
- Create: `tests/release-package-test.sh`
- Create: `tests/source-update-test.sh`
- Create: `tests/manager-cli-test.sh`

### Local runtime state, never committed

- `~/Library/Application Support/AeroSpace Custom Manager/current.json`
- `~/Library/Application Support/AeroSpace Custom Manager/rollback/`
- `~/Library/Application Support/AeroSpace Custom Manager/candidate/`
- `~/Library/Application Support/AeroSpace Custom Manager/process-state.json`
- `~/Library/Application Support/AeroSpace Custom Manager/update.log`
- `~/Library/Application Support/AeroSpace Custom/Signing Backup/AeroSpace Custom Local Code Signing.p12`

---

### Task 1: Preserve the Current Source State Before Rewriting History

**Files:**
- No source files changed.
- Create Git tag: `backup/pre-custom-main-rewrite-20260716`
- Create remote branch: `codex-fork/feature/custom-layout-memory`

**Interfaces:**
- Consumes: current `feature/custom-layout-memory` at commit `3183435c`.
- Produces: immutable remote recovery point before any history rewrite.

- [ ] **Step 1: Verify the current branch is clean and points to the tested commit**

Run:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    status --short
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    rev-parse HEAD
```

Expected:

```text
3183435c...
```

The status output must be empty. If the plan document itself is committed first, record that newer commit as the backup target instead of `3183435c`.

- [ ] **Step 2: Scan the outgoing source diff for secrets and generated artifacts**

Run:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    diff --check 649301b2..HEAD
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    diff --name-only 649301b2..HEAD |
    grep -E '(\.p12$|\.pem$|\.key$|token|secret|credential|\.release/|\.xcode-build)' &&
    exit 1 || true
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    diff 649301b2..HEAD |
    grep -Ein '(api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key|authorization:)' &&
    exit 1 || true
```

Expected: all commands exit successfully without a secret finding.

- [ ] **Step 3: Create the immutable backup tag**

Run:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    tag -a backup/pre-custom-main-rewrite-20260716 \
    -m "Preserve pre-rewrite AeroSpace Custom source state"
```

Expected: `git show-ref --tags backup/pre-custom-main-rewrite-20260716` resolves to the current branch tip.

- [ ] **Step 4: Push the recovery branch and tag to the public fork**

Run only after the required push approval:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    push codex-fork feature/custom-layout-memory
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-layout-memory \
    push codex-fork backup/pre-custom-main-rewrite-20260716
```

Expected: both refs exist in `Knapsack44/AeroSpace`.

---

### Task 2: Create the Private Config Repository and Raw Backup

**Files:**
- Create repository root: `/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config`
- Create raw files under: `raw-backup/markus-macbook/home/`
- Create: `.gitignore`
- Create Git tag: `pre-managed-config-backup`

**Interfaces:**
- Consumes: current active personal files under `/Users/markus_feilen`.
- Produces: private, pushed, byte-exact raw backup before management structure is introduced.

- [ ] **Step 1: Create the local repository with a restrictive default ignore file**

Create `.gitignore` with:

```gitignore
.DS_Store
.state/
candidate/
rollback/
build/
*.log
*.lock
*.bak
*.backup-*
*.p12
*.pem
*.key
layout-memory/
*.env
latest.tsv
latest.meta
```

Initialize:

```bash
mkdir -p /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config init -b main
```

- [ ] **Step 2: Copy the raw managed source files without modifying contents**

The raw backup must contain:

```text
raw-backup/markus-macbook/home/.aerospace.toml
raw-backup/markus-macbook/home/.config/aerospace/apply-primary-layout-profile.sh
raw-backup/markus-macbook/home/.config/aerospace/arrange-workspace-2.sh
raw-backup/markus-macbook/home/.config/aerospace/arrange-workspace-3.sh
raw-backup/markus-macbook/home/.config/aerospace/display-profile.sh
raw-backup/markus-macbook/home/.config/aerospace/enforce-secondary-workspaces.sh
raw-backup/markus-macbook/home/.config/aerospace/ensure-accordion-workspaces.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-down-smart.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-left-smart.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-monitor-ordered.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-right-smart.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-up-smart.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-workspace-stable.sh
raw-backup/markus-macbook/home/.config/aerospace/focus-workspace-window-cycle.sh
raw-backup/markus-macbook/home/.config/aerospace/maximize-workspace-3-accordion.sh
raw-backup/markus-macbook/home/.config/aerospace/move-node-to-secondary-workspace.sh
raw-backup/markus-macbook/home/.config/aerospace/pathfinder-toggle-current-workspace.sh
raw-backup/markus-macbook/home/.config/aerospace/permanent-float-current-window.sh
raw-backup/markus-macbook/home/.config/aerospace/remember-current-window-layout.sh
raw-backup/markus-macbook/home/.config/aerospace/route-teams-window.sh
raw-backup/markus-macbook/home/.config/aerospace/sanitize-languagetool-overlays.sh
raw-backup/markus-macbook/home/.config/aerospace/single-monitor-accordion-reset.sh
raw-backup/markus-macbook/home/.config/aerospace/toggle-aeromux-sidebar.sh
raw-backup/markus-macbook/home/.config/aerospace/track-workspace-window-focus.sh
raw-backup/markus-macbook/home/.config/aerospace/track-ws3-focus-state.sh
raw-backup/markus-macbook/home/.config/aerospace/workspace-layout-memory.sh
raw-backup/markus-macbook/home/Library/LaunchAgents/com.markus-feilen.aerospace-layout-memory.plist
```

Copy each listed file with this exact helper:

```bash
copy_raw_file() {
    source="$1"
    relative="${source#/Users/markus_feilen/}"
    target="raw-backup/markus-macbook/home/$relative"
    mkdir -p "$(dirname "$target")"
    cp -p "$source" "$target"
    cmp -s "$source" "$target"
}
```

Call `copy_raw_file` once for every absolute source represented in the list above. The first source is `/Users/markus_feilen/.aerospace.toml`; entries beginning `raw-backup/markus-macbook/home/` map back to `/Users/markus_feilen/` by removing that prefix. Do not copy logs, state files, backups, snapshots, or `.env` files.

- [ ] **Step 3: Verify raw files are byte-identical**

For every copied file:

```bash
cmp -s "$source" "$raw_copy"
```

Expected: all comparisons exit `0`.

- [ ] **Step 4: Scan the raw import for secrets**

Run:

```bash
grep -RInE \
    '(api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key|authorization:[[:space:]]*(bearer|token)|password[[:space:]]*=)' \
    raw-backup . \
    --exclude-dir=.git
```

Expected: no unreviewed finding. Any finding blocks the commit and repository creation.

- [ ] **Step 5: Commit and tag the raw backup**

Run:

```bash
git add .gitignore raw-backup
git commit -m "Preserve current AeroSpace configuration"
git tag -a pre-managed-config-backup \
    -m "Preserve unmanaged AeroSpace configuration before manager setup"
```

- [ ] **Step 6: Create and push the private GitHub repository**

Run only after GitHub approval:

```bash
gh repo create Knapsack44/aerospace-custom-config \
    --private \
    --source=/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config \
    --remote=origin \
    --push
git push origin pre-managed-config-backup
```

Expected:

```bash
gh repo view Knapsack44/aerospace-custom-config --json visibility --jq .visibility
```

prints `PRIVATE`.

---

### Task 3: Define the Managed Host Profile and Byte-Exact Config Sync

**Files:**
- Create: `manifest/markus-macbook.files`
- Create: `hosts/markus-macbook/home/...`
- Create: `lib/common.sh`
- Create: `lib/config-sync.sh`
- Create: `tests/test-helper.sh`
- Create: `tests/config-sync-test.sh`

**Interfaces:**
- Produces:
  - `manager_init`
  - `manifest_each <callback>`
  - `config_import <host>`
  - `config_install <host> <source_root>`
  - `config_diff <host>`
- Manifest format: `mode<TAB>source-path<TAB>repository-relative-path`.

- [ ] **Step 1: Write the config-sync tests**

The tests must prove:

```bash
test_import_copies_exact_bytes
test_install_preserves_executable_mode
test_unknown_files_are_reported_but_not_added
test_runtime_files_are_never_imported
test_missing_managed_file_fails
```

Use an isolated test HOME and a manifest containing:

```text
0644	$HOME/.aerospace.toml	hosts/markus-macbook/home/.aerospace.toml
0755	$HOME/.config/aerospace/example.sh	hosts/markus-macbook/home/.config/aerospace/example.sh
```

Run:

```bash
bash tests/config-sync-test.sh
```

Expected before implementation: FAIL because `config_import` is undefined.

- [ ] **Step 2: Implement shared manager initialization**

`lib/common.sh` must define:

```bash
set -euo pipefail

MANAGER_REPO="${AEROSPACE_CUSTOM_MANAGER_REPO:-/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config}"
SOURCE_REPO="${AEROSPACE_CUSTOM_SOURCE_REPO:-/Users/markus_feilen/Code/github/nikitabobko/AeroSpace}"
MANAGER_STATE="${AEROSPACE_CUSTOM_MANAGER_STATE:-$HOME/Library/Application Support/AeroSpace Custom Manager}"
HOST_PROFILE="${AEROSPACE_CUSTOM_HOST_PROFILE:-markus-macbook}"
LOCK_DIR="$MANAGER_STATE/manager.lock"

die() {
    printf 'aerospace-custom-manager: %s\n' "$*" >&2
    exit 1
}

manager_init() {
    umask 077
    mkdir -p "$MANAGER_STATE"
    mkdir "$LOCK_DIR" 2>/dev/null || die "another manager operation is active"
    trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}
```

- [ ] **Step 3: Implement byte-exact manifest processing**

`lib/config-sync.sh` must:

```bash
manifest_each() {
    callback="$1"
    while IFS="$(printf '\t')" read -r mode source relative; do
        case "$mode" in
            ''|\#*) continue ;;
        esac
        "$callback" "$mode" "$source" "$relative"
    done < "$MANAGER_REPO/manifest/$HOST_PROFILE.files"
}
```

`config_import` copies every source to its repository-relative path with the declared mode. `config_install` installs from repository path to destination using `install -m`. Both functions fail if any listed source is missing.

- [ ] **Step 4: Create the production manifest**

List exactly the raw files from Task 2. Use:

- `0644` for `.aerospace.toml` and the LaunchAgent plist.
- `0755` for every `.sh` file.

No wildcard is allowed. New files therefore remain untracked until explicitly reviewed and added.

- [ ] **Step 5: Import the managed host profile and verify it**

Run:

```bash
bash -c '. lib/common.sh; . lib/config-sync.sh; manager_init; config_import markus-macbook'
bash tests/config-sync-test.sh
git diff --no-index \
    raw-backup/markus-macbook/home/.aerospace.toml \
    hosts/markus-macbook/home/.aerospace.toml
```

Expected: tests pass and the diff is empty.

- [ ] **Step 6: Commit**

```bash
git add manifest hosts lib tests
git commit -m "Manage the markus-macbook AeroSpace profile"
```

---

### Task 4: Add Blocking Secret Scanning and Safe Config Checkpoints

**Files:**
- Create: `lib/secret-scan.sh`
- Create: `tests/secret-scan-test.sh`
- Modify: `lib/config-sync.sh`

**Interfaces:**
- Produces:
  - `secret_scan_paths <path...>`
  - `config_checkpoint <reason>`
- `config_checkpoint` imports managed files, scans them, commits only when changed, and pushes `main`.

- [ ] **Step 1: Write failing secret-scan tests**

Test these cases:

```text
AWS_SECRET_ACCESS_KEY=example-secret -> reject
Authorization: Bearer example-token -> reject
-----BEGIN PRIVATE KEY----- -> reject
normal AeroSpace TOML and shell paths -> accept
unchanged config -> no commit
changed safe config -> one commit and one push
push failure -> abort operation
```

Use a fake `git` executable in the test PATH to record push attempts.

- [ ] **Step 2: Implement the scanner**

`secret_scan_paths` must reject:

```bash
grep -RInE \
    '(-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|AWS_SECRET_ACCESS_KEY|api[_-]?key[[:space:]]*[:=]|access[_-]?token[[:space:]]*[:=]|client[_-]?secret[[:space:]]*[:=]|authorization:[[:space:]]*(bearer|token)|password[[:space:]]*[:=])'
```

It must also reject tracked files ending in:

```text
.p12 .pem .key .mobileprovision
```

Do not print matched secret values. Report only file path and line number.

- [ ] **Step 3: Implement the checkpoint transaction**

`config_checkpoint` must:

```bash
config_import "$HOST_PROFILE"
secret_scan_paths "$MANAGER_REPO/hosts/$HOST_PROFILE" "$MANAGER_REPO/manifest"

if ! git -C "$MANAGER_REPO" diff --quiet -- hosts manifest; then
    git -C "$MANAGER_REPO" add hosts manifest
    git -C "$MANAGER_REPO" commit -m "Preserve AeroSpace config before $reason"
fi

git -C "$MANAGER_REPO" push origin main
```

Any failure aborts update or rollback before active files are changed.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/secret-scan-test.sh
git add lib tests
git commit -m "Secure managed configuration checkpoints"
```

---

### Task 5: Create and Verify the Stable Local Signing Identity

**Files:**
- Create: `scripts/setup-signing-identity.sh`
- Create: `lib/signing.sh`
- Modify: `.gitignore`
- Test: `tests/manager-cli-test.sh`

**Interfaces:**
- Identity common name: `AeroSpace Custom Local Code Signing`
- Keychain password service: `aerospace-custom-codesign-backup`
- Keychain account: current `$USER`
- Backup path: `~/Library/Application Support/AeroSpace Custom/Signing Backup/AeroSpace Custom Local Code Signing.p12`
- Produces:
  - `signing_identity_name`
  - `signing_verify`

- [ ] **Step 1: Implement identity verification**

`lib/signing.sh`:

```bash
SIGNING_IDENTITY="AeroSpace Custom Local Code Signing"
SIGNING_BACKUP_DIR="$HOME/Library/Application Support/AeroSpace Custom/Signing Backup"
SIGNING_BACKUP="$SIGNING_BACKUP_DIR/$SIGNING_IDENTITY.p12"
SIGNING_PASSWORD_SERVICE="aerospace-custom-codesign-backup"

signing_verify() {
    security find-identity -v -p codesigning |
        grep -F "\"$SIGNING_IDENTITY\"" >/dev/null ||
        die "missing valid code-signing identity: $SIGNING_IDENTITY"
    test -f "$SIGNING_BACKUP" ||
        die "missing encrypted signing backup: $SIGNING_BACKUP"
    security find-generic-password \
        -a "$USER" \
        -s "$SIGNING_PASSWORD_SERVICE" >/dev/null ||
        die "missing signing backup password in Keychain"
}
```

- [ ] **Step 2: Implement one-time certificate setup**

`scripts/setup-signing-identity.sh` must:

1. Abort if the identity already exists.
2. Generate a random 32-byte password without printing it.
3. Create a 3072-bit RSA self-signed certificate with:

```text
CN = AeroSpace Custom Local Code Signing
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
validity = 3650 days
```

4. Export the certificate and key directly to the encrypted `.p12` backup.
5. Import the `.p12` into `~/Library/Keychains/login.keychain-db`.
6. Add user-domain code-signing trust with:

```bash
security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" \
    "$certificate_pem"
```

7. Store the password:

```bash
security add-generic-password \
    -U \
    -a "$USER" \
    -s aerospace-custom-codesign-backup \
    -w "$password"
```

8. Remove temporary unencrypted private-key material through an EXIT trap.

This task changes macOS trust settings and requires explicit execution-time approval.

- [ ] **Step 3: Create the identity and verify stable signing**

Run:

```bash
bash scripts/setup-signing-identity.sh
security find-identity -v -p codesigning
codesign --force --sign "AeroSpace Custom Local Code Signing" /tmp/aerospace-signing-test
codesign --verify --strict /tmp/aerospace-signing-test
```

Prepare the test executable explicitly:

```bash
cp /bin/echo /tmp/aerospace-signing-test
chmod u+w /tmp/aerospace-signing-test
codesign --force --sign "AeroSpace Custom Local Code Signing" /tmp/aerospace-signing-test
codesign --verify --strict /tmp/aerospace-signing-test
rm /tmp/aerospace-signing-test
```

Expected: one valid identity and successful verification.

- [ ] **Step 4: Commit scripts only**

Before commit, verify no certificate or key is under the repository:

```bash
find . -type f \( -name '*.p12' -o -name '*.pem' -o -name '*.key' \) -print -quit |
    grep . && exit 1 || true
```

Then:

```bash
git add .gitignore lib/signing.sh scripts/setup-signing-identity.sh tests
git commit -m "Manage stable AeroSpace Custom signing"
```

---

### Task 6: Add Process-State Preservation

**Files:**
- Create: `lib/processes.sh`
- Create: `tests/processes-test.sh`

**Interfaces:**
- Produces:
  - `processes_capture`
  - `processes_stop_managed`
  - `processes_restore`
  - `processes_assert_singletons`
- Managed process identities:
  - `AeroSpace Custom`
  - `com.rtalur.aeromux`
  - AeroBar only when a concrete configured process or LaunchAgent is added to the manifest.

- [ ] **Step 1: Write process-state tests**

Verify:

```text
running Custom + AeroMux are captured
stopped process remains stopped after restore
running process is restarted after install
two Custom instances fail singleton validation
unmanaged processes are never killed
```

Use fake `pgrep`, `ps`, `open`, `osascript`, and `launchctl` commands.

- [ ] **Step 2: Implement capture and stop**

Store JSON at `$MANAGER_STATE/process-state.json`:

```json
{
  "aerospaceCustom": true,
  "aeromux": true,
  "aerobar": false
}
```

Stop AeroSpace Custom with AppleScript first, then wait up to 10 seconds. Escalate to a PID-specific `kill TERM` only if the same executable remains. Never use broad `pkill AeroSpace`.

- [ ] **Step 3: Implement restore and duplicate checks**

Restore only entries that were previously true. Validate:

```bash
test "$(pgrep -x 'AeroSpace Custom' | wc -l | tr -d ' ')" -le 1
```

Apply equivalent checks to configured AeroMux and AeroBar process names.

- [ ] **Step 4: Verify and commit**

```bash
bash tests/processes-test.sh
git add lib/processes.sh tests/processes-test.sh
git commit -m "Preserve AeroSpace companion process state"
```

---

### Task 7: Define the Durable Custom Patch Stack

**Files:**
- Create: `custom/patches.toml`
- Create: `custom/README.md`
- Create: `script/verify-custom-patch-stack.sh`
- Test: shell execution of `script/verify-custom-patch-stack.sh`

**Interfaces:**
- Upstream base: `v0.21.2-Beta`
- Required ordered patch IDs:
  1. `container-local-focus`
  2. `custom-app-bundle`
  3. `custom-cli-routing`
  4. `ax-registration-backoff`
  5. `delayed-focus-follows-mouse`
  6. `monitor-layout-memory`

- [ ] **Step 1: Create the patch manifest**

`custom/patches.toml` starts with:

```toml
schema-version = 1
upstream-base = 'v0.21.2-Beta'

[[patch]]
id = 'container-local-focus'
commit-subject = 'Add container-local focus cycling'
status = 'submitted'
upstream-reference = 'https://github.com/nikitabobko/AeroSpace/pull/2048'
tests = ['FocusCommandTest', 'FocusCmdArgsTest']
retire-when = 'Upstream provides equivalent container-next/container-prev cycling with ancestor fallback and all retained tests pass.'

[[patch]]
id = 'custom-app-bundle'
commit-subject = 'Add side-by-side AeroSpace Custom build'
status = 'custom-only'
upstream-reference = ''
tests = ['AppMetadataTest']
retire-when = 'Never retire automatically; this defines the Custom product identity.'

[[patch]]
id = 'custom-cli-routing'
commit-subject = 'Route CLI to running AeroSpace Custom'
status = 'custom-only'
upstream-reference = ''
tests = ['AppMetadataTest']
retire-when = 'Retire only if upstream supports equivalent runtime target selection without changing vanilla defaults.'

[[patch]]
id = 'ax-registration-backoff'
commit-subject = 'Throttle failed app registration retries'
status = 'submitted'
upstream-reference = 'https://github.com/nikitabobko/AeroSpace/discussions/2084'
tests = ['FailedRegistrationBackoffTest']
retire-when = 'Upstream prevents tight failed AX registration retries and the CPU regression test passes.'

[[patch]]
id = 'delayed-focus-follows-mouse'
commit-subject = 'Stabilize delayed focus follows mouse'
status = 'custom-only'
upstream-reference = ''
tests = ['ConfigTest focus-follows-mouse delay cases']
retire-when = 'Upstream provides the same delayed overlapping-window behavior and retained tests pass.'

[[patch]]
id = 'monitor-layout-memory'
commit-subject = 'Add native monitor-aware layout memory'
status = 'custom-only'
upstream-reference = ''
tests = ['LayoutMemory']
retire-when = 'Retire only if upstream supplies equivalent versioned monitor-profile snapshots, conservative matching, transactional restore, and manual controls.'
```

- [ ] **Step 2: Implement stack verification**

The verifier must:

1. Read `upstream-base`.
2. Confirm the base tag resolves.
3. Confirm each `commit-subject` appears exactly once in `upstream-base..HEAD`.
4. Confirm subjects occur in manifest order.
5. Reject commits in the range with subjects beginning `WIP`, `fixup!`, or `squash!`.
6. Run the listed focused tests.

- [ ] **Step 3: Document branch policy**

`custom/README.md` must state:

```text
custom/main is the full integration branch and may contain experiments.
Successful installation plus smoke tests make a revision stable by default.
Stable release tags use custom-v<upstream-version>.<revision>.
Contribution branches contain one upstream contribution and never include personal Custom-only patches.
```

- [ ] **Step 4: Commit**

```bash
git add custom script/verify-custom-patch-stack.sh
git commit -m "Document the AeroSpace Custom patch stack"
```

---

### Task 8: Rebuild `custom/main` as an Atomic Patch Series

**Files:**
- Rewrite Git branch history only.
- Preserve source tree behavior and all tests.

**Interfaces:**
- Consumes: immutable backup tag from Task 1 and dedicated CPU branch `codex/ax-registration-retry-backoff`.
- Produces: `custom/main` based on `v0.21.2-Beta` with the exact ordered subjects from Task 7.

- [ ] **Step 1: Create an isolated reconstruction worktree**

Run:

```bash
git worktree add \
    /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-stack-rebuild \
    -b custom/rebuild-v0.21.2-beta.1 \
    v0.21.2-Beta
```

Do not rewrite the existing tested worktree in place.

- [ ] **Step 2: Reconstruct container-local focus as one commit**

Start with the original atomic focus commit:

```bash
git cherry-pick c322a4bd
```

Apply only the later ancestor-fallback and lint corrections:

```bash
git show b7730c6d -- \
    Sources/AppBundle/command/impl/FocusCommand.swift \
    Sources/AppBundleTests/command/FocusCommandTest.swift \
    docs/aerospace-focus.adoc |
    git apply --3way
git show fdd463fa -- Sources/Common/cmdArgs/impl/FocusCmdArgs.swift |
    git apply --3way
./generate.sh
git add \
    Sources/AppBundle/command/impl/FocusCommand.swift \
    Sources/AppBundleTests/command/FocusCommandTest.swift \
    Sources/Common/cmdArgs/impl/FocusCmdArgs.swift \
    Sources/Common/cmdHelpGenerated.swift \
    Sources/Cli/subcommandDescriptionsGenerated.swift \
    docs/aerospace-focus.adoc \
    docs/config-examples/i3-like-config-example.toml \
    grammar/commands-bnf-grammar.txt
git commit --amend --no-edit
```

The resulting commit includes ancestor fallback, parser validation, docs, grammar, generated help, and tests. Its subject remains:

```text
Add container-local focus cycling
```

Required tests:

```bash
swift test --filter FocusCommandTest
```

- [ ] **Step 3: Reconstruct side-by-side Custom app identity and packaging**

Use `b7730c6d` as the reference, but reconstruct this commit with `apply_patch` rather than cherry-picking the mixed WIP commit. The commit may modify only:

```text
Sources/AppBundle/config/startAtLogin.swift
Sources/AppBundle/initAppBundle.swift
Sources/AppBundle/server.swift
Sources/AppBundleTests/config/AppMetadataTest.swift
Sources/Common/appMetadata.swift
Sources/Common/model/AeroSpaceEnvVars.swift
Sources/Common/util/commonUtil.swift
build-release.sh
build-shell-completion.sh
script/setup.sh
dev-docs/development.md
docs/guide.adoc
install-custom-from-sources.sh
xcode/AeroSpace.xcodeproj/project.pbxproj
xcode/project.yml
Sources/AppBundle/util/AxUiElementMock.swift
```

Implement only:

- App name, bundle ID, socket identity, login-item identity.
- `AeroSpaceCustom` Xcode scheme and generated project.
- Custom release artifact production.
- Homebrew/Ruby and fish-availability build portability required by the release path.
- Stable named signing identity support.

At the end of this commit, `Sources/Common/appMetadata.swift` may define the stable, Custom, and debug app IDs/names plus app-process resolution, but it must not inspect `NSWorkspace.shared.runningApplications`. `Sources/Cli/_main.swift` must remain unchanged. Do not include CLI auto-routing, CPU backoff, focus behavior, or layout-memory.

Generate the Xcode project non-interactively:

```bash
./generate.sh
git add \
    Sources/AppBundle/config/startAtLogin.swift \
    Sources/AppBundle/initAppBundle.swift \
    Sources/AppBundle/server.swift \
    Sources/AppBundleTests/config/AppMetadataTest.swift \
    Sources/Common/appMetadata.swift \
    Sources/Common/model/AeroSpaceEnvVars.swift \
    Sources/Common/util/commonUtil.swift \
    build-release.sh \
    build-shell-completion.sh \
    script/setup.sh \
    dev-docs/development.md \
    docs/guide.adoc \
    install-custom-from-sources.sh \
    Sources/AppBundle/util/AxUiElementMock.swift \
    xcode/AeroSpace.xcodeproj/project.pbxproj \
    xcode/project.yml
git commit -m "Add side-by-side AeroSpace Custom build"
```

Commit:

```text
Add side-by-side AeroSpace Custom build
```

Required tests:

```bash
swift test --filter AppMetadataTest
./build-release.sh \
    --build-version 0.21.2-Beta \
    --custom-app \
    --codesign-identity "AeroSpace Custom Local Code Signing"
```

- [ ] **Step 4: Reconstruct CLI auto-routing as one commit**

Add the final runtime resolver from the backup branch to:

```text
Sources/Common/appMetadata.swift
Sources/Cli/_main.swift
Sources/AppBundleTests/config/AppMetadataTest.swift
```

The resolver must expose:

```swift
public func currentAeroSpaceRunningBundleIds() -> Set<String>

public func resolveAeroSpaceCliTarget(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executableName: String = cliExecutableName(),
    runningBundleIds: Set<String> = currentAeroSpaceRunningBundleIds(),
) -> AeroSpaceCliTarget
```

Selection order:

```text
explicit environment overrides
aerospace-custom executable name
running AeroSpace Custom bundle
stable AeroSpace fallback
```

Apply runtime detection and environment override behavior only. Preserve:

```text
AEROSPACE_APP_ID
AEROSPACE_APP_NAME
AEROSPACE_SOCKET_PATH
```

Then:

```bash
git add \
    Sources/Common/appMetadata.swift \
    Sources/Cli/_main.swift \
    Sources/AppBundleTests/config/AppMetadataTest.swift
git commit -m "Route CLI to running AeroSpace Custom"
swift test --filter AppMetadataTest
```

Commit:

```text
Route CLI to running AeroSpace Custom
```

- [ ] **Step 5: Apply the dedicated AX registration backoff**

Cherry-pick the dedicated commit:

```bash
git cherry-pick cf2a730d
```

Resolve only API drift from the reconstruction branch. The final change in `Sources/AppBundle/tree/MacApp.swift` must contain a five-second negative retry cache keyed by PID, clear it after successful registration, and clear it when the app is destroyed. Commit subject must remain:

```text
Throttle failed app registration retries
```

Extract the time-based state into:

```swift
struct FailedRegistrationBackoff {
    let delay: TimeInterval
    private(set) var retryAfterByPid: [pid_t: Date] = [:]

    mutating func shouldAttempt(pid: pid_t, now: Date) -> Bool {
        guard let retryAfter = retryAfterByPid[pid] else { return true }
        if retryAfter > now { return false }
        retryAfterByPid[pid] = nil
        return true
    }

    mutating func recordFailure(pid: pid_t, now: Date) {
        retryAfterByPid[pid] = now.addingTimeInterval(delay)
    }

    mutating func clear(pid: pid_t) {
        retryAfterByPid[pid] = nil
    }
}
```

Add deterministic tests for initial attempt, suppression before five seconds, retry after five seconds, and clearing after success/destruction:

```bash
swift test --filter FailedRegistrationBackoffTest
```

- [ ] **Step 6: Reconstruct delayed focus-follows-mouse**

Apply the focused commit without its unrelated installer hunk:

```bash
git show bb96e622 -- \
    Sources/AppBundle/config/Config.swift \
    Sources/AppBundle/config/parseFocusFollowsMouse.swift \
    Sources/AppBundle/mouse/focusFollowsMouse.swift \
    Sources/AppBundleTests/config/ConfigTest.swift \
    docs/config-examples/default-config.toml |
    git apply --3way
git show fdd463fa -- Sources/AppBundle/mouse/focusFollowsMouse.swift |
    git apply --3way
git add \
    Sources/AppBundle/config/Config.swift \
    Sources/AppBundle/config/parseFocusFollowsMouse.swift \
    Sources/AppBundle/mouse/focusFollowsMouse.swift \
    Sources/AppBundleTests/config/ConfigTest.swift \
    docs/config-examples/default-config.toml
git commit -m "Stabilize delayed focus follows mouse"
```

This applies delay parsing, overlap behavior, tests, and documentation while excluding installer-version edits. Commit:

```text
Stabilize delayed focus follows mouse
```

- [ ] **Step 7: Squash native layout-memory into one functional commit**

Apply the layout-memory series without committing each source commit:

```bash
for commit in \
    34be0be0 \
    96008f6c \
    3a9dd733 \
    5bf234bd \
    2169bdcf \
    a0b7f01e \
    35ec4874 \
    ccd89ee5 \
    302a05c7 \
    e0db8c0b \
    ee6413d0
do
    git cherry-pick --no-commit "$commit"
done
```

If generated-file context conflicts because earlier commits have already regenerated help, keep the semantic source files and rerun:

```bash
./generate.sh
```

Then:

```bash
git add \
    Sources/AppBundle \
    Sources/AppBundleTests \
    Sources/Common \
    Sources/Cli \
    docs/aerospace-layout-memory.adoc \
    docs/commands.adoc \
    docs/config-examples/default-config.toml \
    docs/custom-layout-memory-rollout.adoc \
    grammar/commands-bnf-grammar.txt
git commit -m "Add native monitor-aware layout memory"
```

This includes later static-analysis fixes, generated help, tests, docs, and manual-change integration hooks. Commit:

```text
Add native monitor-aware layout memory
```

- [ ] **Step 8: Add the patch manifest commit**

Cherry-pick the Task 7 manifest commit after all functional commits.

- [ ] **Step 9: Verify tree equivalence**

Compare the reconstructed source tree to the backup tag while excluding:

```text
custom/
docs/superpowers/plans/
.gitignore worktree-only entry
```

Expected differences must be limited to intentional commit cleanup, signing identity integration, and removal of obsolete WIP artifacts. Functional Swift, docs, grammar, and tests must otherwise match.

- [ ] **Step 10: Run full validation**

```bash
./generate.sh
git diff --check
swift test --filter LayoutMemory
swift test --filter FocusCommandTest
./lint.sh
./test.sh
./script/verify-custom-patch-stack.sh
```

Expected: all pass.

- [ ] **Step 11: Publish `custom/main` safely**

Create another local tag before moving any existing remote branch:

```bash
git tag -a backup/pre-custom-main-publish-20260716 \
    -m "Preserve source before publishing clean custom/main"
```

After secret scan and push approval:

```bash
git push codex-fork backup/pre-custom-main-publish-20260716
git branch -f custom/main custom/rebuild-v0.21.2-beta.1
git push --force-with-lease codex-fork custom/main
```

Never modify the existing contribution branches.

---

### Task 9: Build Transactional Release and Rollback Packages

**Files:**
- Create: `lib/release-package.sh`
- Create: `tests/release-package-test.sh`

**Interfaces:**
- Produces:
  - `release_build <upstream-version> <source-commit> <config-commit>`
  - `release_capture_rollback`
  - `release_install_candidate`
  - `release_rollback [restore-layout]`
- Runtime package metadata file: `release.json`.

- [ ] **Step 1: Write release-package tests**

Verify:

```text
build failure leaves active installation unchanged
rollback package contains app, CLI, config, scripts, checksums, and metadata
only one rollback directory remains
install verifies checksums before copying
normal rollback does not call layout restore
rollback --restore-layout calls the recorded snapshot version
```

- [ ] **Step 2: Define release metadata**

`release.json` must contain:

```json
{
  "releaseTag": "custom-v0.21.2-beta.1",
  "upstreamTag": "v0.21.2-Beta",
  "customCommit": "full-40-character-sha",
  "configCommit": "full-40-character-sha",
  "buildTimeUtc": "ISO-8601",
  "bundleVersion": "0.21.2-Beta",
  "snapshotSchemaVersion": 1,
  "layoutSnapshotId": "UUID",
  "files": {
    "AeroSpace Custom.app": "sha256",
    "aerospace-custom": "sha256",
    "managed-config.tar": "sha256"
  }
}
```

- [ ] **Step 3: Implement build**

Build from a clean candidate worktree:

```bash
./build-release.sh \
    --build-version "$upstream_version" \
    --custom-app \
    --codesign-identity "AeroSpace Custom Local Code Signing"
```

Validate:

```bash
codesign --verify --deep --strict ".release/AeroSpace Custom.app"
codesign -dvvv ".release/AeroSpace Custom.app"
file ".release/AeroSpace Custom.app/Contents/MacOS/AeroSpace Custom"
file ".release/aerospace"
```

- [ ] **Step 4: Capture the pinned pre-install layout snapshot**

Run:

```bash
snapshot_id="$(
    aerospace-custom layout-memory snapshot \
        --label "pre-install-$release_tag"
)"
```

Store the ID in `release.json`. Do not call restore.

- [ ] **Step 5: Capture exactly one rollback package**

Before installation:

1. Remove the previous `$MANAGER_STATE/rollback.next`.
2. Copy the current app, CLI, managed configuration repository commit, and active files to `rollback.next`.
3. Write and verify checksums.
4. Atomically replace `$MANAGER_STATE/rollback` with `rollback.next`.

Do not remove the previous rollback until the new rollback package is complete and verified.

- [ ] **Step 6: Install the candidate**

After process capture and stop:

```bash
ditto "$candidate/AeroSpace Custom.app" "/Applications/AeroSpace Custom.app"
install -m 0755 "$candidate/aerospace" /opt/homebrew/bin/aerospace-custom
config_install "$HOST_PROFILE" "$candidate/config"
```

Preserve `/opt/homebrew/bin/aerospace -> /opt/homebrew/bin/aerospace-custom`.

- [ ] **Step 7: Implement rollback**

Normal rollback restores:

```text
/Applications/AeroSpace Custom.app
/opt/homebrew/bin/aerospace-custom
all manifest-managed active config files
previous process state
```

Only when `restore-layout` is true:

```bash
aerospace-custom layout-memory restore --version "$layout_snapshot_id"
```

- [ ] **Step 8: Verify and commit**

```bash
bash tests/release-package-test.sh
git add lib/release-package.sh tests/release-package-test.sh
git commit -m "Install and roll back complete Custom releases"
```

---

### Task 10: Implement Smoke Tests and Automatic Immediate Rollback

**Files:**
- Create: `lib/smoke-test.sh`
- Create or modify: `tests/release-package-test.sh`

**Interfaces:**
- Produces: `smoke_test_installed_release`
- Failure triggers `release_rollback false`.

- [ ] **Step 1: Write failing smoke-test cases**

Verify failures for:

```text
missing app
invalid signature
client/server version mismatch
invalid config
layout-memory unavailable
more than one Custom process
old layout-memory tick process running
```

- [ ] **Step 2: Implement the smoke test**

Run these checks in order:

```bash
codesign --verify --deep --strict "/Applications/AeroSpace Custom.app"
aerospace-custom --version
aerospace-custom reload-config --dry-run
aerospace-custom layout-memory status --json |
    jq -e '.available == true and .enabled == true'
aerospace-custom layout-memory restore --dry-run --json |
    jq -e '.mutated == false and .result == "full"'
test "$(pgrep -x 'AeroSpace Custom' | wc -l | tr -d ' ')" = 1
! pgrep -af 'workspace-layout-memory.sh --tick' >/dev/null
```

Also verify CLI and server versions are identical.

- [ ] **Step 3: Wire automatic immediate rollback**

Installation flow:

```bash
if ! smoke_test_installed_release; then
    release_rollback false
    processes_restore
    die "smoke test failed; previous release restored"
fi
```

- [ ] **Step 4: Verify and commit**

```bash
bash tests/release-package-test.sh
git add lib/smoke-test.sh tests
git commit -m "Verify Custom releases after installation"
```

---

### Task 11: Implement Manual Upstream Update Integration

**Files:**
- Create: `lib/source-update.sh`
- Create: `tests/source-update-test.sh`

**Interfaces:**
- Produces:
  - `latest_beta_tag`
  - `source_prepare_candidate <tag>`
  - `source_verify_candidate`
  - `source_publish_candidate <release-tag>`

- [ ] **Step 1: Write update tests**

Use local bare Git fixtures and fake `gh` output to prove:

```text
latest published Beta is selected
draft releases are ignored
upstream main is not selected by default
backup tag is created before rebase
conflict leaves custom/main and installed app unchanged
successful candidate does not move custom/main before smoke success
publish uses force-with-lease
```

- [ ] **Step 2: Implement newest Beta lookup**

```bash
latest_beta_tag() {
    gh api repos/nikitabobko/AeroSpace/releases --paginate |
        jq -rs '
            add
            | map(select(.draft == false))
            | map(select(.tag_name | test("-Beta$"; "i")))
            | sort_by(.published_at)
            | last
            | .tag_name
        '
}
```

An explicitly passed `--upstream-main` bypasses this function.

- [ ] **Step 3: Prepare a candidate branch**

Flow:

```text
fetch origin tags
fetch codex-fork custom/main
create and push backup/pre-update-<UTC timestamp>
create custom/update-<normalized tag>-<UTC timestamp> from custom/main
rebase --onto <new tag> <manifest upstream-base> <candidate branch>
```

If rebase conflicts:

- Leave the candidate branch and worktree intact.
- Do not build, install, tag, or move `custom/main`.
- Print the exact worktree and branch for Codex continuation.

- [ ] **Step 4: Verify upstream-equivalent patch retirement**

For each manifest patch:

1. Search the new upstream range and implementation.
2. Run the retained tests against upstream without the patch.
3. Retire only when behavior is equivalent.
4. Change status to `upstreamed` and record the upstream commit or release.

This semantic step is Codex-guided. The standalone manager may detect likely duplicates but must not retire them automatically.

- [ ] **Step 5: Publish only after installation succeeds**

After smoke success:

```bash
git branch -f custom/main "$candidate_branch"
git push --force-with-lease codex-fork custom/main
git tag -a "$release_tag" -m "Install $release_tag"
git push codex-fork "$release_tag"
```

- [ ] **Step 6: Verify and commit**

```bash
bash tests/source-update-test.sh
git add lib/source-update.sh tests/source-update-test.sh
git commit -m "Prepare Custom updates from upstream Beta releases"
```

---

### Task 12: Expose `aerospace-custom-manager`

**Files:**
- Create: `bin/aerospace-custom-manager`
- Create: `tests/manager-cli-test.sh`
- Create symlink: `/usr/local/bin/aerospace-custom-manager`

**Interfaces:**
- Commands:
  - `status`
  - `verify`
  - `update [--tag TAG | --upstream-main] [--bootstrap-accessibility]`
  - `rollback [--restore-layout]`

- [ ] **Step 1: Write CLI tests**

Verify:

```text
unknown command exits 2
update without flags selects latest Beta
update is never triggered by status
bootstrap-accessibility waits for the first stable-signed app authorization
rollback rejects unknown options
status performs no mutation
```

- [ ] **Step 2: Implement dispatcher**

`bin/aerospace-custom-manager`:

```bash
#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$repo/lib/common.sh"
. "$repo/lib/config-sync.sh"
. "$repo/lib/secret-scan.sh"
. "$repo/lib/signing.sh"
. "$repo/lib/processes.sh"
. "$repo/lib/source-update.sh"
. "$repo/lib/release-package.sh"
. "$repo/lib/smoke-test.sh"

command="${1:-status}"
test $# -eq 0 || shift

case "$command" in
    status) manager_status "$@" ;;
    verify) manager_verify "$@" ;;
    update) manager_update "$@" ;;
    rollback) manager_rollback "$@" ;;
    *) printf 'Unknown command: %s\n' "$command" >&2; exit 2 ;;
esac
```

- [ ] **Step 3: Implement update orchestration**

`manager_update` order is fixed:

```text
manager_init
prerequisite checks
config_checkpoint "update"
signing_verify
source_prepare_candidate
source_verify_candidate
release_build
create pinned layout snapshot
processes_capture
release_capture_rollback
processes_stop_managed
release_install_candidate
processes_restore
smoke_test_installed_release
publish custom/main
tag source repo
tag config repo
write current.json
```

No step before `release_install_candidate` may modify the active app, CLI, or config.

`--bootstrap-accessibility` is permitted only when no prior `current.json` exists for the stable signing identity. After installation it opens the Accessibility settings pane, waits up to five minutes for the Custom server to become reachable, and then continues with the normal smoke test. Timeout or explicit failure restores the rollback package. Later updates reject this flag because the stable identity should retain permission.

- [ ] **Step 4: Implement rollback orchestration**

`manager_rollback` order:

```text
manager_init
config_checkpoint "rollback"
processes_capture
processes_stop_managed
release_rollback false-or-restore-layout
processes_restore
smoke_test_installed_release
```

- [ ] **Step 5: Install the system-wide symlink**

Run with filesystem approval:

```bash
ln -sfn \
    /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/bin/aerospace-custom-manager \
    /usr/local/bin/aerospace-custom-manager
```

- [ ] **Step 6: Verify and commit**

```bash
bash tests/manager-cli-test.sh
/usr/local/bin/aerospace-custom-manager status
git add bin tests
git commit -m "Expose the AeroSpace Custom manager"
```

---

### Task 13: Build and Install the Initial Common Release

**Files:**
- Update source metadata: `custom/patches.toml`
- Create manager metadata: `$MANAGER_STATE/current.json`
- Create tags in both repositories: `custom-v0.21.2-beta.1`

**Interfaces:**
- Consumes: clean `custom/main`, pushed private config `main`, stable signing identity, manager.
- Produces: first fully reproducible installed baseline and one rollback package.

- [ ] **Step 1: Verify both repositories are clean and pushed**

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace status --short
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config status --short
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config push origin main
```

Expected: both status outputs are empty.

- [ ] **Step 2: Run the manager verification**

```bash
aerospace-custom-manager verify
```

Expected checks:

```text
private config remote is reachable
source fork remote is reachable
stable signing identity is valid
encrypted signing backup exists
manifest files exist
no suspected secrets
custom patch stack verifies
old polling LaunchAgent is disabled
```

- [ ] **Step 3: Run the initial managed installation**

Invoke a fixed-tag update with the one-time Accessibility bootstrap:

```bash
aerospace-custom-manager update \
    --tag v0.21.2-Beta \
    --bootstrap-accessibility
```

Expected:

- Stable-signature Custom app installed.
- CLI installed.
- Managed config installed.
- Exactly one AeroSpace Custom process running.
- AeroMux restored only if it was running before.
- Pinned pre-install layout snapshot exists.
- One complete rollback package exists.
- No automatic layout restore occurred.

- [ ] **Step 4: Verify Accessibility trust survives one same-identity rebuild**

Build and sign the same source again without installing it. Compare signing authority and designated requirement. Then install that same-identity build through the manager and verify AeroSpace starts without requiring a new Accessibility grant.

- [ ] **Step 5: Tag both repositories**

Only after smoke success:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace \
    tag -a custom-v0.21.2-beta.1 \
    -m "AeroSpace Custom v0.21.2 Beta revision 1"
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config \
    tag -a custom-v0.21.2-beta.1 \
    -m "AeroSpace Custom config v0.21.2 Beta revision 1"
```

Scan before push, then:

```bash
git -C /Users/markus_feilen/Code/github/nikitabobko/AeroSpace \
    push codex-fork custom-v0.21.2-beta.1
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config \
    push origin custom-v0.21.2-beta.1
```

- [ ] **Step 6: Exercise rollback without layout mutation**

```bash
aerospace-custom-manager rollback
```

Verify:

- App, CLI, and config return to the previous package.
- No layout-memory restore command was issued.
- Processes return to their previous state.

Then reinstall `custom-v0.21.2-beta.1` and rerun smoke tests.

- [ ] **Step 7: Exercise layout-aware rollback in a controlled test**

Create a fresh test snapshot, make a reversible layout change, then:

```bash
aerospace-custom-manager rollback --restore-layout
```

Verify the recorded snapshot is selected explicitly and the restore reports no ambiguous windows.

---

### Task 14: Document Operation and Recovery

**Files:**
- Create or modify: `README.md` in the private config repository.
- Modify: `custom/README.md` in the AeroSpace fork.

**Interfaces:**
- Produces a non-code operator guide for routine updates and disaster recovery.

- [ ] **Step 1: Document normal commands**

Include:

```bash
aerospace-custom-manager status
aerospace-custom-manager verify
aerospace-custom-manager update
aerospace-custom-manager update --tag v0.22.0-Beta
aerospace-custom-manager rollback
aerospace-custom-manager rollback --restore-layout
```

- [ ] **Step 2: Document Codex workflow**

State that “Bring AeroSpace Custom auf den neuesten Stand” means:

1. Inspect newest published Beta.
2. Secure and push direct config edits.
3. Rebase the complete manifest patch stack.
4. Resolve technical conflicts autonomously.
5. Ask Markus only for unavoidable behavioral decisions.
6. Test, build, sign, snapshot, install, smoke-test, and publish.

- [ ] **Step 3: Document failure behavior**

Explicitly state:

```text
Rebase conflict: active installation unchanged.
Build/test failure: active installation unchanged.
Smoke failure: automatic software/config rollback.
Problem reported later: explicit rollback required.
Normal rollback: no layout restore.
Signing identity missing: update aborts before installation.
Secret suspicion: update and rollback abort before commit or push.
```

- [ ] **Step 4: Document disaster recovery**

Recovery inputs:

```text
Knapsack44/AeroSpace custom release tag
Knapsack44/aerospace-custom-config matching private release tag
encrypted local .p12 backup
Keychain-stored .p12 password
```

Recovery must rebuild locally; no binaries are downloaded from GitHub.

- [ ] **Step 5: Commit and push**

```bash
git add README.md
git commit -m "Document AeroSpace Custom lifecycle management"
git push origin main
```

In the source fork:

```bash
git add custom/README.md
git commit -m "Document Custom branch lifecycle"
git push --force-with-lease codex-fork custom/main
```

Run the required secret scan before both pushes.

---

## Final Acceptance Checklist

- [ ] `custom/main` exists in `Knapsack44/AeroSpace` and contains the ordered atomic patch stack.
- [ ] Existing upstream PR branches remain unchanged and isolated.
- [ ] `backup/pre-custom-main-rewrite-20260716` remains available in the fork.
- [ ] `Knapsack44/aerospace-custom-config` exists and is private.
- [ ] `pre-managed-config-backup` preserves the original selected config files.
- [ ] Direct changes to active managed files are imported, committed, scanned, and pushed before update and rollback.
- [ ] New unknown config files are reported and never silently added.
- [ ] Stable signing identity is valid and its encrypted backup remains outside Git.
- [ ] Reinstalling a same-identity build does not require a fresh Accessibility grant.
- [ ] `aerospace-custom-manager` is available at `/usr/local/bin/aerospace-custom-manager`.
- [ ] `status` and `verify` never install or update anything.
- [ ] `update` selects the newest published Beta by default and is never automatic.
- [ ] A rebase, test, build, signing, or config-push failure leaves the active installation unchanged.
- [ ] A smoke-test failure automatically restores the previous app, CLI, and config.
- [ ] Exactly one complete local rollback version is retained.
- [ ] Normal rollback does not alter the window layout.
- [ ] `rollback --restore-layout` restores only the explicitly recorded pinned snapshot.
- [ ] Managed AeroSpace, AeroMux, and available AeroBar process state is preserved without duplicates.
- [ ] Source and config repositories share the release tag `custom-v0.21.2-beta.1`.
- [ ] Each installed release records upstream tag, Custom commit, config commit, version, snapshot schema, snapshot ID, and checksums.
- [ ] No app binaries, CLI binaries, certificates, keys, `.p12`, snapshots, logs, locks, or rollback packages are tracked in Git.
