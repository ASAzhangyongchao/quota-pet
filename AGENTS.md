# QuotaPet Maintenance Rules

## Source of truth

- The public GitHub repository and standard Git history are the source of truth.
- Keep the project buildable, testable, releasable, and reviewable without access to any private knowledge base, private Codex task, or local-only conversation context.

## Tool portability

- GitHub operations may use the connected GitHub app, `gh`, standard `git`, the GitHub web interface, or another compatible automation tool.
- Do not make maintenance depend on one Codex task, one AI client, one plugin, or one vendor-specific hidden state.
- Keep required release prerequisites and commands in versioned repository documentation and scripts. Never store credentials in the repository.

## Safety gates

- Run the repository test suite and relevant packaging checks before publishing changes.
- Do not publish private paths, account identifiers, credentials, Codex configuration, quota history, or knowledge-base content.
- Public release artifacts require the documented signing, notarization, checksum, and provenance checks; a local ad-hoc build is not a public release.

## Product / UX defaults (owner expectations)

These are standing product rules for agents across sessions:

1. **Releases after meaningful changes** — When shipping user-visible fixes or features, plan a GitHub Release update. Prefer artifacts that include a **`.dmg`** (and usually `.zip`). An empty “version marker” Release is only for in-app update checks via `releases.atom`; do not describe it as a downloadable installer.
2. **Notarized DMG requires Developer ID** — Follow `docs/RELEASING.md` / `docs/RELEASING.zh-CN.md`. Do not enable `ENABLE_NOTARIZED_RELEASE=1` or claim a Gatekeeper-ready public package without Developer ID Application + notary credentials. If credentials are missing, say so and fall back to local `./scripts/build-app.sh` + `./scripts/install-local.sh`, or ask before uploading an ad-hoc DMG.
3. **Settings `?` help** — Every help popover must explain what the control does, when it applies, and where the effect appears. Connection mode help must make “energy saving vs real-time” choosable for daily use.
4. **Keyboard shortcuts** — Keep a dedicated “Keyboard shortcuts” row that opens a sheet listing **all** `AppHotKey` bindings with title, explanation, and per-row change/reset. Do not bury a single recorder under Connection.
5. **Codex sources** — Dual cards for ChatGPT-bundled vs terminal Codex. A shell `codex` that resolves to the ChatGPT bundle is not a terminal install. Rescan must show an explicit scan-result message.
6. **Local GitHub connectivity** — If `git push` to github.com times out on this machine, retry with the user’s local proxy (commonly `https_proxy=http://127.0.0.1:7897`) without rewriting git config.
