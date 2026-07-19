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
