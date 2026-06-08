import { INTERNAL_PREFIXES } from "./constants.ts";
import { err, ok, type Result } from "./result.ts";
import type { RouteError } from "./errors.ts";

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

export type RouteId = string;

export type PublicRoute = {
  id: RouteId;
  targetOrigin: URL;
};

export type RouteTargetGetter = (
  id: RouteId,
) => Promise<Result<URL, RouteError>>;

export function createPortRouteTargetGetter(): RouteTargetGetter {
  return async (id) => {
    const port = parsePortId(id);
    if (!port.ok) return port;

    return ok(new URL(`http://localhost:${port.value}`));
  };
}

export function routeIdFromUrl(url: URL): Result<RouteId, RouteError> {
  const [id = ""] = url.pathname.slice(1).split("/");

  if (!id) {
    return err({
      category: "bad-route",
      status: 404,
      message: "Route id required.",
    });
  }

  return parsePublicRouteId(id);
}

export async function resolvePublicRoute(
  url: URL,
  getRouteTarget: RouteTargetGetter,
): Promise<Result<PublicRoute, RouteError>> {
  const id = routeIdFromUrl(url);
  if (!id.ok) return id;

  const targetOrigin = await getRouteTarget(id.value);
  if (!targetOrigin.ok) return targetOrigin;

  return ok({ id: id.value, targetOrigin: targetOrigin.value });
}

export function canTransportTo(remote: URL, target: URL): boolean {
  if (!["http:", "https:", "ws:", "wss:"].includes(remote.protocol)) {
    return false;
  }

  if (!isLocalHost(remote.hostname)) {
    return false;
  }

  return equivalentOrigin(remote, target);
}

export function parsePublicRouteId(id: string): Result<RouteId, RouteError> {
  if (INTERNAL_PREFIXES.includes(id)) {
    return err({
      category: "bad-route",
      status: 404,
      message: "Internal route.",
    });
  }

  const port = parsePortId(id);
  if (!port.ok) {
    return err({
      category: "bad-route",
      status: 400,
      message: "Route id must be a port from 1 to 65535.",
    });
  }

  return ok(id);
}

function parsePortId(id: string): Result<number, RouteError> {
  if (!/^[1-9]\d*$/.test(id)) {
    return err({
      category: "bad-route",
      status: 400,
      message: "Route id must be a port from 1 to 65535.",
    });
  }

  const port = Number(id);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    return err({
      category: "bad-route",
      status: 400,
      message: "Route id must be a port from 1 to 65535.",
    });
  }

  return ok(port);
}

function equivalentOrigin(remote: URL, target: URL): boolean {
  const remoteProtocol = remote.protocol === "ws:"
    ? "http:"
    : remote.protocol === "wss:"
    ? "https:"
    : remote.protocol;
  return remoteProtocol === target.protocol &&
    remote.hostname === target.hostname &&
    remote.port === target.port;
}

function isLocalHost(host: string): boolean {
  return LOCAL_HOSTS.has(host.toLowerCase());
}
