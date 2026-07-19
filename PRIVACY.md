# QuotaPet Privacy Notice

Last updated: 2026-07-19

QuotaPet is a local-first desktop application with no developer-operated server, account system, analytics, advertising, crash upload, telemetry, or remote configuration service.

## Data processed in memory

The main process receives quota-window percentages and reset times from the official Codex App Server child process. It uses the current snapshot to render the menu bar, pet, and local notifications. It does not call identity endpoints, request an email address or account ID, or build a usage history.

The QuotaPet main process does not initiate outgoing network requests and does not read Codex credentials. It does not access browser cookies, project directories, clipboard contents, screen contents, camera, or microphone. It passively observes macOS connectivity state only to decide when an already approved Codex child process may refresh after network recovery.

## Official Codex child process

After the user approves an inspected Codex executable, QuotaPet launches the official Codex App Server over standard input/output. That separate child process follows normal Codex authentication, may read Codex configuration and credentials, and connects to OpenAI. QuotaPet does not intercept, copy, or persist those credentials.

## Data stored locally

QuotaPet stores only:

- non-sensitive preferences such as pet visibility, position, refresh mode, hotkey, notifications, and launch-at-login choice;
- trust fingerprints for approved Codex binaries, including the canonical path, file identity/hash, ownership, and signing metadata;
- notification de-duplication state: quota bucket identifier, reset time, and a threshold bitmask.

QuotaPet does not store tokens, email addresses, account identifiers, usage samples, quota history, project names, or App Server responses. Settings are stored with macOS `UserDefaults`. Launch-at-login state is managed by macOS.

## Permissions

The application bundle declares no camera, microphone, screen recording, Accessibility, Input Monitoring, Apple Events, or Network Extension permission. Local notifications are requested only when the user enables them. The Carbon global hotkey does not require Accessibility or Input Monitoring access.

## Retention and deletion

Preferences remain on the Mac until the user resets them. Removing the app does not silently delete settings. The uninstall section in [README.md](README.md) documents the separate, intentional reset command.

## Changes and questions

Material privacy changes will be documented in Git history and release notes. For a suspected security or privacy vulnerability, use the private reporting process in [SECURITY.md](SECURITY.md).
