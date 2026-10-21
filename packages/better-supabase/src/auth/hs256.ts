import type { JWTClaims, UserClaims } from "@supabase/server";

import { base64ToText, fromBase64 } from "../core/base64.ts";

export type Hs256Result =
  | { readonly ok: true; readonly claims: JWTClaims; readonly user: UserClaims }
  | { readonly ok: false; readonly code: string; readonly message: string };

export interface Hs256Options {
  readonly audience?: string | readonly string[];
  readonly issuer?: string | readonly string[];
  /** Epoch seconds. */
  readonly now: number;
}

let encoderInstance: InstanceType<typeof TextEncoder> | undefined;

// Created on first use: not every runtime has the global at import time.
const encoder = {
  encode: (text: string): Uint8Array<ArrayBuffer> =>
    (encoderInstance ??= new TextEncoder()).encode(text),
};

/** The most HMAC keys kept at once; the oldest goes first. */
const KEYS_SIZE = 64;

// Typed from `crypto.subtle`, because `CryptoKey` is a value only under @types/node without the DOM lib.
type ImportedKey = ReturnType<typeof crypto.subtle.importKey>;

const keys = new Map<string, ImportedKey>();

/** Forgets every imported key. For tests and benchmarks. */
export function clearHs256Keys(): void {
  keys.clear();
}

function keyFor(secret: string): ImportedKey {
  let key = keys.get(secret);

  if (!key) {
    key = crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    keys.set(secret, key);

    if (keys.size > KEYS_SIZE) {
      const oldest = keys.keys().next();

      if (!oldest.done) {
        keys.delete(oldest.value);
      }
    }
  }

  return key;
}

function parseJson(part: string): Record<string, unknown> | undefined {
  try {
    const parsed: unknown = JSON.parse(base64ToText(part));

    // SAFETY: parsed is a non-null, non-array object; callers check each field they read.
    return typeof parsed === "object" &&
      parsed !== null &&
      !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Whether the token is HS256 without a `kid`, the shape Supabase Lite (and
 * legacy shared-secret projects) issue.
 */
export function isSharedSecretToken(token: string): boolean {
  const part = token.split(".", 1)[0];
  const header = part ? parseJson(part) : undefined;

  return header?.["alg"] === "HS256" && header["kid"] === undefined;
}

function fail(message: string): Hs256Result {
  return { ok: false, code: "INVALID_JWT", message };
}

function matches(
  claim: unknown,
  expected: string | readonly string[],
): boolean {
  const wanted = typeof expected === "string" ? [expected] : expected;
  const given = Array.isArray(claim) ? claim : [claim];

  return given.some(
    (value) => typeof value === "string" && wanted.includes(value),
  );
}

/**
 * Verifies an HS256 user token against a shared secret with WebCrypto: the
 * signature, `exp`, `nbf`, and `aud` and `iss` when they are given.
 */
export async function verifyHs256(
  token: string,
  secret: string,
  options: Hs256Options,
): Promise<Hs256Result> {
  const parts = token.split(".");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  if (
    parts.length !== 3 ||
    !encodedHeader ||
    !encodedPayload ||
    encodedSignature === undefined
  ) {
    return fail("The token is not a JWT");
  }

  const header = parseJson(encodedHeader);

  if (header?.["alg"] !== "HS256") {
    return fail("The token is not signed with HS256");
  }

  let signature: Uint8Array<ArrayBuffer>;

  try {
    signature = fromBase64(encodedSignature);
  } catch {
    return fail("The token signature is not base64url");
  }

  const valid = await crypto.subtle.verify(
    "HMAC",
    await keyFor(secret),
    signature,
    encoder.encode(`${encodedHeader}.${encodedPayload}`),
  );

  if (!valid) {
    return fail("The token signature does not match the JWT secret");
  }

  const payload = parseJson(encodedPayload);

  if (!payload) {
    return fail("The token payload is not a JSON object");
  }

  const { exp, nbf, sub } = payload;

  if (typeof exp === "number" && exp <= options.now) {
    return fail("The token has expired");
  }

  if (typeof nbf === "number" && nbf > options.now) {
    return fail("The token is not valid yet");
  }

  if (
    options.audience !== undefined &&
    !matches(payload["aud"], options.audience)
  ) {
    return fail("The token audience does not match");
  }

  if (
    options.issuer !== undefined &&
    !matches(payload["iss"], options.issuer)
  ) {
    return fail("The token issuer does not match");
  }

  if (typeof sub !== "string") {
    return fail("The token has no sub claim, so it identifies no user");
  }

  // SAFETY: the payload is an object with a string `sub`, the only required JWTClaims field.
  const claims = payload as JWTClaims;

  return {
    ok: true,
    claims,
    user: {
      id: sub,
      ...(typeof claims.role === "string" ? { role: claims.role } : {}),
      ...(typeof claims.email === "string" ? { email: claims.email } : {}),
      ...(claims.app_metadata ? { appMetadata: claims.app_metadata } : {}),
      ...(claims.user_metadata ? { userMetadata: claims.user_metadata } : {}),
    },
  };
}
