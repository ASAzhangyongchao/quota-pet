# QuotaPet semantic glow and public-release legal hardening design

## Decision

Implement the approved **A — semantic soft glow** direction and the previously approved public-release legal hardening together as QuotaPet `0.1.3` (build `4`).

The visual treatment stays native, static, and compatible with the existing macOS 13 minimum. The public product name remains **QuotaPet**, the generated Q-shaped pet icon remains unchanged, and descriptive Codex quota names remain in the usage UI. The app must not adopt OpenAI logos, OpenAI Sans, model names in the app title, copied third-party artwork, or continuous decorative animation.

## Context and plugin guidance

QuotaPet is a menu-bar accessory with a borderless `NSPanel`. The collapsed pet is drawn by AppKit/Core Graphics, while the expanded detail embeds SwiftUI inside an `NSVisualEffectView`. This is already the correct architecture for a lightweight always-on-top utility.

The Build macOS Apps review changes the implementation approach in four ways:

1. Keep AppKit as the narrow owner of the panel, anchoring, screen clamping, and transparent glow margins.
2. Keep SwiftUI as the source of truth for detail content and quota presentation.
3. Use the existing system visual-effect material instead of recreating blur or requiring newer Liquid Glass APIs that would break macOS 13 compatibility.
4. Use fixed shadow paths and state-driven redraws instead of repeating animations, shaders, or timers.

## Considered visual directions

### A — semantic soft glow (selected)

A restrained status-colored halo, a high-contrast two-segment quota ring, and two-segment meters in the detail cards. This is the best balance of visibility, long-term comfort, accessibility, and energy use.

### B — minimal edge light

Only a faint neutral edge light plus the two-segment ring. This is the cheapest rendering option but does not sufficiently separate the expanded panel from complex desktop content.

### C — atmospheric neon

A wide, saturated halo that changes strongly with status. This is highly visible but too distracting for an always-on-top utility and needs larger transparent margins.

## Collapsed pet design

### Geometry and anchoring

- The visible pet remains 72 points; it must not become visually larger.
- A transparent 6-point halo margin wraps the pet, making the collapsed panel 84 by 84 points.
- The expanded panel uses the same 6-point outer margin. The inner glass card begins at the same visual origin as the collapsed pet, so the pet does not jump when expanding or collapsing.
- The panel frame, including the transparent halo margin, remains clamped to the active display's visible frame. The halo may touch the display edge, but no part of the panel may be dragged off-screen.
- Expansion and collapse keep the current top-left anchor and preserve the existing cross-display behavior.

### Quota ring

- Replace the current same-hue track/arc treatment with two explicit semantic segments:
  - **used:** warm coral-orange;
  - **remaining:** luminous mint.
- Keep a dark neutral backing track so both segments remain legible on light and dark backgrounds.
- Preserve the numeric badge as the remaining percentage. The combination of segment length, color, and text prevents color from being the only signal.
- The remaining segment is slightly brighter than the used segment because remaining quota is the primary product signal.
- Stale data reduces saturation and opacity; unavailable data keeps the existing dashed neutral ring.
- The menu-bar ring reuses the same semantic color constants and receives a small line-width/contrast adjustment, but no menu-bar halo.

### Halo

- Draw one static accent halo behind the visible pet using a bounded layer with an explicit circular shadow path.
- Ready data uses a mint/cyan halo. Warning and depleted states use amber/red. Unavailable data uses a subdued neutral blue-gray.
- The halo does not pulse, rotate, or animate continuously.
- Existing click, hover, and blink animations remain bounded and do not add a second glow animation.

## Expanded detail design

### Glass container and outer glow

- Refactor the current clipping `NSVisualEffectView` into a transparent outer container plus an inset inner material view.
- The inner view keeps the `.hudWindow` system material, active state, 22-point continuous corners, and an adaptive hairline border.
- The outer container owns the fixed shadow paths. It supplies one dark ambient shadow and one restrained mint/cyan accent halo without masking them at the card edge.
- The `NSPanel` does not add a second competing shadow.
- The card remains visually anchored to the collapsed pet and continues to grow rightward/downward, shifting only when required to remain on-screen.

### Quota cards

- Each quota card adds a 6–7 point two-segment meter using the same used/remaining colors as the pet.
- Existing text remains authoritative: quota name, remaining percentage, used percentage, reset date, and reset countdown.
- The meter is not animated during ordinary refreshes. It updates atomically with the snapshot to avoid flicker.
- Card fills and strokes use adaptive semantic foreground opacity rather than fixed white chrome. This improves both light- and dark-mode contrast while preserving the outer system material.
- The existing exact labels **General usage limit** and **GPT-5.3-Codex-Spark usage limit**, with their Simplified Chinese equivalents, remain unchanged.

