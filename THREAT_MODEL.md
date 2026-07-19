# QuotaPet Threat Model

## Scope and trust boundaries

QuotaPet consists of a Swift/AppKit main process, local preferences, and an explicitly approved official Codex App Server child process connected over JSONL/RPC standard I/O. The child crosses a trust boundary: it runs as the current user, performs normal Codex authentication, and may connect to OpenAI. QuotaPet has no developer backend.

Protected assets are the user's Codex credentials, local files, approved executable identity, quota snapshot integrity, preference integrity, and the ability to terminate the child process reliably.

## Threats and gates

| Threat | Impact | Gate |
| --- | --- | --- |
| Codex path hijacking or symlink replacement | Execute attacker-controlled code as the user | Resolve to a canonical regular file; reject unsafe owners and group/world-writable files; bound file/path size; hash through an open descriptor; compare device/inode/size/mode/owner before and after inspection; validate known bundle signing identity; require explicit confirmation for other sources; revalidate before launch. |
| Forged JSONL response | Display false quota data or confuse RPC state | Accept only correlated RPC responses; parse typed quota fields; ignore unknown/invalid data; bound pending requests and timeouts; treat malformed input as a connection failure. |
| Oversized frame or bucket fan-out | Memory or CPU denial of service | Limit each JSONL frame to 1 MiB, retain at most 128 quota buckets, cap pending RPC requests at four, and bound stderr retention. |
| Orphaned child process | Leave a credential-bearing/networked process running after quit, sleep, or restart | Serialize lifecycle transitions, close input, request graceful termination, wait with a deadline, then send a targeted force termination to the tracked child PID. Never use broad process-name killing. |
| Supply chain compromise | Malicious source, toolchain, or release artifact | No third-party runtime packages; review standard Git history; run tests and package verification; exclude build output from Git; publish checksums and provenance; protect release credentials outside the repository. |
| Weak or missing signature | Users cannot authenticate the publisher; modified bundles may execute | Verify ad-hoc signatures only for local staging integrity. Require Developer ID signing, hardened runtime, notarization, stapling, and Gatekeeper tests for every public artifact. Do not claim publisher identity for local builds. |
| Global hotkey conflict | Shortcut does not work or intercepts an unexpected chord | Register only the documented `⌥⌘U` shortcut, report registration failure, and retain menu bar controls. The hotkey requests no Accessibility or Input Monitoring permission. |
| Preference tampering | Alter UI choices, approved fingerprints, or notification state | Treat preferences as untrusted local input; decode defensively; revalidate approved executable identity before use; never store credentials in preferences. |
| Malicious App Server stderr or exit behavior | Memory growth, log disclosure, or shutdown hangs | Bound stderr tail, do not persist it by default, ignore late callbacks by generation, and enforce targeted shutdown deadlines. |
| Accidental privacy disclosure in repository or package | Publish paths, credentials, account data, or quota history | Run source and artifact scans, strip release debug paths, inspect ZIP contents, keep `dist/` and `.build/` ignored, and review staged Git changes before publishing. |

## Data flow

1. QuotaPet discovers candidate Codex paths without executing them.
2. It inspects path ownership, permissions, file identity, hash, and signing metadata.
3. An allow-listed official bundle may be trusted automatically; other candidates require user confirmation.
4. QuotaPet launches the approved executable as a child and exchanges bounded JSONL over pipes.
5. The child reads normal Codex configuration/credentials and connects to OpenAI; QuotaPet receives only usage responses needed for the UI.
6. QuotaPet keeps the current snapshot in memory and stores only preferences, trust fingerprints, and notification threshold state.

## Residual risks

An already compromised macOS account or approved Codex installation can bypass these gates. Ad-hoc local signing proves integrity after staging but not publisher identity. A global shortcut cannot reliably surface third-party menu bar UI on the macOS lock screen. Users must unlock the Mac and use the menu or shortcut afterward.
