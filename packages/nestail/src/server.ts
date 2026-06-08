import { baremuxPath } from "npm:@mercuryworkshop/bare-mux@2.1.9/node";
import { scramjetPath } from "npm:@mercuryworkshop/scramjet@1.1.0/path";
import { javascript, json, serveStatic } from "./assets.ts";
import { EnvValidationError, type NestailEnv, readEnv } from "./env.ts";
import { renderError } from "./errors.ts";
import {
  createPortRouteTargetGetter,
  resolvePublicRoute,
  type RouteTargetGetter,
} from "./routes.ts";
import { type AuthMiddleware, createAuthMiddleware } from "./middleware.ts";
import { scramjetServiceWorkerScript, shellResponse } from "./scramjet.ts";
import {
  handleTransport,
  localTransportModule,
  transportRouteIdFromRequest,
} from "./transport.ts";

const SCRAMJET_ASSET_PREFIX = "/__scramjet/";
const BAREMUX_ASSET_PREFIX = "/__baremux/";
const TRANSPORT_PREFIX = "/__transport/";

type ServerContext = {
  auth: AuthMiddleware;
  getRouteTarget: RouteTargetGetter;
};

export function startServer(env: NestailEnv): Deno.HttpServer {
  const context: ServerContext = {
    auth: createAuthMiddleware(env),
    getRouteTarget: createPortRouteTargetGetter(),
  };

  return Deno.serve(
    { hostname: env.scramjetHost, port: env.scramjetPort },
    (request) => handleRequest(request, context),
  );
}

if (import.meta.main) {
  try {
    startServer(readEnv());
  } catch (error) {
    if (error instanceof EnvValidationError) {
      console.error(error.message);
      Deno.exit(1);
    }
    throw error;
  }
}

async function handleRequest(
  request: Request,
  context: ServerContext,
): Promise<Response> {
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
    return context.auth.consume(request);
  }

  if (url.pathname.startsWith(SCRAMJET_ASSET_PREFIX)) {
    return serveStatic(url.pathname, SCRAMJET_ASSET_PREFIX, scramjetPath);
  }

  if (url.pathname.startsWith(BAREMUX_ASSET_PREFIX)) {
    return serveStatic(url.pathname, BAREMUX_ASSET_PREFIX, baremuxPath);
  }

  if (url.pathname.startsWith(TRANSPORT_PREFIX)) {
    const authResponse = await context.auth.guardTransport(
      request,
      transportRouteIdFromRequest(request),
    );
    if (authResponse) return authResponse;

    return handleTransport(request, context.getRouteTarget);
  }

  const route = await resolvePublicRoute(url, context.getRouteTarget);
  if (!route.ok) {
    return renderError(route.error);
  }

  const authResponse = await context.auth.guardShell(request, route.value.id);
  if (authResponse) return authResponse;

  return shellResponse(route.value.id, route.value.targetOrigin);
}