## Accessibility and system settings

- Respect Reduce Motion; no new motion is introduced.
- Respect Reduce Transparency by replacing the inner blur with an adaptive solid window background while retaining a clear border and the two-segment meters.
- Respect Increase Contrast by strengthening the card border, ring backing track, and text contrast rather than increasing glow intensity.
- Accessibility labels continue to state the numeric remaining percentage and reset information. The new meters receive combined used/remaining accessibility values.
- The glow is decorative and never the sole indication of ready, stale, warning, or unavailable state.

## Performance boundaries

- No repeating glow animation, display link, shader, timer, network request, history database, or third-party package.
- Use explicit `shadowPath` values so Core Animation does not infer dynamic shadows every frame.
- Recompute paths only on bounds, appearance, accessibility, connection-mode, or quota-state changes.
- Keep the 72-point pet drawing plan bounded and retain its current path-count contract.
- Energy-saver mode uses the same static geometry with reduced halo opacity; it must not add wakeups.
- Preserve the existing performance baseline and package audit. Any measurable regression outside the existing thresholds blocks release.

## Local diagnostics

Do not add analytics or remote telemetry. If implementation debugging needs instrumentation, use a small number of local Apple unified-log events or test-only signposts for expand/collapse and appearance fallback paths. They must not contain percentages, account data, executable paths, credentials, or project content, and temporary noisy logs must be removed before release.

## Legal and brand hardening

### Repository documents

- Add `LEGAL.md` for English and `LEGAL.zh-CN.md` for Simplified Chinese. Keep them as separate maintained documents.
- Cover non-affiliation, OpenAI/Codex/ChatGPT/GPT trademark ownership, descriptive model-name use, the documented Codex App Server dependency, no rate-limit circumvention, interface-change risk, user responsibility, MIT warranty limits, and the fact that the document is not legal advice.
- Record that the QuotaPet name, Q-shaped mascot, ring treatment, and generated icon originate in this repository's drawing code and do not use OpenAI artwork or third-party image assets.
- Add English and Simplified Chinese contribution guidance requiring provenance and license review for code, fonts, images, icons, sounds, screenshots, and dependencies.

### Product disclosure

- Add a concise localized About & Legal section to Settings: QuotaPet is unofficial and is not affiliated with or endorsed by OpenAI; third-party marks belong to their owners.
- Do not add a developer backend or a legal-document web request. Full legal documents remain in the public repository and release source archive.
- Link the correct language legal document from each README and user guide.

### Release gates

- Extend both release guides with manual checks for name/title conflicts, OpenAI brand-rule changes, third-party asset provenance, dependency licenses, privacy changes, and target-market trademark clearance before commercialization or App Store submission.
- Add contract tests ensuring the app title and bundle display name do not contain OpenAI, ChatGPT, GPT, or Codex; the required disclaimers and legal documents exist; and English/Chinese legal links do not drift.
- Keep the existing preliminary finding narrowly stated: no conflicting exact QuotaPet product was found in the available public search, but this is not a formal national or international trademark clearance.

## Testing and verification

1. Add failing tests for the semantic ring colors, split-meter fractions, halo state mapping, transparent-margin geometry, detail container contract, accessibility fallbacks, and legal-release gates.
2. Implement the smallest AppKit/SwiftUI changes that make those tests pass.
3. Run the full Swift test suite.
4. Build and verify the `.app` and ZIP package, including localization, bundle metadata, dependency scan, privacy/source scan, and icon checks.
5. Launch the real `.app` bundle and inspect collapsed/expanded states in light mode, dark mode, Reduce Transparency, Increase Contrast, Reduce Motion, energy-saver mode, and at every display edge.
6. Verify the avatar's visual center remains aligned through expand, drag, clamp, and collapse.
7. Run the established performance measurement and confirm no material memory, CPU, wakeup, or disk-write regression.
8. Reinstall the verified local build in `/Applications/QuotaPet.app`.
9. Review the final diff for copied assets, accidental private paths, credentials, account data, and misleading affiliation claims before commit and push.

## Non-goals

- No rebrand, new icon, animated neon, sound, account switching, quota history, background updater, analytics, or developer-operated network service.
- No change to refresh frequency, authentication, executable trust, Codex credentials, or rate-limit behavior.
- No claim that the repository documents are a formal legal opinion or complete trademark/patent clearance.
