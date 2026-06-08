import { parseArgs } from "@std/cli/parse-args";
import { createAuthorizationGrant, DEFAULT_GRANT_TTL_SECONDS } from "./auth.ts";
import { EnvValidationError, type NestailEnv, readEnv } from "./env.ts";
import { parsePublicRouteId } from "./routes.ts";

if (import.meta.main) {
  try {
    await main(Deno.args, readEnv());
  } catch (error) {
    if (error instanceof EnvValidationError) {
      console.error(error.message);
      Deno.exit(1);
    }
    throw error;
  }
}

async function main(args: string[], env: NestailEnv): Promise<void> {
  const [command = "serve", ...rest] = args;

  switch (command) {
    case "serve":
      await serve(env);
      return;
    case "token":
      await printTokenUrl(rest, env);
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

async function serve(env: NestailEnv): Promise<void> {
  const { startServer } = await import("./server.ts");
  startServer(env);
}

async function printTokenUrl(args: string[], env: NestailEnv): Promise<void> {
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

  const secret = env.authSecret;
  if (!secret) {
    console.error("NESTAIL_AUTH_SECRET is required to generate auth tokens.");
    Deno.exit(2);
  }

  const ttl = parseTtl(parsed.ttl);
  const targetPath = normalizeTargetPath(String(parsed._[1] ?? "/"));
  const origin = parseOrigin(parsed.origin, env);
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

function parseOrigin(value: string | undefined, env: NestailEnv): string {
  if (value !== undefined) {
    try {
      const origin = new URL(value);
      return origin.origin;
    } catch {
      console.error("--origin must be an absolute URL.");
      Deno.exit(2);
    }
  }

  return `http://${hostForUrl(env.scramjetHost)}:${env.scramjetPort}`;
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
