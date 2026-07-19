# QuotaPet official quota names design

## Goal

Match the two quota cards to the names shown by the Codex usage interface:

- The `codex` bucket is displayed as `通用使用限额`.
- The second Codex bucket is displayed as `GPT-5.3-Codex-Spark 使用限额`.

## Scope

Only the presentation mapping changes. Percentages, reset dates, countdowns, refresh behavior, window layout, privacy boundaries, and provider parsing remain unchanged.

Because the second bucket now has a confirmed product-facing name, the previous `服务端未提供公开名称` note is removed.

## Verification

- Update the presentation unit test to assert the two exact names and no legacy note.
- Run the full Swift test suite.
- Build and verify the application package.
- Reinstall the local application and confirm the two names with real usage data.
