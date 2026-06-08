import type { RouteError } from "./errors.ts";
import { z } from "@zod/zod";
import {
  canTransportTo,
  parsePublicRouteId,
  type RouteTargetGetter,
} from "./routes.ts";

const BareHeadersSchema = z.record(
  z.string(),
  z.union([z.string(), z.array(z.string())]),
);

export async function handleTransport(
  request: Request,
  getRouteTarget: RouteTargetGetter,
): Promise<Response> {
  const routeId = transportRouteIdFromRequest(request);
  if (!routeId) {
    return bareError(400, "MISSING_ROUTE", "Missing transport route.");
  }

  const validRouteId = parsePublicRouteId(routeId);
  if (!validRouteId.ok) {
    return bareRouteError(validRouteId.error);
  }

  const target = await getRouteTarget(validRouteId.value);
  if (!target.ok) {
    return bareRouteError(target.error);
  }

  if (request.headers.get("upgrade")?.toLowerCase() === "websocket") {
    return handleTransportWebSocket(request, target.value);
  }

  const remoteValue = request.headers.get("x-bare-url");
  if (!remoteValue) {
    return bareError(400, "MISSING_REMOTE", "Missing transport target.");
  }

  let remote: URL;
  try {
    remote = new URL(remoteValue);
  } catch {
    return bareError(400, "INVALID_REMOTE", "Invalid transport target.");
  }

  if (!canTransportTo(remote, target.value)) {
    return bareError(403, "DENIED_REMOTE", "Transport target denied.");
  }

  let upstreamHeaders: Headers;
  try {
    upstreamHeaders = requestHeadersFromBare(
      request.headers.get("x-bare-headers"),
    );
  } catch {
    return bareError(400, "INVALID_HEADERS", "Invalid transport headers.");
  }

  try {
    const upstream = await fetch(remote, {
      method: request.method,
      headers: upstreamHeaders,
      body: request.body,
      redirect: "manual",
    });

    const headers = new Headers({
      "x-bare-status": String(upstream.status),
      "x-bare-status-text": upstream.statusText,
      "x-bare-headers": JSON.stringify(headersObject(upstream.headers)),
    });

    return new Response(upstream.body, { status: 200, headers });
  } catch (error) {
    console.error("Transport request failed:", remote.href, error);
    return bareError(502, "UPSTREAM_FAILED", "Transport request failed.");
  }
}

function handleTransportWebSocket(request: Request, target: URL): Response {
  const { socket, response } = Deno.upgradeWebSocket(request);
  let upstream: WebSocket | null = null;

  socket.addEventListener("message", (event) => {
    if (upstream) {
      upstream.send(event.data);
      return;
    }

    let message: { type?: string; remote?: string; protocols?: string[] };
    try {
      message = JSON.parse(String(event.data));
    } catch {
      socket.close(1002, "Invalid transport message.");
      return;
    }

    if (message.type !== "connect" || !message.remote) {
      socket.close(1002, "Invalid transport connect.");
      return;
    }

    let remote: URL;
    try {
      remote = new URL(message.remote);
    } catch {
      socket.close(1008, "Invalid transport target.");
      return;
    }

    if (!canTransportTo(remote, target)) {
      socket.close(1008, "Transport target denied.");
      return;
    }

    upstream = new WebSocket(remote, message.protocols ?? []);
    upstream.binaryType = "arraybuffer";
    upstream.addEventListener("open", () => {
      socket.send(
        JSON.stringify({ type: "open", protocol: upstream?.protocol ?? "" }),
      );
    });
    upstream.addEventListener("message", (upstreamEvent) => {
      socket.send(upstreamEvent.data);
    });
    upstream.addEventListener("close", (upstreamEvent) => {
      socket.close(upstreamEvent.code, upstreamEvent.reason);
    });
    upstream.addEventListener("error", () => {
      socket.close(1011, "Transport websocket failed.");
    });
  });

  socket.addEventListener("close", (event) => {
    upstream?.close(event.code, event.reason);
  });

  return response;
}

