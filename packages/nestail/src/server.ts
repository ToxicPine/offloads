import { baremuxPath } from "npm:@mercuryworkshop/bare-mux@2.1.9/node";
import { scramjetPath } from "npm:@mercuryworkshop/scramjet@1.1.0/path";
import { javascript, json, serveStatic } from "./assets.ts";
import { authSecret } from "./auth.ts";
import { createAuthMiddleware } from "./middleware.ts";
import { SCRAMJET_HOST, SCRAMJET_PORT } from "./constants.ts";
import { renderError } from "./errors.ts";
import { createPortRouteTargetGetter, resolvePublicRoute } from "./routes.ts";
import { scramjetServiceWorkerScript, shellResponse } from "./scramjet.ts";
import {
  handleTransport,
  localTransportModule,
  transportRouteIdFromRequest,
} from "./transport.ts";

const SCRAMJET_ASSET_PREFIX = "/__scramjet/";
const BAREMUX_ASSET_PREFIX = "/__baremux/";
const TRANSPORT_PREFIX = "/__transport/";

if (
  !Number.isInteger(SCRAMJET_PORT) || SCRAMJET_PORT < 1 || SCRAMJET_PORT > 65535
) {
  console.error("SCRAMJET_PORT must be an integer from 1 to 65535.");
  Deno.exit(1);
}

const getRouteTarget = createPortRouteTargetGetter();
const auth = createAuthMiddleware(authSecret());

export function startServer(): Deno.HttpServer {
  return Deno.serve(
    { hostname: SCRAMJET_HOST, port: SCRAMJET_PORT },
    handleRequest,
  );
}

if (import.meta.main) {
  startServer();
}

async function handleRequest(request: Request): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/__health") {
    return json({ ok: true });
  }

  if (url.pathname === "/__scramjet-sw.js") {
    return javascript(scramjetServiceWorkerScript());
  }

  if (url.pathname === "/__route-proxy/transport.js") {
    return javascript(localTransportModule());
  }

  if (url.pathname === "/__auth/consume") {
    return auth.consume(request);
  }

  if (url.pathname.startsWith(SCRAMJET_ASSET_PREFIX)) {
    return serveStatic(url.pathname, SCRAMJET_ASSET_PREFIX, scramjetPath);
  }

  if (url.pathname.startsWith(BAREMUX_ASSET_PREFIX)) {
    return serveStatic(url.pathname, BAREMUX_ASSET_PREFIX, baremuxPath);
  }

  if (url.pathname.startsWith(TRANSPORT_PREFIX)) {
    const authResponse = await auth.guardTransport(
      request,
      transportRouteIdFromRequest(request),
    );
    if (authResponse) return authResponse;

    return handleTransport(request, getRouteTarget);
  }

  const route = await resolvePublicRoute(url, getRouteTarget);
  if (!route.ok) {
    return renderError(route.error);
  }

  const authResponse = await auth.guardShell(request, route.value.id);
  if (authResponse) return authResponse;

  return shellResponse(route.value.id, route.value.targetOrigin);
}
