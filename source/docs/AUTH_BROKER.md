# AniList and MyAnimeList QR pairing

AniList currently documents authorization-code and implicit OAuth grants, but
not RFC 8628 device authorization. MyAnimeList uses OAuth authorization code
with PKCE but likewise needs a registered application/callback. The implemented
Node broker in [`broker/`](../broker/) adapts both providers to a TV-friendly QR
flow without embedding client secrets in the APK.

## Flow

1. The TV calls `POST /v1/{provider}/pairings` over TLS, where provider is
   `anilist` or `myanimelist`.
2. The broker creates:
   - a high-entropy `device_code` known only to the TV;
   - a short human-readable `user_code`;
   - a single-use `pairing_id`;
   - a 10-minute expiry.
3. The TV displays `verification_uri_complete` as a QR code and also shows the
   user code for manual entry.
4. The phone opens the broker. The broker binds the pairing to an HTTP-only
   session cookie, then redirects to the selected provider's authorization
   endpoint with a cryptographically random `state` and PKCE where supported.
5. The provider redirects back to the broker with an authorization code. The
   broker validates `state` and exchanges the code using the registered
   credentials and exact redirect URI.
6. The TV polls the pairing endpoint at the server-provided interval. The short
   user code is never sufficient to retrieve the token.
7. Once, the broker returns the access token to the TV that proves possession
   of `device_code`, then deletes the broker-side token material.
8. The TV stores tokens with `flutter_secure_storage`. AniList calls use
   GraphQL and MyAnimeList calls use the v2 REST API.
9. MyAnimeList's refresh token is also stored in the Android Keystore. Five
   minutes before expiry, the app asks the broker to rotate it and atomically
   replaces the encrypted access/refresh credentials.

AniList tokens are long-lived and its current docs do not describe refresh
tokens. Logout removes the device copy. The broker must never log codes,
tokens, callback query strings, or authorization headers.

## Mobile approval URLs

The broker starts AniList authorization with:

```text
https://anilist.co/api/v2/oauth/authorize
  ?client_id=...
  &redirect_uri=https%3A%2F%2Ftetotv-auth.onrender.com%2Foauth%2Fanilist%2Fcallback
  &response_type=code
  &state=...
```

The broker exchanges the returned code at:

```text
POST https://anilist.co/api/v2/oauth/token
```

The redirect URI must exactly match the URI registered in AniList developer
settings.

MyAnimeList is registered with:

```text
https://tetotv-auth.onrender.com/oauth/myanimelist/callback
```

The broker uses PKCE for the authorization-code exchange. The client secret,
when the registered client has one, remains server-side.

## App-facing contract

`POST /v1/{provider}/pairings`

```json
{
  "pairing_id": "public-random-id",
  "device_code": "at-least-256-bits-of-entropy",
  "user_code": "KUMO-7F4K",
  "verification_uri": "https://tetotv-auth.onrender.com/pair",
  "verification_uri_complete": "https://tetotv-auth.onrender.com/pair?code=KUMO-7F4K",
  "expires_at": "2026-07-31T00:00:00Z",
  "interval": 5
}
```

`GET /v1/{provider}/pairings/{pairing_id}`

```http
Authorization: Pairing {device_code}
```

Pending:

```json
{ "status": "pending" }
```

Single-use success:

```json
{
  "status": "authorized",
  "access_token": "...",
  "refresh_token": "...",
  "expires_at": "2026-07-31T01:00:00Z"
}
```

`refresh_token` is returned for MyAnimeList and omitted when the provider does
not issue one.

## Finish the provider link

1. Register the two callback URLs above in the provider developer consoles.
2. Copy `broker/.env.example` to `broker/.env` and add the issued client
   credentials.
3. Deploy `broker/` at the same HTTPS origin used in the callback URLs.
4. Either enter that HTTPS origin on TetoTV's pairing screen, or set
   `AUTH_BROKER_BASE_URL` in `config/dev.json` to bake it into the APK.
5. For a preconfigured APK, build with `flutter build apk --release
   --dart-define-from-file=.\config\dev.json`.

If no broker URL is compiled into the APK, **Accounts > AniList/MyAnimeList >
Connect by QR** now opens a one-time setup panel. Paste the public HTTPS origin
with TetoTV's on-screen keyboard, choose **Save and connect**, and the address
is stored in Android's encrypted storage. The same broker is used for both
trackers. A local `localhost` URL will not work from a phone scanning the TV.

The APK never needs either provider client secret.

The broker rate-limits by IP, returns `429` with `Retry-After`, binds state to
one pairing, uses strict CSP, and expires all state. The included implementation
uses an in-memory single-instance TTL store. Replace it with an encrypted shared
TTL store before horizontally scaling the broker.

For a public product, review AniList's API terms and request authorization if
the application could be considered a competing tracker. Significant,
sustained AniList synchronization should be explicit in that request.
