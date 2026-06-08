export const SCRAMJET_HOST = Deno.env.get("SCRAMJET_HOST") ?? "localhost";
export const SCRAMJET_PORT = Number(Deno.env.get("SCRAMJET_PORT") ?? 4096);

export const INTERNAL_PREFIXES = [
  "__scramjet",
  "__scramjet-sw.js",
  "__baremux",
  "__route-proxy",
  "__transport",
  "__health",
];
