# Public-release checklist

This checklist treats TetoTV as a public product even when a build is shared
only with a private test group. Passing automated tests is necessary but is not
the same as legal, store, or codec certification.

## Release blockers

- Sign every APK with a unique protected release key. Reject debug keys at
  build time, keep at least two encrypted/offline backups, and never lose the
  signing identity used by installed sideload builds.
- Publish the privacy disclosure at an unauthenticated HTTPS URL, keep the
  in-app disclosure accessible by remote and touch, and provide a working
  public support/contact route.
- Choose and publish an explicit software license before exposing the source
  repository. APK distribution does not by itself grant permission to reuse
  TetoTV's source or branding.
- Verify Public and Beta update checks use anonymous GitHub requests to their
  fixed public repositories, send no token or shared Beta credential, prefer
  the `-universal.apk` asset, and download directly from its
  `browser_download_url`. During the one-release legacy migration window, keep
  the previously deployed compatibility route available only for pre-1.0.2 and
  pre-2.0.5 clients; new builds must never call it. After migration adoption is
  verified, deploy the broker cleanup and confirm `/v1/app-updates/*` and all
  update-specific secrets are gone.
- Deploy exactly one broker instance while pairing state is process-local, or
  move pairing/rate-limit state to an atomic shared TTL store before scaling.
- Obtain any required AniList authorization for a client that also integrates
  MAL, and confirm the current terms for every metadata, tracking, skip-time,
  and debrid service.
- Confirm that the intended Teto name/artwork use and monetization comply with
  the official character guidelines and obtain permission where required.
- Archive and ship the exact third-party notices, native binary provenance,
  and GPL/LGPL source/relinking materials required for the release build. Run
  `powershell -ExecutionPolicy Bypass -File tool/release/verify_native_redistribution.ps1`
  before building, then run it with `-StageBundle` and publish the generated
  native source bundle beside the APK. Review every reported upstream
  provenance limit before approving distribution.
- Verify the vendored QuickJS 2026-06-04 archive and reviewed FFI bridge with
  `powershell -ExecutionPolicy Bypass -File tool/android/verify_vendored_quickjs.ps1`, then run the packaged runtime and
  infinite-loop interruption tests on a 16 KiB-page Android device. Do not
  reintroduce the legacy QuickJS 2021-03-27 JitPack AAR.
- Decide whether automatic/manual AniSkip lookups are enabled in the public
  product, and ensure the privacy disclosure and settings accurately describe
  when episode identifiers and durations are sent.
- Revoke any credential ever embedded in an older APK and remove compromised
  historical assets before making release history public.

## Distribution modes

The GitHub/sideload build may keep the signed in-app updater and
`REQUEST_INSTALL_PACKAGES`. A Google Play build must remove that permission and
the direct APK installer, use Play-managed updates, complete the Data safety
form, and link the public privacy policy. Do not upload the sideload flavor to
Google Play.

The extension marketplace downloads user-selected JavaScript and runs it in a
bounded interpreter. A Play distribution must separately review or disable
that feature and prove that every remotely loaded extension and resulting
content complies with current Google Play dynamic-code, device/network-abuse,
content, and intellectual-property policies. Passing Android security tests is
not a Play policy approval.

Choose a permanent application ID before the first store release. Changing
`dev.animetv.anime_tv` later creates a different Android app and breaks normal
in-place updates.

## Technical gate

1. Start from a reviewed, clean commit and explicitly stage files; never use a
   broad add that could include screenshots, keystores, or local configuration.
2. Include the AI-assisted development disclosure in the GitHub release notes
   and confirm the in-app About/Legal disclosure is present and readable.
3. Run Flutter formatting, analysis, unit/widget/integration tests, broker
   syntax/self-tests, Android JVM tests, release lint, and Kotlin compilation.
4. Build exactly one public APK with the protected production signing key: the
   Universal APK containing `armeabi-v7a` and `arm64-v8a`. Keep x86_64 and
   separate per-ABI APKs test-only; do not upload them as release assets unless
   policy changes.
5. Verify package ID, version codes, signer identity, v2/v3 signatures,
   zip/page alignment, supported ABIs, min/target SDKs, manifest permissions,
   and absence of debug flags/secrets/default source URLs.
6. Install the universal APK on at least one phone and one TV; test first-run
   setup, D-pad/touch navigation, all pairing flows, source import, search,
   stream recovery, audio/subtitle selection, resume, tracking, and update
   download/install.
7. Install the same Universal APK on a 32-bit Fire TV, ARM64 Google
   TV/Chromecast, foldable phone portrait/landscape, and a 16-KiB-page Android
   device or emulator.
8. After all local checks pass, publish one normal completed release containing
   exactly one APK variant: the verified Universal APK. Also attach the required
   native corresponding-source bundle and third-party notices/license artifact;
   do not attach per-ABI APK variants. Immediately compare the hosted APK digest
   and GitHub-downloaded bytes to the local file before announcing it.

## Content/source policy

Release builds must contain no torrent index, default source repository,
preconfigured Stremio manifest, provider credential, or instructions that
promote an infringing source. Users must deliberately add compatible sources
they trust and are authorized to use. This design reduces risk but does not
guarantee immunity from copyright, trademark, service-terms, or platform
complaints.
