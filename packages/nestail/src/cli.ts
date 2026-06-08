import { parseArgs } from "@std/cli/parse-args";
import {
  authSecret,
  createAuthorizationGrant,
  DEFAULT_GRANT_TTL_SECONDS,
} from "./auth.ts";
import { SCRAMJET_HOST, SCRAMJET_PORT } from "./constants.ts";
import { parsePublicRouteId } from "./routes.ts";

if (import.meta.main) {
  await main(Deno.args);
}

async function main(args: string[]): Promise<void> {
  const [command = "serve", ...rest] = args;

  switch (command) {
    case "serve":
      await serve();
      return;
    case "token":
      await printTokenUrl(rest);
      return;
    case "help":
    case "--help":
    case "-h":
      printUsage();
      return;
    default:
      console.error(`Unknown command: ${command}`);
      printUsage();
      Deno.exit(2);
  }
}

async function serve(): Promise<void> {
  const { startServer } = await import("./server.ts");
  startServer();
}

async function printTokenUrl(args: string[]): Promise<void> {
  const parsed = parseArgs(args, {
    string: ["ttl", "origin"],
    boolean: ["help"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    printTokenUsage();
    return;
  }

  const routeId = String(parsed._[0] ?? "");
  const route = parsePublicRouteId(routeId);
  if (!route.ok) {
    console.error(route.error.message);
    Deno.exit(2);
  }

  const secret = authSecret();
  if (!secret) {
    console.error("NESTAIL_AUTH_SECRET is required to generate auth tokens.");
    Deno.exit(2);
  }

  const ttl = parseTtl(parsed.ttl);
  const targetPath = normalizeTargetPath(String(parsed._[1] ?? "/"));
  const origin = parseOrigin(parsed.origin);
  const grant = await createAuthorizationGrant(secret, route.value, ttl);

  const base = new URL(`/${route.value}`, origin);
  console.log(`${base.href}#${grant}${targetPathForFragment(targetPath)}`);
}

function parseTtl(value: string | undefined): number {
  if (value === undefined) return DEFAULT_GRANT_TTL_SECONDS;

  if (!/^[1-9]\d*$/.test(value)) {
    console.error("--ttl must be a positive integer number of seconds.");
    Deno.exit(2);
  }

  return Number(value);
}

function parseOrigin(value: string | undefined): string {
  if (value !== undefined) {
    try {
      const origin = new URL(value);
      return origin.origin;
    } catch {
      console.error("--origin must be an absolute URL.");
      Deno.exit(2);
    }
  }

  return `http://${hostForUrl(SCRAMJET_HOST)}:${SCRAMJET_PORT}`;
}

function hostForUrl(host: string): string {
  if (host.includes(":") && !host.startsWith("[") && !host.endsWith("]")) {
    return `[${host}]`;
  }
  return host;
}

function normalizeTargetPath(value: string): string {
  return value.startsWith("/") ? value : `/${value}`;
}

function targetPathForFragment(path: string): string {
  return encodeURI(path).replaceAll("#", "%23");
}

function printUsage(): void {
  console.error(`Usage:
  nestail serve
  nestail token <port> [target-path] [--ttl seconds] [--origin url]`);
}

function printTokenUsage(): void {
  console.error(`Usage:
  nestail token <port> [target-path] [--ttl seconds] [--origin url]

Example:
  NESTAIL_AUTH_SECRET=... nestail token 3000 /dashboard`);
}