export function transportRouteIdFromRequest(request: Request): string | null {
  const url = new URL(request.url);
  const [, prefix, id = ""] = url.pathname.split("/");
  if (prefix !== "__transport") return null;
  return id || null;
}

function requestHeadersFromBare(value: string | null): Headers {
  const headers = new Headers();
  if (!value) {
    return headers;
  }

  const parsed = parseBareHeaders(value);
  for (const [name, raw] of Object.entries(parsed)) {
    const lower = name.toLowerCase();
    if (
      [
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "transfer-encoding",
        "upgrade",
      ]
        .includes(lower)
    ) {
      continue;
    }

    const values = Array.isArray(raw) ? raw : [raw];
    for (const headerValue of values) {
      headers.append(name, headerValue);
    }
  }

  return headers;
}

function parseBareHeaders(value: string): Record<string, string | string[]> {
  const parsed: unknown = JSON.parse(value);
  return BareHeadersSchema.parse(parsed);
}

function headersObject(headers: Headers): Record<string, string> {
  const output: Record<string, string> = {};
  for (const [key, value] of headers) {
    output[key] = value;
  }
  return output;
}

function bareError(status: number, code: string, message: string): Response {
  return new Response(
    JSON.stringify({ code, id: code.toLowerCase(), message }),
    {
      status,
      headers: { "content-type": "application/json; charset=utf-8" },
    },
  );
}

function bareRouteError(error: RouteError): Response {
  switch (error.category) {
    case "bad-route":
      return bareError(error.status, "INVALID_ROUTE", error.message);
    case "config-error":
      return bareError(error.status, "ROUTE_CONFIG_INVALID", error.message);
    case "asset-missing":
      return bareError(error.status, "ROUTE_ERROR", error.message);
  }
}

export function localTransportModule(): string {
  return `
export default class LocalTransport {
  constructor(server) {
    this.base = new URL("v3/", server);
    this.ready = true;
  }

  async init() {
    this.ready = true;
  }

  meta() {
    return {};
  }

  async request(remote, method, body, headers, signal) {
    const response = await fetch(this.base, {
      method,
      body: body === undefined ? null : body,
      signal,
      headers: this.createBareHeaders(remote, headers)
    });

    if (!response.ok) {
      throw new Error((await response.json()).message || "Transport request failed.");
    }

    const bareHeaders = this.readBareHeaders(response.headers);
    return {
      body: response.body,
      headers: bareHeaders.headers,
      status: bareHeaders.status,
      statusText: bareHeaders.statusText
    };
  }

  connect(url, protocols, requestHeaders, onopen, onmessage, onclose, onerror) {
    const wsUrl = new URL(this.base);
    wsUrl.protocol = wsUrl.protocol === "https:" ? "wss:" : "ws:";
    const socket = new WebSocket(wsUrl);
    socket.binaryType = "arraybuffer";

    const firstMessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        onerror("Transport websocket failed.");
        socket.close();
        return;
      }

      if (message.type !== "open") {
        onerror("Transport websocket failed.");
        return;
      }
      onopen(message.protocol || "");
      socket.removeEventListener("message", firstMessage);
      socket.addEventListener("message", (messageEvent) => onmessage(messageEvent.data));
    };

    socket.addEventListener("message", firstMessage);
    socket.addEventListener("close", (event) => onclose(event.code, event.reason));
    socket.addEventListener("error", () => onerror("Transport websocket failed."));
    socket.addEventListener("open", () => {
      socket.send(JSON.stringify({
        type: "connect",
        remote: url.toString(),
        protocols,
        headers: requestHeaders
      }));
    }, { once: true });

    return [
      (data) => socket.send(data),
      (code, reason) => socket.close(code, reason)
    ];
  }

  createBareHeaders(remote, headers) {
    return new Headers({
      "x-bare-url": remote.toString(),
      "x-bare-headers": JSON.stringify(headers)
    });
  }

  readBareHeaders(headers) {
    return {
      status: Number(headers.get("x-bare-status") || "200"),
      statusText: headers.get("x-bare-status-text") || "",
      headers: JSON.parse(headers.get("x-bare-headers") || "{}")
    };
  }
}
`;
}
