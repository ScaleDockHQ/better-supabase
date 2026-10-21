/**
 * OAuth helpers for any provider: PKCE, sealed cookies and a session shape,
 * on WebCrypto only. `better-supabase/create/supabase` builds the Supabase
 * flow on them; another provider, such as a deploy target, can reuse them.
 */

/** The HKDF info `seal` and `unseal` use when none is given; cookies sealed with it keep opening. */
export const DEFAULT_SEAL_INFO = "better-supabase create session";

/** An access token, an optional refresh token and when the access token expires. */
export interface OAuthSession {
  readonly accessToken: string;
  readonly refreshToken?: string | undefined;
  /** Epoch milliseconds. */
  readonly expiresAt: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isOAuthSession(value: unknown): value is OAuthSession {
  return (
    isRecord(value) &&
    typeof value["accessToken"] === "string" &&
    (value["refreshToken"] === undefined ||
      typeof value["refreshToken"] === "string") &&
    typeof value["expiresAt"] === "number"
  );
}

/** What a flow cookie holds between the redirect and the callback. */
export interface OAuthFlow {
  readonly state: string;
  readonly verifier: string;
  readonly returnTo: string;
}

export function isFlow(value: unknown): value is OAuthFlow {
  return (
    isRecord(value) &&
    typeof value["state"] === "string" &&
    typeof value["verifier"] === "string" &&
    typeof value["returnTo"] === "string"
  );
}

export class OAuthError extends Error {
  override readonly name = "OAuthError";
}

/** Whether the access token expires within a minute. */
export function needsRefresh(session: OAuthSession, now: number): boolean {
  return session.expiresAt - 60_000 <= now;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function base64url(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCodePoint(byte);
  }

  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/u, "");
}

function fromBase64url(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.codePointAt(index) ?? 0;
  }

  return bytes;
}

/** `length` random bytes as base64url. */
export function randomToken(length = 32): string {
  return base64url(crypto.getRandomValues(new Uint8Array(length)));
}

/** A PKCE verifier and its S256 challenge (RFC 7636). */
export async function pkcePair(): Promise<{
  verifier: string;
  challenge: string;
}> {
  const verifier = randomToken(32);

  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(verifier),
  );

  return { verifier, challenge: base64url(new Uint8Array(digest)) };
}

async function cookieKey(secret: string, info: string): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    "HKDF",
    false,
    ["deriveKey"],
  );

  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: new Uint8Array(0),
      info: encoder.encode(info),
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

/**
 * Encrypts `value` as JSON with AES-GCM: base64url of the IV, then the
 * ciphertext. The key comes from `secret` through HKDF with `info`; give
 * each cookie its own `info` so one can't be swapped for another.
 */
export async function seal(
  value: object,
  secret: string,
  info: string = DEFAULT_SEAL_INFO,
): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));

  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await cookieKey(secret, info),
    encoder.encode(JSON.stringify(value)),
  );

  const sealed = new Uint8Array(iv.length + cipher.byteLength);
  sealed.set(iv);
  sealed.set(new Uint8Array(cipher), iv.length);

  return base64url(sealed);
}

/**
 * The value `seal` wrote with the same `secret` and `info`, or `undefined`
 * when it is missing, tampered with or another shape.
 */
export async function unseal<TValue>(
  sealed: string | undefined,
  secret: string,
  guard: (value: unknown) => value is TValue,
  info: string = DEFAULT_SEAL_INFO,
): Promise<TValue | undefined> {
  if (sealed === undefined || sealed === "") {
    return undefined;
  }

  try {
    const bytes = fromBase64url(sealed);

    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: bytes.slice(0, 12) },
      await cookieKey(secret, info),
      bytes.slice(12),
    );

    const parsed: unknown = JSON.parse(decoder.decode(plain));

    return guard(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}
