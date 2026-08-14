# Native playback redistribution record

This record covers the native playback binaries resolved by the current ARM
universal Android build. It records evidence and a practical replacement path;
it is not legal advice or a claim of compliance.

## Binary identity

`media_kit_libs_android_video` 1.3.8 downloads the `default` JARs from
`media-kit/libmpv-android-video-build` v1.1.7. The release tag resolves to
commit `fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768`.

| ABI | Published file | SHA-256 |
| --- | --- | --- |
| arm64-v8a | `default-arm64-v8a.jar` | `4363dfa5d3d415b91c1f16f6fb90c3fe59a77dfd3f9b824d2b24b492d6b09df9` |
| armeabi-v7a | `default-armeabi-v7a.jar` | `8ead114fc5a43348d89dc0eb8f41823e549b15115c29f73ee26973f973620995` |

`flutter_vlc_player` 7.4.4 resolves Maven artifact
`org.videolan.android:libvlc-all:3.6.3`. The AAR SHA-256 is
`dc627487bfca9e20dec69db85288e5a0e68b04561daca8d37d9f7d2c9f5094b6`.
Its POM identifies GNU LGPL 2.1 and points to VideoLAN's source repository.
Gradle's verification metadata independently pins the same AAR hash.

The machine-readable record is
[`tool/release/native_playback_manifest.json`](../tool/release/native_playback_manifest.json).

## Source and build chain

The libmpv JARs were produced by the v1.1.7 build repository. Its pinned roots
are libmpv build commit `fe8c3ac1a91c09aa6fb1deccbc833f1bafa54768`, mpv
commit `78d43740f52db817d98bcf24fb30a76ab6fa13ff`, and
media-kit-android-helper commit `42054e5d479f39ccbb0ae604862e2bcaf59b74c2`.
The default flavor's `depinfo.sh`, patches, and configure arguments are part of
the build-repository snapshot. They select FFmpeg 6.0, libass 0.17.1, Mbed TLS
3.4.0, dav1d 1.2.0, libxml2 2.10.3, FreeType 2.13.0, FriBidi 1.0.12, and
HarfBuzz 7.2.0. Rebuild on Linux from the exact build commit, install the SDK,
NDK and host tools required by its workflow, and run
`buildscripts/bundle_default.sh`. Preserve its patches and default-flavor
configuration. Build only `arm64` and `armv7l` when reproducing TetoTV's ARM
release inputs.

The libVLC chain is VideoLAN VLC-Android tag `libvlc-3.6.3` at
`633911a9125a047355a67178ca2b42c4c75e988f`, which selects libvlcjni
`755eea54c2a0d282bbb88d3d448efbadea9a8340`; its `get-vlc.sh` selects VLC
3.0.x commit `4ce93430234330ab7d5ef15b6dfd864e75e150cb` and applies the patches
shipped in the libvlcjni snapshot. On Linux, set `ANDROID_SDK` and
`ANDROID_NDK`, then use VideoLAN's `buildsystem/compile.sh` for each ARM ABI
with `-l --release --license a`. The pinned build requires NDK 21 for
armeabi-v7a and NDK 27 or 28 for arm64-v8a. Use the repository's Gradle
publishing/assembly tasks to create the replacement AAR.

These commands are practical upstream rebuild paths, not reproducible-build
claims. Upstream v1.1.7 identifies several libmpv dependencies by mutable tag,
does not publish source-archive SHA-256 values, and contains a floating
`media_kit` clone that is not used by the final helper bundling step. A fresh
build therefore cannot be proven bit-for-bit identical from the recorded
metadata alone. The staging tool records the resolved commit of every such
tag; release review must retain and evaluate that report.

## Relinking and installation

The APK loads ABI-specific shared objects. A recipient may rebuild an
interface-compatible native stack, unpack a copy of the APK, and replace:

- `lib/<abi>/libmpv.so` and its media-kit helper libraries for the MPV stack;
- `lib/<abi>/libvlc.so`, `libvlcjni.so`, and a matching `libc++_shared.so` for
  the VLC stack.

Repack the APK, run Android SDK `zipalign`, and sign it with the recipient's
own key using `apksigner`. Verify the signature before installation. Android
does not allow an APK signed with a different key to update the official
package, so testing a modified build normally requires uninstalling the
officially signed copy first (which removes its local app data) or using a
separate application ID in a recipient-built TetoTV variant. The distribution
terms must not prohibit modification or reverse engineering needed to debug
such library changes.

## Release procedure

Run the offline verifier first:

```powershell
powershell -ExecutionPolicy Bypass -File `
  tool/release/verify_native_redistribution.ps1
```

At release time, use `-StageBundle`. This intentionally performs network-heavy
source checkouts only then, validates immutable revisions, records the commit
behind every upstream-declared tag, and writes a bundle under
`build/release-compliance`. Publish that bundle from the same release page as
the APK and retain it for as long as the binary remains available. Inspect the
generated report; do not publish if a revision, binary hash, license asset, or
source snapshot is missing.

The checked-in full GPL/LGPL texts are conservative. Component copyright and
license notices inside the staged sources determine the actual license of each
file. A qualified release reviewer must resolve the documented upstream
provenance gaps and confirm the final source offer before distribution.
