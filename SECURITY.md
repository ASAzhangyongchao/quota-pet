# Security Policy

## Supported versions

During the `0.1.x` preview, only the latest tagged release receives security fixes. Development snapshots and locally modified builds are not supported release artifacts.

## Report a vulnerability

Use the repository's **Security → Advisories → Report a vulnerability** private reporting flow. Please do not open a public issue for an unpatched vulnerability.

Include the affected version and macOS version, reproduction steps, expected impact, and a minimal proof of concept without credentials or personal data. Maintainers will acknowledge a complete report, investigate it, coordinate a fix and disclosure, and credit the reporter if requested.

## Security boundaries

- QuotaPet validates and fingerprints a Codex executable before first use and revalidates its file identity before launch.
- Untrusted Codex paths are never silently executed.
- JSONL frames, parsed bucket counts, pending RPC requests, stderr retention, and executable size are bounded.
- Child-process shutdown is coordinated and escalates to a targeted force termination if graceful termination times out.
- The app requests no privileged entitlement and never embeds credentials.

The official Codex App Server is a separate trusted dependency. It runs as the current user, uses normal Codex authentication, and connects to OpenAI. A compromised operating system, compromised approved Codex executable, or compromised user account is outside QuotaPet's protection boundary.

See [THREAT_MODEL.md](THREAT_MODEL.md) for detailed threats and gates.

## Signing and release policy

Local builds use an ad-hoc signature only to verify bundle integrity during staging and installation. Ad-hoc signing does not authenticate a publisher.

Any public binary release must use a valid Developer ID Application identity, hardened runtime, Apple notarization and stapling, checksums, provenance/attestation, and Gatekeeper verification on a clean user environment. Release credentials must remain outside the repository and CI logs.

## Reproducible network and file-access audit

Build and install the exact release candidate, launch it, and record its PID:

```bash
PID="$(pgrep -x QuotaPet)"
lsof -nP -a -p "$PID" -i
pgrep -P "$PID"
```

The first command should show no network socket owned by the QuotaPet main process. A Codex App Server child PID may appear after trust approval and may connect to OpenAI.

In a dedicated test account, use the macOS file-system activity tool while refreshing usage:

```bash
fs_usage -w -f filesystem QuotaPet
```

Confirm that the QuotaPet main process reads its bundle, preferences, and inspected Codex executable metadata/content for fingerprinting, but does not open Codex credential files or project directories. Audit the child PID separately because its access to Codex configuration and credentials is expected. Stop the trace before sharing results and review it for personal paths.
