import { join, normalize, relative } from "node:path";
import { errorResponse } from "./errors.ts";

export async function serveStatic(
  pathname: string,
  prefix: string,
  root: string,
): Promise<Response> {
  let relativePath: string;
  try {
    relativePath = decodeURIComponent(pathname.slice(prefix.length));
  } catch {
    return errorResponse("asset-missing", 404, "Asset not found.");
  }

  const filePath = normalize(join(root, relativePath));
  const staticRelativePath = relative(root, filePath);

  if (
    staticRelativePath.startsWith("..") || staticRelativePath.startsWith("/")
  ) {
    return errorResponse("asset-missing", 404, "Asset not found.");
  }

  try {
    const file = await Deno.open(filePath, { read: true });
    return new Response(file.readable, {
      headers: { "content-type": contentType(filePath) },
    });
  } catch {
    return errorResponse("asset-missing", 404, "Asset not found.");
  }
}

export function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export function javascript(source: string): Response {
  return new Response(source, {
    headers: { "content-type": "text/javascript; charset=utf-8" },
  });
}

function contentType(filePath: string): string {
  if (filePath.endsWith(".js") || filePath.endsWith(".mjs")) {
    return "text/javascript; charset=utf-8";
  }
  if (filePath.endsWith(".wasm")) return "application/wasm";
  if (filePath.endsWith(".map") || filePath.endsWith(".json")) {
    return "application/json; charset=utf-8";
  }
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  return "application/octet-stream";
}
