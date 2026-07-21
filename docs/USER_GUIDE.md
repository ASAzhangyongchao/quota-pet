# QuotaPet User Guide

[简体中文](USER_GUIDE.zh-CN.md)

## First launch

Open QuotaPet from Applications. It is a menu bar app, so no Dock icon appears. The floating pet and menu bar ring show the remaining General usage limit. Click the pet to expand the complete detail card.

If no usage is available, QuotaPet shows the Codex executable it found. Confirm only a path you recognize. QuotaPet will revalidate the file before every launch and ask again after a meaningful file or signing change.

## Everyday controls

- Click the floating pet: expand details.
- Click the pet at the detail card's top-left: collapse details.
- Drag either state: move the whole window. The pet stays attached to the same top-left anchor and the window remains fully inside the current display.
- Click the menu bar ring: open or close the compact usage popover.
- Right-click the menu bar ring: refresh, show or hide the pet, select a connection mode, restore interaction, open Settings, User guide, About, or quit.
- In Settings, choose System / 简体中文 / English; menus, details, and refresh states update immediately.
- If a refresh stays pending too long, QuotaPet shows a reconnect notice first, then recovers once.
- Press `⌥⌘U`: show the pet and disable mouse passthrough so it can be clicked again.
- Click Refresh now: the avatar becomes a spinner, then briefly shows a checkmark after fresh data arrives.

The detail card labels the service windows as **General usage limit** and **GPT-5.3-Codex-Spark usage limit**. A countdown below 24 hours uses hours; a longer countdown uses days.

## Settings

- **Energy-saving mode** is the new-install default and exits the Codex child after a read.
- **Real-time mode** keeps one validated child session for faster updates.
- **Always on top** controls the floating window level.
- **Mouse passthrough** lets clicks reach the app behind the pet; use `⌥⌘U` or Restore pet interaction to undo it.
- Notifications are local and opt-in. Launch at login uses the macOS login-item API.
- **About & Legal** shows the current version (`x.y.z (build)`). **Check for Updates** queries GitHub Releases only when you click it; it does not auto-download.

## Language

QuotaPet defaults to the macOS preferred language. In Settings you can override that with **System**, **简体中文**, or **English**; the menu bar, detail card, refresh states, and Settings copy update immediately. Adding another language still requires only a new localization resource and catalog validation.

## Updating

In Settings → About & Legal, use **Check for Updates** to compare your marketing version with the latest published GitHub Release (via the public Releases Atom feed). If a newer release exists, open the download page from the same section. Until a public release exists, the check reports that no public release is published yet.

For a signed GitHub Release, quit QuotaPet, download the newer DMG or ZIP from the repository's Releases page, verify the published checksum, and replace the app in Applications. Preferences remain intact.

When an official Homebrew cask is published, use `brew upgrade --cask quotapet`. Until a notarized public release exists, build and install from source using the commands in the README.

## Troubleshooting

- **Usage unavailable:** make sure the official Codex app is installed and signed in, then review the displayed executable path and refresh.
- **Wrong or stale data:** click Refresh now. A warning state retains the last real reading instead of inventing a value.
- **Pet cannot be clicked:** press `⌥⌘U` or use Restore pet interaction from the right-click menu.
- **Shortcut conflict:** choose the menu bar item; Settings reports when another app owns the shortcut.
- **Pet is missing:** enable Show desktop pet and use the shortcut. Display changes automatically clamp the window back on screen.
- **Locked screen:** macOS does not reliably expose third-party menu bar UI while locked; QuotaPet does not bypass lock-screen security.

## Uninstall and reset

Disable Launch at login, quit QuotaPet, and remove `/Applications/QuotaPet.app`. Preferences are intentionally preserved. To reset them:

```bash
defaults delete io.github.asazhangyongchao.quotapet
```

## Legal and brand notice

QuotaPet is unofficial and independent. Descriptive third-party names in the quota UI do not imply affiliation or endorsement. Read the full [English legal and brand notice](../LEGAL.md) before redistributing or modifying public branding.
