# Errors

Command failures and integration errors.

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
Run the release packaging script with normal local permissions after source tests pass; do not weaken the application sandbox or redirect release artifacts outside the repository.

### Metadata
- Reproducible: yes
- Related Files: scripts/build-app.sh

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
