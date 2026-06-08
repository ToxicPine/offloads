---
name: nestail-service-urls
description: "Use when the user asks to view, open, test, share, or find the URL for a running web service or dev server from this environment. Convert localhost dev-server URLs through Nestail using Bash `$HOSTNAME`: `http://$HOSTNAME/<port>/<rest-of-url>`. If Nestail auth is enabled, generate an auth grant with `nestail token` instead of giving a plain URL."
---

# Nestail Service URLs

You are the agent supervising this machine. When the user asks to view a service, translate local dev-server ports into URLs the user can open from their side.

Nestail exposes local web services through the system hostname. When a dev server is running on `localhost:<port>`, the unauthenticated URL shape is:

```text
http://<HOSTNAME>/<port>/<rest-of-url>
```

Get the hostname from Bash `$HOSTNAME`:

```bash
printf '%s\n' "$HOSTNAME"
```

If `$HOSTNAME` is empty, fall back to:

```bash
hostname
```

Examples:

```text
http://localhost:3000/        -> http://$HOSTNAME/3000/
http://127.0.0.1:5173/app     -> http://$HOSTNAME/5173/app
http://localhost:8000/a?x=1   -> http://$HOSTNAME/8000/a?x=1
```

Do not tell the user to open `localhost:<port>` unless they explicitly ask for the container-local URL. For user-facing links, replace the local origin with the Nestail URL shape.

## Auth

Nestail auth is enabled only when `NESTAIL_AUTH_SECRET` is set. When it is enabled, do not give the
plain URL above as a shareable link. Generate a route-bound authorization grant with `nestail token`:

```bash
nestail token "$PORT" "$TARGET_PATH" --origin "http://$HOSTNAME"
```

The command reads `NESTAIL_AUTH_SECRET` from the machine environment and prints a URL shaped like:

```text
http://<HOSTNAME>/<port>#<grant>/<target-path>
```

The grant is short-lived and one-time-use. The browser redeems it for an HTTP-only `nestail_auth`
cookie, then lands on the normal URL (`http://<HOSTNAME>/<port>/<target-path>`). Session cookies are
route-bound, so a cookie for `/3000` does not authorize `/3001`.

Do not print, copy, or ask for `NESTAIL_AUTH_SECRET`. Do not hand-build grant fragments. If auth is
enabled but `nestail token` is unavailable or cannot see the secret, say you cannot generate a
shareable authenticated Nestail link from this shell.

## Workflow

1. Identify the service port from the dev server output, config, or command.
2. Verify it responds locally when practical:

```bash
curl -fsS -I "http://localhost:$PORT/" >/dev/null
```

3. Read `$HOSTNAME` from Bash.
4. Preserve any path, query string, or hash from the original local URL as `$TARGET_PATH`; use `/` if there is no path.
5. Check whether auth is enabled without printing the secret:

```bash
[ -n "${NESTAIL_AUTH_SECRET:-}" ]
```

6. If `NESTAIL_AUTH_SECRET` is set, run `nestail token "$PORT" "$TARGET_PATH" --origin "http://$HOSTNAME"` and give the generated URL.
7. If `NESTAIL_AUTH_SECRET` is unset, give `http://$HOSTNAME/$PORT$TARGET_PATH`.

Nestail routes the first path segment as the target localhost port, so the Nestail URL has the port in the path, not after the hostname.
