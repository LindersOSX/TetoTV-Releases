# TetoTV update channels

TetoTV defaults every fresh installation to the **Public** update channel.
Developer mode is unlocked by activating **Settings > System** ten times. Its
Public/Beta choice is stored locally in encrypted preferences and can be
changed later.

Both channels use anonymous GitHub release requests. App updates do not use the
TetoTV Render broker, a GitHub token, a shared Beta key, or any other update
credential. The repository selected by the channel is the trust boundary.

### Legacy migration window

Builds released before 1.0.2/2.0.5 cannot run this direct-GitHub updater yet.
Keep the already-deployed compatibility endpoint available long enough for
1.11.x installs to receive the current Public APK and for 2.0.x Beta installs
to receive the current Beta APK. New builds never call that endpoint. Do not
deploy the source-tree broker cleanup until the migration window is complete;
otherwise old Public clients can fall through to the Beta repository and old
Beta clients cannot update at all. After adoption is verified, deploy the
cleanup and remove the legacy update secrets/routes.

## Public releases

Public reads the latest completed release from:

```text
https://api.github.com/repos/LindersOSX/TetoTV-Releases/releases/latest
```

The current Public release is `v1.0.2`. The release should contain exactly one
signed universal APK with both supported ARM ABIs, preferably named
`TetoTV-v1.0.2-universal.apk`.

## Beta releases

Beta reads the latest completed release from:

```text
https://api.github.com/repos/LindersOSX/TetoTV/releases/latest
```

The current Beta release is `v2.0.5`, with the user-facing name
**TetoTV 2.0.5 Beta**. The repository determines that this is the Beta channel;
the client does not require GitHub's `prerelease` field to be `true`. Publish a
normal, non-draft release so GitHub's `/releases/latest` endpoint can return it.

## Shared GitHub contract

The updater uses the same release parser and validation rules for both
repositories. Requests are anonymous and send no `Authorization` header. The
latest endpoint supplies the version, title, release notes, publication time,
and release assets. The updater chooses an APK whose name ends in
`-universal.apk` (case-insensitive) before considering another `.apk` asset.
It downloads the selected file directly from that asset's
`browser_download_url`; APK bytes never pass through Render.

Developer-mode release history also comes anonymously from the selected
repository's GitHub releases API. Drafts, malformed versions, releases outside
the selected 1.x Public or 2.x Beta family, and releases without an APK are not
offered. The same universal-asset preference applies to history entries.

GitHub's release asset `digest` is verified when present. The existing installer
flow continues to show download progress and validates the downloaded APK's
size, digest when supplied, package ID, signing certificate, Android build
code, SDK compatibility, ABI compatibility, and version name before opening
Android's installer. These rules apply equally on phones, Android TV, and Fire
TV.

## Switching and rollback

Public `1.0.2` and Beta `2.0.5` use Android `versionCode` `410001`, the same
application ID, and the same production signer. This lets Developer mode move
between compatible completed Public 1.x and Beta 2.x releases even when the
target's user-facing SemVer is lower. Once the installed major family matches
the selected channel, ordinary version comparison resumes so automatic checks
do not repeatedly offer the installed release.

Releases offered for rollback must keep the same package ID, signer,
compatible SDK/ABIs, and Android `versionCode`. Android rejects a lower build
code. Raising the code intentionally creates a one-way boundary: older history
can remain visible but cannot be installed over the newer build.

Public versioning restarted below the earlier private 1.11.x line. The updater's
existing build-code migration rule handles eligible older installs while
keeping ordinary version checks for current Public builds.

## Publishing checks

Before publishing either channel:

1. Build one universal APK containing `armeabi-v7a` and `arm64-v8a`.
2. Sign it with the protected production key used by the installed builds.
3. Keep Android `versionCode` `410001` while bidirectional Public/Beta rollback
   is required.
4. Publish a normal completed `vX.Y.Z` GitHub release, never a draft.
5. Attach the universal APK and required notices/source artifacts; do not
   attach competing per-ABI APKs.
6. Verify the anonymous GitHub response and hosted APK digest after publishing.
7. Install over the preceding build and exercise check, notes, download
   progress, verification, and Android installer launch on phone, Android TV,
   and Fire TV test targets.

No Beta update key or GitHub token belongs in a Dart define, APK, Render
environment, app preference, command line, or release artifact.
