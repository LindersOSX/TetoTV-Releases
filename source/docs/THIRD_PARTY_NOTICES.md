# Third-party notices

TetoTV's default Android player and its independent compatibility engines use
the following third-party components:

| Component | Use in TetoTV | Upstream license |
| --- | --- | --- |
| AndroidX Media3 1.11.0 (`media3-exoplayer`, `media3-ui`, `media3-session`, and `media3-datasource-okhttp`) | Native default player, `PlayerView`/`SurfaceView`, MediaSession, and OkHttp-backed media data source | Apache License 2.0 |
| Google Material Icons | Rounded/outlined vector glyphs that keep the native Media3 HUD visually aligned with Flutter's Material icons | Apache License 2.0 |
| OkHttp | HTTPS redirects, byte-range requests, retries, and debrid request headers for Media3 | Apache License 2.0 |
| `media_kit`, `media_kit_video`, and `media_kit_libs_android_video` | MPV compatibility player and Flutter integration | MIT License for the media_kit projects; bundled native components retain their own licenses |
| mpv, FFmpeg, and libass | Compatibility decoding and styled ASS subtitle rendering inside the media_kit Android runtime | Their respective upstream licenses apply; the exact v1.1.7 binary provenance and conservative GPL/LGPL license set are recorded in `NATIVE_PLAYBACK_REDISTRIBUTION.md` |
| `flutter_vlc_player` 7.4.4 | Flutter integration for the final VLC fallback | BSD 3-Clause License |
| VideoLAN libVLC 3.6.3 | Final software compatibility player | GNU Lesser General Public License 2.1 or later, subject to the licenses of included modules |
| Vendored `flutter_js` 0.8.7+tetotv.1 | Dart/Android bridge for the isolated add-on JavaScript runtime | MIT License; copyright 2019 Ábner Oliveira |
| Android JS Runtimes bridge 0.3.6 (locally reviewed) | Source-derived FFI bridge used by the in-tree Android QuickJS build | MIT License; copyright 2020 fast-development |
| QuickJS 2026-06-04 | JavaScript engine built from pinned official source inside the Android plugin | MIT License; copyright Fabrice Bellard and Charlie Gordon |
| Discord Social SDK 1.10.18369 | Optional, user-authorized Discord Rich Presence on Android | Discord Social SDK Terms; the open-source notices supplied with the SDK are bundled separately |
| CryptoJS 4.2.0 | Compatibility APIs in the bundled add-on runtime | MIT License |
| LinkeDOM 0.18.12 and its bundled dependencies | Isolated HTML parsing for installed add-ons | ISC License for LinkeDOM; bundled dependencies retain their MIT, ISC, BSD-2-Clause, and other notices |
| Sucrase 3.35.0 and its bundled dependencies | Offline TypeScript transformation for installed add-ons | MIT License for Sucrase; bundled dependencies retain their MIT, Apache-2.0, and other notices |
| Dart `xml` 6.6.1 | Bounded parsing of Plex Media Server XML responses | MIT License |
| Noto Sans Regular | Bundled subtitle font used by the MPV/libass compatibility player | SIL Open Font License 1.1; copyright 2018 The Noto Project Authors |

TetoTV's optional filler labels and per-series filler skipping read episode
metadata from the public Jikan REST API. Jikan is a network service rather than
code bundled in the APK; its server implementation is MIT licensed, while the
episode metadata it exposes originates from MyAnimeList and remains subject to
the applicable upstream service terms. TetoTV does not scrape Anime Filler
List or MyAnimeList directly.

Upstream projects and license sources:

- AndroidX Media3: <https://github.com/androidx/media>
- OkHttp: <https://github.com/square/okhttp>
- media_kit and its Android native-library package:
  <https://github.com/media-kit/media-kit>
- mpv: <https://github.com/mpv-player/mpv>
- FFmpeg: <https://ffmpeg.org/legal.html>
- libass: <https://github.com/libass/libass>
- flutter_vlc_player:
  <https://github.com/solid-software/flutter_vlc_player>
- VLC for Android/libVLC:
  <https://code.videolan.org/videolan/vlc-android>
- flutter_js: <https://github.com/abner/flutter_js>
- Android JS Runtimes bridge tag 0.3.6:
  <https://github.com/fast-development/android-js-runtimes/tree/0.3.6>
- QuickJS 2026-06-04: <https://bellard.org/quickjs/>
- Discord Social SDK: <https://discord.com/developers/docs/social-sdk/index.html>
- CryptoJS: <https://github.com/brix/crypto-js>
- LinkeDOM: <https://github.com/WebReflection/linkedom>
- Sucrase: <https://github.com/alangpierce/sucrase>
- Dart xml: <https://github.com/renggli/dart-xml>
- Noto Sans: <https://github.com/notofonts/noto-fonts>
- Jikan REST API: <https://github.com/jikan-me/jikan-rest>

The exact resolved Dart package versions are recorded in `pubspec.lock`.
Native Android versions are declared in `android/app/build.gradle.kts`, plugin
Gradle metadata, and the resolved Gradle dependency graph. Copyright notices
and complete license texts shipped by those dependencies remain applicable.
When redistributing an APK, retain those notices and comply with the source,
relinking, attribution, and other requirements that apply to the exact native
binaries in that build. This summary is not a replacement for the full license
texts.

The minified JavaScript bundles are produced with license comments removed, so
the separate license assets and the complete notices for every package actually
included by the bundler must ship with the APK. `tool/addon_runtime/package-lock.json`
is the dependency provenance record; `docs/DEPENDENCY_VERIFICATION.md` records
the native QuickJS source archive hash, reviewed bridge delta, and verification
procedure. The Android JS Runtimes and QuickJS MIT notices must remain bundled
with every redistributed APK.

The Flutter license page includes notices generated from resolved Dart and
Android packages. The APK also carries complete GPL 2.0, GPL 3.0, LGPL 2.1,
and LGPL 3.0 texts, the libmpv Android build's default-flavor MIT notice, and
the native playback notice under
`assets/legal/native/`. Exact binary hashes, source revisions, rebuild and
relink instructions, and known evidence limits are in
[`NATIVE_PLAYBACK_REDISTRIBUTION.md`](NATIVE_PLAYBACK_REDISTRIBUTION.md).
A distributor must run the verifier, stage the corresponding-source bundle,
and make that bundle available alongside every APK. Neither this summary nor
the in-APK notice is, by itself, a source-code offer.

## Kasane Teto name and artwork

TetoTV is an independent, unofficial application and is not endorsed by the
Kasane Teto rights holders. The launcher artwork, character name, and related
branding must be used in accordance with the official Kasane Teto character
guidelines: <https://kasaneteto.jp/guidelines/>.

Required character attribution retained by the app:

```text
重音テト © 線 / 小山乃舞世 / TWINDRILL
```

Those guidelines and any separate commercial-use permissions apply in
addition to the software licenses above. A distributor is responsible for
confirming that its particular release, artwork, territory, and monetization
model are permitted.
