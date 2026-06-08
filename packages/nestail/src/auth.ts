import { decodeBase64Url, encodeBase64Url } from "@std/encoding/base64url";
import { z } from "@zod/zod";
import type { Result } from "./result.ts";
import { err, ok } from "./result.ts";

export const AUTH_COOKIE_NAME = "nestail_auth";
export const DEFAULT_GRANT_TTL_SECONDS = 20 * 60;
export const DEFAULT_SESSION_TTL_SECONDS = 3 * 24 * 60 * 60;

const GRANT_TYPE = "nestail-auth-grant";
const SESSION_TYPE = "nestail-auth-session";
const JWT_HEADER: JwtHeader = { alg: "HS256", typ: "JWT" };

const consumedGrantExpiresAtById = new Map<string, number>();
const encoder = new TextEncoder();
const decoder = new TextDecoder();

export type AuthError = {
  status: number;
  code: string;
  message: string;
};

type TokenPayload = Record<string, unknown>;

type JwtHeader = {
  alg: "HS256";
  typ: "JWT";
};

type GrantClaims = {
  typ: typeof GRANT_TYPE;
  route: string;
  jti: string;
  iat: number;
  exp: number;
};

type SessionClaims = {
  typ: typeof SESSION_TYPE;
  route: string;
  sid: string;
  iat: number;
  exp: number;
};

export type RedeemedSession = {
  token: string;
  maxAge: number;
};

const JwtHeaderSchema = z.object({
  alg: z.literal("HS256"),
  typ: z.literal("JWT"),
});

const TokenPayloadSchema = z.record(z.string(), z.unknown());

const GrantClaimsSchema = z.object({
  typ: z.literal(GRANT_TYPE),
  route: z.string().min(1),
  jti: z.string().min(1),
  iat: z.number().int(),
  exp: z.number().int(),
});

const SessionClaimsSchema = z.object({
  typ: z.literal(SESSION_TYPE),
  route: z.string().min(1),
  sid: z.string().min(1),
  iat: z.number().int(),
  exp: z.number().int(),
});

export function authSecret(): string | null {
  const value = Deno.env.get("NESTAIL_AUTH_SECRET")?.trim();
  return value ? value : null;
}

export async function createAuthorizationGrant(
  secret: string,
  route: string,
  ttlSeconds = DEFAULT_GRANT_TTL_SECONDS,
): Promise<string> {
  const now = unixSeconds();
  return signToken(
    secret,
    {
      typ: GRANT_TYPE,
      route,
      jti: crypto.randomUUID(),
      iat: now,
      exp: now + ttlSeconds,
    } satisfies GrantClaims,
  );
}

export async function redeemAuthorizationGrant(
  secret: string,
  route: string,
  grant: string,
): Promise<Result<RedeemedSession, AuthError>> {
  const payload = await verifyToken(secret, grant);
  if (!payload.ok) return payload;

  const claims = grantClaims(payload.value);
  if (!claims.ok) return claims;

  const now = unixSeconds();
  if (claims.value.exp <= now) {
    return authErr(401, "GRANT_EXPIRED", "Authorization grant expired.");
  }

  if (claims.value.route !== route) {
    return authErr(403, "GRANT_ROUTE_MISMATCH", "Authorization grant denied.");
  }

  pruneConsumedGrants(now);
  if (consumedGrantExpiresAtById.has(claims.value.jti)) {
    return authErr(401, "GRANT_CONSUMED", "Authorization grant already used.");
  }
  consumedGrantExpiresAtById.set(claims.value.jti, claims.value.exp);

  const session = await createSessionToken(secret, route);
  return ok({
    token: session.token,
    maxAge: session.expiresAt - now,
  });
}

export async function isSessionTokenValid(
  token: string,
  secret: string,
  route: string,
): Promise<boolean> {
  const payload = await verifyToken(secret, token);
  if (!payload.ok) return false;

  const claims = sessionClaims(payload.value);
  if (!claims.ok) return false;

  return claims.value.route === route && claims.value.exp > unixSeconds();
}

async function createSessionToken(
  secret: string,
  route: string,
): Promise<{ token: string; expiresAt: number }> {
  const now = unixSeconds();
  const expiresAt = now + DEFAULT_SESSION_TTL_SECONDS;
  const token = await signToken(
    secret,
    {
      typ: SESSION_TYPE,
      route,
      sid: crypto.randomUUID(),
      iat: now,
      exp: expiresAt,
    } satisfies SessionClaims,
  );

  return { token, expiresAt };
}

async function signToken(
  secret: string,
  payload: TokenPayload,
): Promise<string> {
  const header = encodeJson(JWT_HEADER);
  const body = encodeJson(payload);
  const signingInput = `${header}.${body}`;
  const signature = await hmacSign(secret, signingInput);
  return `${signingInput}.${encodeBase64Url(signature)}`;
}

async function verifyToken(
  secret: string,
  token: string,
): Promise<Result<TokenPayload, AuthError>> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  const [headerPart, payloadPart, signaturePart] = parts;
  const signingInput = `${headerPart}.${payloadPart}`;
  let signature: Uint8Array;
  try {
    signature = decodeBase64Url(signaturePart);
  } catch {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  if (!(await hmacVerify(secret, signingInput, signature))) {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  let header: unknown;
  let payload: unknown;
  try {
    header = decodeJson(headerPart);
    payload = decodeJson(payloadPart);
  } catch {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  if (!JwtHeaderSchema.safeParse(header).success) {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  const parsedPayload = TokenPayloadSchema.safeParse(payload);
  if (!parsedPayload.success) {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  return ok(parsedPayload.data);
}

async function hmacSign(secret: string, value: string): Promise<Uint8Array> {
  const key = await hmacKey(secret, ["sign"]);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );
  return new Uint8Array(signature);
}

async function hmacVerify(
  secret: string,
  value: string,
  signature: Uint8Array,
): Promise<boolean> {
  const key = await hmacKey(secret, ["verify"]);
  return crypto.subtle.verify(
    "HMAC",
    key,
    arrayBufferFromBytes(signature),
    encoder.encode(value),
  );
}

function hmacKey(
  secret: string,
  usages: KeyUsage[],
): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages,
  );
}

function grantClaims(
  payload: TokenPayload,
): Result<GrantClaims, AuthError> {
  const claims = GrantClaimsSchema.safeParse(payload);
  if (!claims.success) {
    return authErr(401, "GRANT_INVALID", "Authorization grant invalid.");
  }

  return ok(claims.data);
}

function sessionClaims(
  payload: TokenPayload,
): Result<SessionClaims, AuthError> {
  const claims = SessionClaimsSchema.safeParse(payload);
  if (!claims.success) {
    return authErr(401, "TOKEN_INVALID", "Auth token invalid.");
  }

  return ok(claims.data);
}

function encodeJson(value: unknown): string {
  return encodeBase64Url(JSON.stringify(value));
}

function decodeJson(value: string): unknown {
  return JSON.parse(decoder.decode(decodeBase64Url(value)));
}

function pruneConsumedGrants(now: number): void {
  for (const [id, expiresAt] of consumedGrantExpiresAtById) {
    if (expiresAt <= now) consumedGrantExpiresAtById.delete(id);
  }
}

function authErr(
  status: number,
  code: string,
  message: string,
): Result<never, AuthError> {
  return err({ status, code, message });
}

function arrayBufferFromBytes(bytes: Uint8Array): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(buffer).set(bytes);
  return buffer;
}

function unixSeconds(): number {
  return Math.floor(Date.now() / 1000);
}
