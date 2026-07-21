# Releasing QuotaPet

[简体中文](RELEASING.zh-CN.md)

QuotaPet is currently **preparation-only** for public distribution. Never publish an ad-hoc signed build. A public release requires a Developer ID Application identity, Apple notarization credentials, the protected GitHub `release` environment, and a separate clean-machine Gatekeeper check.

## Version policy

QuotaPet follows Semantic Versioning:

- PATCH: compatible fixes, polish, documentation, or localization.
- MINOR: compatible user-facing features.
- MAJOR: incompatible behavior, storage, trust, or distribution changes.

`VERSION` is the marketing-version source of truth. `CFBundleShortVersionString` in `Resources/Info.plist` must match it. Increment `CFBundleVersion` for every distributed build, including a rebuilt release candidate.

## Prepare a version

1. Start from a clean, reviewed branch.
2. Update `VERSION`, both Info.plist version fields, `CHANGELOG.md`, and `CHANGELOG.zh-CN.md`.
3. Run:

   ```bash
   git diff --check
   swift test --disable-sandbox
   ./scripts/build-app.sh
   ./scripts/verify-package.sh
   ./scripts/measure-performance.sh
   ```

4. Confirm the built app reports the intended version and contains both `en.lproj` and `zh-Hans.lproj`.
5. Review privacy, security, dependency, license, and release-note changes.

## Legal and brand release gates

Treat each item as fail-closed and record the reviewer/date in the release pull request:

1. Repeat a public **name conflict** search for `QuotaPet` in the intended markets.
2. Review the current **OpenAI brand** rules and confirm the app title and icon do not imply affiliation.
3. Review **asset provenance** for code-generated art plus every font, image, icon, sound, and screenshot.
4. Run a **dependency license** review and confirm `DEPENDENCIES.md` matches the package graph.
5. Review every **privacy change**, new permission, network destination, persisted field, and diagnostic output.
6. Obtain **formal trademark clearance** before commercialization, App Store submission, or entry into a new target market. Public searching is only preliminary; useful starting points include WIPO's [Global Brand Database](https://www.wipo.int/en/web/global-brand-database) and [CNIPA](https://www.cnipa.gov.cn/art/2020/6/17/art_75_126939.html).

Also re-read [LEGAL.md](../LEGAL.md) and confirm the non-affiliation and compatibility statements still match actual behavior.

## Release prerequisites

Configure the protected GitHub environment named `release`, restrict it to version tags, require reviewers, and add only these secrets there:

- `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`
- `SIGNING_IDENTITY`
- `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`

The workflow fails closed when a prerequisite is missing. It signs with hardened runtime and timestamping, uses `notarytool`, staples and validates the app and DMG, runs Gatekeeper, creates SHA256 checksums and an SPDX SBOM, emits GitHub attestations, and generates a version-pinned Homebrew cask.

## Tag and publish

Only after every prerequisite is confirmed:

```bash
git tag -s v0.1.3 -m "QuotaPet 0.1.3"
git push origin v0.1.3
```

The tag must exactly match `VERSION` and Info.plist. The release workflow publishes `QuotaPet-VERSION.zip`, `QuotaPet-VERSION.dmg`, `SHA256SUMS`, the SBOM, and `quotapet.rb`.

Download the final artifacts as an ordinary user on a clean macOS account or VM. Verify checksums and attestations, confirm Gatekeeper launch, confirm English and Simplified Chinese operation, and test a real read without recording private output. Announce the release only after this check passes.

## Homebrew

The generated cask pins the versioned GitHub Release URL and literal DMG SHA256; it never uses `latest`. Submit that cask to the maintained tap only after the corresponding Release is public and verified. Future updates use `brew upgrade --cask quotapet`.

## Rollback

Do not rewrite or delete a published tag. If a release is unsafe, mark it clearly in GitHub, remove it from the Homebrew tap, and publish a higher patch version containing the correction. Users can temporarily reinstall a previously verified versioned artifact. Preserve checksums, release notes, and the Git history for auditability.

## Current 0.1.4 status

Version 0.1.4 build 10 may be built and installed locally. Do not tag or publish it until the signing, notarization, protected-environment, legal-review, and clean-machine prerequisites above are actually available.
