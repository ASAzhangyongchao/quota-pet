# Errors

Command failures and integration errors.

---

## [ERR-20260719-004] visual_companion_local_port_sandbox

**Logged**: 2026-07-19T20:30:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The visual companion preview server could not bind a localhost port inside the workspace sandbox.

### Error

```text
Error: listen EPERM: operation not permitted 127.0.0.1:<port>
```

### Context
- The server was used only for a temporary local QuotaPet visual-design comparison.
- Starting the same localhost-only script with approved local-network permission succeeded.

### Suggested Fix
Request the narrow localhost-server approval before starting the visual companion in restricted Codex desktop sessions.

### Metadata
- Reproducible: yes
- Related Files: docs/superpowers/specs

---

## [ERR-20260719-003] gh_api_unavailable_in_workspace_sandbox

**Logged**: 2026-07-19T20:00:00+08:00
**Priority**: low
**Status**: resolved
**Area**: infra

### Summary
The local `gh` CLI could not reach `api.github.com` while gathering read-only repository metadata inside the workspace sandbox.

### Error

```text
error connecting to api.github.com
check your internet connection or https://githubstatus.com
```

### Context
- The command was a read-only `gh repo view` during a public-release legal and provenance audit.
- The connected GitHub app and web sources remain available as non-shell fallbacks.

### Suggested Fix
Use the connected GitHub app for repository metadata in restricted sessions; reserve the local `gh` CLI for approved network-enabled operations.

### Metadata
- Reproducible: unknown
- Related Files: AGENTS.md

---

## [ERR-20260719-002] swift_release_build_in_workspace_sandbox

**Logged**: 2026-07-19T17:26:00+08:00
**Priority**: medium
**Status**: resolved
**Area**: infra

### Summary
The release build could not write Swift's user-level module cache while running inside the workspace filesystem sandbox.

### Error

```text
error opening the user module cache for output: Operation not permitted
```

### Context
- The package sources and destination directory were writable.
- Swift still selected a cache under the user's home directory.

### Suggested Fix
Set `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` to a writable temporary directory before invoking the release packaging script. Escalate to normal local permissions only if a later signing or installation step genuinely requires it.

### Resolution
The same failure recurred during the 0.1.3 package build. Redirecting both Swift/Clang module caches to `/private/tmp` allowed the build to proceed without changing application code or weakening its runtime security model.

### Metadata
- Reproducible: yes
- Related Files: scripts/build-app.sh
- Recurrence-Count: 2

---

## [ERR-20260719-001] codex_rate_limits_integration

**Logged**: 2026-07-19T17:10:26+08:00
**Priority**: high
**Status**: resolved
**Area**: tests

### Summary
The explicitly confirmed local Codex app-server did not produce a ready rate-limit snapshot within 30 seconds.

### Error

```text
Timed out waiting for a rate-limit snapshot
```

### Context
- The read-only integration test used the same resolver confirmation and revalidation path as the app.
- The candidate passed path, ownership, permissions, identity, hash, confirmation, and pre-launch revalidation checks.
- The test currently hides intermediate unavailable failures, so the underlying protocol error still needs to be surfaced.

### Suggested Fix
Run the authenticated integration test outside the workspace filesystem sandbox. Keep provider stderr in memory after an unexpected child exit so local diagnostics remain available without printing or persisting it.

### Resolution
The app-server exited because the workspace sandbox denied access to its SQLite state under the user's Codex home. This was an integration-test environment restriction, not a protocol incompatibility. The production app is installed and launched outside that sandbox.

### Metadata
- Reproducible: yes
- Related Files: Tests/QuotaPetTests/CodexIntegrationTests.swift, Sources/QuotaPet/Usage/CodexAppServerStdioProvider.swift

---
