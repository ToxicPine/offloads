import { getCookies, setCookie } from "@std/http/cookie";
import { z } from "@zod/zod";
import {
  AUTH_COOKIE_NAME,
  type AuthError,
  isSessionTokenValid,
  redeemAuthorizationGrant,
  type RedeemedSession,
} from "./auth.ts";
import { parsePublicRouteId } from "./routes.ts";

const AuthConsumeBodySchema = z.object({
  route: z.string(),
  grant: z.string(),
});

export type AuthMiddleware = {
  consume: (request: Request) => Promise<Response>;
  guardShell: (request: Request, route: string) => Promise<Response | null>;
  guardTransport: (
    request: Request,
    route: string | null,
  ) => Promise<Response | null>;
};

export function createAuthMiddleware(
  secret: string | null,
): AuthMiddleware {
  return {
    consume: (request) => handleAuthConsume(request, secret),
    guardShell: (request, route) => requireShellAuth(request, secret, route),
    guardTransport: (request, route) =>
      requireTransportAuth(request, secret, route),
  };
}

async function handleAuthConsume(
  request: Request,
  secret: string | null,
): Promise<Response> {
  if (!secret) return authDisabledResponse();
  if (request.method !== "POST") {
    return authJsonError({
      status: 405,
      code: "METHOD_NOT_ALLOWED",
      message: "Method not allowed.",
    });
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return invalidAuthRequest();
  }

  const body = AuthConsumeBodySchema.safeParse(payload);
  if (!body.success) {
    return invalidAuthRequest();
  }

  const route = parsePublicRouteId(body.data.route);
  if (!route.ok) {
    return authJsonError({
      status: route.error.status,
      code: "INVALID_ROUTE",
      message: route.error.message,
    });
  }

  const redeemed = await redeemAuthorizationGrant(
    secret,
    route.value,
    body.data.grant,
  );
  if (!redeemed.ok) return authJsonError(redeemed.error);

  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
  });
  setAuthCookie(headers, redeemed.value, isSecureRequest(request));

  return new Response(JSON.stringify({ ok: true }), { headers });
}

async function requireShellAuth(
  request: Request,
  secret: string | null,
  route: string,
): Promise<Response | null> {
  if (!secret) return null;
  if (await isRequestAuthenticated(request, secret, route)) return null;
  return authBootstrapResponse(route);
}

async function requireTransportAuth(
  request: Request,
  secret: string | null,
  rawRoute: string | null,
): Promise<Response | null> {
  if (!secret || !rawRoute) return null;

  const route = parsePublicRouteId(rawRoute);
  if (!route.ok) return null;

  if (await isRequestAuthenticated(request, secret, route.value)) return null;
  return unauthenticatedTransportResponse();
}

async function isRequestAuthenticated(
  request: Request,
  secret: string,
  route: string,
): Promise<boolean> {
  const token = getCookies(request.headers)[AUTH_COOKIE_NAME];
  if (!token) return false;
  return isSessionTokenValid(token, secret, route);
}

function setAuthCookie(
  headers: Headers,
  session: RedeemedSession,
  secure: boolean,
): void {
  setCookie(headers, {
    name: AUTH_COOKIE_NAME,
    value: session.token,
    httpOnly: true,
    sameSite: "Lax",
    path: "/",
    secure,
    maxAge: session.maxAge,
  });
}

function isSecureRequest(request: Request): boolean {
  if (new URL(request.url).protocol === "https:") return true;
  if (Deno.env.get("NESTAIL_TRUST_PROXY_HEADERS") === "0") return false;

  return request.headers.get("x-forwarded-proto") === "https" ||
    request.headers.get("x-forwarded-ssl") === "on";
}

function authBootstrapResponse(route: string): Response {
  const body = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Authentication required</title>
<script type="module">
const route = ${JSON.stringify(route)};
const fragment = location.hash.startsWith("#") ? location.hash.slice(1) : "";
const slash = fragment.indexOf("/");
const grant = slash === -1 ? fragment : fragment.slice(0, slash);
const targetPath = slash === -1 ? "/" : "/" + fragment.slice(slash + 1);

history.replaceState(history.state, "", location.pathname + location.search);

if (!grant) {
  renderError("Authentication required.");
} else {
  try {
    const response = await fetch("/__auth/consume", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ route, grant })
    });

    if (!response.ok) {
      let message = "Authentication failed.";
      try {
        message = (await response.json()).message || message;
      } catch {
        // Keep the generic message.
      }
      renderError(message);
    } else {
      location.replace(postAuthUrl(route, targetPath));
    }
  } catch {
    renderError("Authentication failed.");
  }
}

function postAuthUrl(route, targetPath) {
  const encodedHashIndex = targetPath.search(/%23/i);
  if (encodedHashIndex === -1) {
    return "/" + route + targetPath;
  }

  return "/" + route +
    targetPath.slice(0, encodedHashIndex) +
    "#" +
    targetPath.slice(encodedHashIndex + 3);
}

function renderError(message) {
  document.body.textContent = "";
  const heading = document.createElement("h1");
  heading.textContent = message;
  document.body.appendChild(heading);
}
</script>
<body></body>`;

  return new Response(body, {
    status: 401,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function unauthenticatedTransportResponse(): Response {
  return new Response(
    JSON.stringify({
      code: "UNAUTHENTICATED",
      id: "unauthenticated",
      message: "Authentication required.",
    }),
    {
      status: 401,
      headers: { "content-type": "application/json; charset=utf-8" },
    },
  );
}

function invalidAuthRequest(): Response {
  return authJsonError({
    status: 400,
    code: "INVALID_BODY",
    message: "Invalid auth request.",
  });
}

function authDisabledResponse(): Response {
  return authJsonError({
    status: 404,
    code: "AUTH_DISABLED",
    message: "Auth is not enabled.",
  });
}

function authJsonError(error: AuthError): Response {
  return new Response(
    JSON.stringify({ code: error.code, message: error.message }),
    {
      status: error.status,
      headers: { "content-type": "application/json; charset=utf-8" },
    },
  );
}
