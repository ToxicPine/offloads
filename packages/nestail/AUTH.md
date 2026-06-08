# Nestail Auth Plan

## Intent

Nestail auth is an optional access gate for public route URLs and their
transport requests. It is enabled only when `NESTAIL_AUTH_SECRET` is set.

When auth is enabled, a user may visit a route URL that includes a one-time
authorization grant in the URL fragment:

```text
/:port#<grant>/<target-path>
```

Example:

```text
/3000#eyJ.../dashboard
```

The grant is redeemed immediately for an HTTP-only auth cookie. After successful
redemption, the browser is redirected to the normal route URL:

```text
/3000/dashboard
```

Without a valid auth cookie, public route requests and matching transport
requests are unauthenticated and must not reach the proxied local service.

## URL Contract

The existing public route shape remains:

```text
/:port/:target-path
```

`port` is the route id and selects `http://localhost:<port>`.

Auth adds a fragment-based bootstrap shape:

```text
/:port#<grant>/<target-path>
```

Definitions:

- `port`: A decimal TCP port from `1` to `65535`.
- `grant`: A compact, URL-safe, signed one-time authorization token.
- `target-path`: The path to visit after the grant has been redeemed. It starts
  after the first `/` following the grant in the fragment.

The fragment is never sent in the HTTP request. The server cannot inspect
`#<grant>/<target-path>` during the original request for `/:port`. Therefore the
first interception step must run in browser JavaScript.

## Redirect Semantics

For:

```text
/3000#<grant>/dashboard
```

the intended post-auth URL is:

```text
/3000/dashboard
```

For:

```text
/3000#<grant>
```

the intended post-auth URL is:

```text
/3000/
```

If the post-auth target needs its own fragment, it must be encoded inside
`target-path`, for example:

```text
/3000#<grant>/dashboard%23section
```

which redirects to:

```text
/3000/dashboard#section
```

## Terms

Authorization grant:

A short-lived, signed, URL-safe token carried in the URL fragment. It is used
only to request an authenticated session cookie. It is not the session.

Grant redemption:

The server operation that verifies an authorization grant, marks its unique id
as consumed, and returns a response that sets an auth cookie.

Consumed grant:

A grant whose unique id has already been redeemed. A consumed grant must not be
accepted again while it remains within its expiry window.

Auth cookie:

An HTTP-only cookie set by the server after successful grant redemption. It is
the credential used by middleware for subsequent public route and transport
requests.

Authenticated request:

A request that carries a valid auth cookie whose signed claims authorize the
requested route id.

Unauthenticated request:

A request without a valid auth cookie for the requested route id.

## Token Model

Nestail should use two signed token types.

### Authorization Grant

Purpose: one-time bootstrap credential carried in the URL fragment.

Required claims:

- `typ`: `"nestail-auth-grant"`.
- `route`: route id, such as `"3000"`.
- `jti`: unique grant id, generated with `crypto.randomUUID()`.
- `iat`: issued-at time, as Unix seconds.
- `exp`: expiry time, as Unix seconds.

Default TTL: 20 minutes.

### Session Token

Purpose: ongoing route credential stored inside the auth cookie.

Required claims:

- `typ`: `"nestail-auth-session"`.
- `route`: route id, such as `"3000"`.
- `sid`: unique session id, generated with `crypto.randomUUID()`.
- `iat`: issued-at time, as Unix seconds.
- `exp`: expiry time, as Unix seconds.

The session token should be route-bound. A cookie minted for route `3000` must
not authenticate route `3001`.

Default TTL: three days.

## Signing

Tokens should use an HMAC-SHA-256 signature derived from `NESTAIL_AUTH_SECRET`.

The token format may be JWT-compatible:

```text
base64url(header).base64url(payload).base64url(signature)
```

Required header:

```json
{ "alg": "HS256", "typ": "JWT" }
```

The implementation should use Deno's native Web Crypto API for HMAC:

- `crypto.subtle.importKey`
- `crypto.subtle.sign`
- `crypto.subtle.verify`

## Cookie Properties

The auth cookie should be set by the grant redemption endpoint.

Recommended attributes:

- `HttpOnly`: true.
- `SameSite`: `"Lax"`.
- `Path`: `"/"`.
- `Secure`: true when the request URL is HTTPS, or when trusted proxy headers
  indicate that the original client request was HTTPS.
- `Max-Age`: no greater than the session token expiry.

