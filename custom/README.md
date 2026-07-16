# AeroSpace Custom

`custom/main` is the complete integration branch for Markus' AeroSpace
Custom build. It may contain experiments in addition to established
features.

A revision is treated as stable by default after it builds, installs, and
passes the post-install smoke test. Stable release tags use:

```text
custom-v<upstream-version>.<revision>
```

The matching source and private configuration repositories receive the same
release tag.

`custom/patches.toml` is the authoritative patch inventory. Each durable
Custom function has one atomic commit, retained regression tests, an
upstream status, and explicit retirement criteria.

Upstream contribution branches stay separate from `custom/main`. They
contain one contribution only and never include Custom-only product,
configuration, or layout-memory changes.

Before rewriting `custom/main`, create and push an immutable backup tag.
Publish rewritten history only with `git push --force-with-lease`.

The matching private repository
`Knapsack44/aerospace-custom-config` stores the exact personal configuration
and provides `/usr/local/bin/aerospace-custom-manager`. Updates are manual:

```bash
aerospace-custom-manager status
aerospace-custom-manager verify
aerospace-custom-manager update
aerospace-custom-manager rollback
```

The manager checkpoints direct config edits, rebuilds the full patch stack,
uses the stable local signing identity, retains one complete rollback release,
and publishes `custom/main` only after the installed release passes smoke tests.
