# QuotaPet official quota names and anchored window design

## Goal

Match the two quota cards to the names shown by the Codex usage interface:

- The `codex` bucket is displayed as `通用使用限额`.
- The second Codex bucket is displayed as `GPT-5.3-Codex-Spark 使用限额`.

## Scope

Only the presentation mapping changes. Percentages, reset dates, countdowns, refresh behavior, window layout, privacy boundaries, and provider parsing remain unchanged.

Because the second bucket now has a confirmed product-facing name, the previous `服务端未提供公开名称` note is removed.

## Anchored window interaction

The 72-point collapsed pet is the top-left anchor of the expanded detail window:

- Expansion grows from the pet toward the right and bottom.
- The expanded header pet remains at the same visual top-left anchor.
- Moving the expanded window moves the pet with it.
- Collapse shrinks back to the expanded window's current top-left corner instead of restoring an older position.

Both collapsed and expanded frames are clamped to the visible frame of the current display. A pet can touch a display edge but cannot be dragged beyond it. If an expanded window would cross the right or bottom edge, the complete window shifts left or up just enough to remain visible; the pet remains in the window's top-left corner. The same rule applies independently on each display.

This behavior is implemented as pure frame geometry plus controller-level application, without adding timers, polling, or continuous animation.

## Verification

- Update the presentation unit test to assert the two exact names and no legacy note.
- Add geometry tests covering top-left expansion, right/bottom edge adjustment, collapse anchoring, and drag clamping.
- Verify the controller keeps the same top-left anchor through expand, move, and collapse transitions.
- Run the full Swift test suite.
- Build and verify the application package.
- Reinstall the local application and confirm the names, anchored transition, and screen-edge behavior with real usage data.