The cookie value should be the signed session token, not the authorization
grant.

Proxy TLS termination:

- Nestail trusts proxy TLS headers by default.
- `X-Forwarded-Proto: https` or `X-Forwarded-SSL: on` should cause the auth
  cookie to be set with `Secure`.
- Set `NESTAIL_TRUST_PROXY_HEADERS=0` to ignore proxy TLS headers and only trust
  the request URL scheme.
- The default is intended for platforms such as Fly.io, where the platform proxy
  terminates TLS and forwards HTTP to the app.

## Middleware Boundary

When `NESTAIL_AUTH_SECRET` is unset:

- Auth is disabled.
- Existing route behavior remains unchanged.
- No auth bootstrap or auth cookie is required.

When `NESTAIL_AUTH_SECRET` is set:

- Public route requests for `/:port/...` require a valid auth cookie for `port`.
- Transport requests for `/__transport/:port/...` require a valid auth cookie
  for `port`.
- Static internal assets may remain public.
- `/__health` may remain public.
- `/__auth/consume` must remain public because it is the redemption endpoint.
- A request to `/:port` or `/:port/...` without a valid auth cookie should
  return the auth bootstrap page rather than the normal Scramjet shell.
- Transport requests without a valid auth cookie should return an authentication
  error and must not proxy to the local service.

## Implementation Boundary

Auth should be split into three layers.

Token primitives:

- Own signed token creation and verification.
- Own grant consumption state.
- Know about grant claims and session claims.
- Do not construct HTTP responses.
- Do not parse request cookies.
- Do not know about Scramjet or transport handling.

HTTP auth middleware:

- Own cookie parsing and `Set-Cookie` construction.
- Own the auth bootstrap HTML response.
- Own the `/__auth/consume` endpoint behavior.
- Expose route guard functions that return either `null` for "continue" or a
  `Response` for "stop here".
- Do not know how public routes are rendered after auth succeeds.
- Do not proxy transport requests.

Server routing:

- Own internal path dispatch.
- Resolve public route ids.
- Call the auth middleware before rendering a shell or handling transport.
- Continue to delegate Scramjet shell rendering and transport proxying to their
  existing modules.

## Browser Bootstrap

The auth bootstrap page is only used when auth is enabled and the request lacks
a valid auth cookie.

Responsibilities:

1. Read `location.hash`.
2. Parse the fragment into `grant` and `target-path`.
3. Remove the fragment from browser history with `history.replaceState`.
4. POST the grant and current route id to `/__auth/consume`.
5. On success, navigate to `/:port/<target-path>`.
6. On failure, render a small authentication error page.

The bootstrap must not store the grant in local storage, session storage,
IndexedDB, or a non-HTTP-only cookie.

## Grant Consumption Store

Grant consumption may initially be enforced in memory.

An in-memory store is sufficient for a single Nestail process. It means an
unexpired grant could be redeemed again after process restart. If restart-proof
single-use semantics are required, replace or supplement the in-memory store
with a small persistent store.

The store should retain consumed grant ids only until their expiry time.

## CLI Contract

The `nestail` command should support generating route-bound authorization
grants.

Example:

```sh
NESTAIL_AUTH_SECRET=... nestail token 3000 /dashboard
```

Expected output:

```text
http://localhost:4096/3000#<grant>/dashboard
```

The CLI should read:

- `NESTAIL_AUTH_SECRET`: required for token generation.
- `SCRAMJET_HOST`: optional, defaults to existing server default.
- `SCRAMJET_PORT`: optional, defaults to existing server default.

Suggested options:

- `--ttl <seconds>`: authorization grant TTL.
- `--origin <url>`: override the output URL origin.

## Deno Std Dependencies

Use a small set of Deno-native JSR packages:

- `@std/http/cookie`: cookie parsing and `Set-Cookie` construction.
- `@std/encoding/base64url`: JWT-compatible base64url encoding and decoding.
- `@std/cli/parse-args`: CLI argument parsing.

Do not add `@std/crypto` for HMAC. Deno's built-in Web Crypto API is sufficient.

Do not add `@std/uuid` for grant or session ids. `crypto.randomUUID()` is
sufficient.

## Non-Goals

- This feature does not authenticate users by identity.
- This feature does not authorize access to arbitrary remote origins.
- This feature does not make URL fragments visible to server middleware.
- This feature does not replace the existing route id model.
- This feature does not persist single-use grant state across restarts unless a
  persistent store is added later.
