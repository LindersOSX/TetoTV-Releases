# Player HUD parity

TetoTV has two HUD implementations because MPV and VLC render inside Flutter,
while Media3 owns a native Android `SurfaceView`. The implementations follow the
same user-facing contract even though their playback APIs are different.

| Contract | MPV | VLC | Media3 |
| --- | --- | --- | --- |
| Card, title, engine/source badges | Shared `TetoPlayerChrome` | Shared `TetoPlayerChrome` | Native equivalent with the same spacing, colors, and responsive width cap |
| Control order | Back, Play/Pause, Forward, Audio, CC, Size, Picture, Player, Sources when applicable, Options | Same | Same; Sources appears when another direct stream is available |
| Action-to-progress spacing | 18 dp (15 dp compact) | 18 dp (15 dp compact) | Visual bar is 18 dp below controls inside an accessible 32 dp touch target |
| Progress and elapsed/duration | Accent progress, elapsed/duration footer | Same | Same |
| Auto-hide | 5 seconds in playing and paused states | Same | Same on TV, touch, mouse, and keyboard |
| Early dismissal | D-pad Down or tap | Same | Same |
| Reveal/focus | First directional press reveals HUD and focuses Play | Same | Same |
| Keyboard/gamepad shortcuts | J/L seek, K play/pause, S captions, Menu/M/Y options | Same | Same |
| Audio and CC unavailable state | Picker explains when tracks are unavailable | Same | Same; controls remain focusable so the native picker can explain the missing track |
| Icons and TV focus | Rounded Flutter Material glyphs; 3 dp Teto-red ring/glow with dark inner keyline, 1.025 scale over 80 ms | Same | The same Apache-2.0 Material glyph paths and timing, with a Fire TV-safe native ring/glow/keyline selector |
| Skip segment | Separate translucent overlay | Same | Separate native translucent overlay |

Engine-specific playback capabilities stay honest rather than exposing buttons
that cannot work:

- Sources is conditional in every engine. Media3 returns to Flutter to select
  the next resolved direct stream; trusted local/Jellyfin/Plex sessions hide
  the action because those sessions intentionally remain in Media3.
- MPV can create seek-preview screenshots; VLC and Media3 surfaces cannot always
  expose decoded frames safely.
- Track pickers are engine-native, but use the same Audio/CC entry points and
  restore focus to the originating control.
- Media3's video surface and dialogs remain native Android widgets. Pixel parity
  is maintained for the persistent HUD card, actions, labels, progress, footer,
  responsive geometry, and focus feedback; platform font rasterization and the
  native dialog implementation can still differ slightly from Flutter.
