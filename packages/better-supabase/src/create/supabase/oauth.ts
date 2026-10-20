import { isRecord } from "./guards.ts";

export const SUPABASE_API: string = "https://api.supabase.com";

/** Where the session and the in-flight authorization live. */
export const COOKIE_PATH: string = "/create/supabase";
export const SESSION_COOKIE = "bs_supabase";
export const FLOW_COOKIE = "bs_supabase_flow";

/** A flow cookie older than this is ignored, so a stale tab can't finish one. */
export const FLOW_MAX_AGE = 600;

/** The session cookie outlives the access token; the refresh token renews it. */
export const SESSION_MAX_AGE: number = 60 * 60 * 24 * 7;

export interface OAuthConfig {
  readonly clientId: string;
  readonly clientSecret: string;
  readonly cookieSecret: string;
}

export interface SupabaseSession {
  readonly accessToken: string;
  readonly refreshToken?: string | undefined;
  /** Epoch milliseconds. */
  readonly expiresAt: number;
}

export function isSession(value: unknown): value is SupabaseSession {
  return (
    isRecord(value) &&
    typeof value["accessToken"] === "string" &&
    (value["refreshToken"] === undefined ||
      typeof value["refreshToken"] === "string") &&
    typeof value["expiresAt"] === "number"
  );
}

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
    .replace(/=+$/u, "");
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

async function cookieKey(secret: string): Promise<CryptoKey> {
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
      info: encoder.encode("better-supabase create session"),
    },
    material,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

/** Encrypts `value` as JSON with AES-GCM: base64url of the IV, then the ciphertext. */
export async function seal(value: object, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));

  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await cookieKey(secret),
    encoder.encode(JSON.stringify(value)),
  );

  const sealed = new Uint8Array(iv.length + cipher.byteLength);
  sealed.set(iv);
  sealed.set(new Uint8Array(cipher), iv.length);

  return base64url(sealed);
}

/** The value `seal` wrote, or `undefined` when it is missing, tampered with or another shape. */
export async function unseal<TValue>(
  sealed: string | undefined,
  secret: string,
  guard: (value: unknown) => value is TValue,
): Promise<TValue | undefined> {
  if (sealed === undefined || sealed === "") {
    return undefined;
  }

  try {
    const bytes = fromBase64url(sealed);

    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: bytes.slice(0, 12) },
      await cookieKey(secret),
      bytes.slice(12),
    );

    const parsed: unknown = JSON.parse(decoder.decode(plain));

    return guard(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

/**
 * A same-site path under `/create` to return to after the consent screen,
 * or `/create` for anything else, so the callback never redirects off site.
 */
export function returnPath(value: string | null): string {
  if (value === null) {
    return "/create";
  }

  try {
    const url = new URL(value, "https://create.invalid");

    if (
      url.origin !== "https://create.invalid" ||
      (url.pathname !== "/create" && !url.pathname.startsWith("/create/"))
    ) {
      return "/create";
    }

    return `${url.pathname}${url.search}`;
  } catch {
    return "/create";
  }
}

/** Adds `deploy=1`, which opens the deploy dialog again after the redirect. */
export function withDeployFlag(path: string): string {
  const url = new URL(path, "https://create.invalid");
  url.searchParams.set("deploy", "1");

  return `${url.pathname}${url.search}`;
}

export function authorizeUrl({
  clientId,
  redirectUri,
  state,
  challenge,
}: {
  clientId: string;
  redirectUri: string;
  state: string;
  challenge: string;
}): string {
  const url = new URL("/v1/oauth/authorize", SUPABASE_API);
  url.search = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  }).toString();

  return url.toString();
}

export class OAuthError extends Error {
  override readonly name = "OAuthError";
}

async function tokenRequest(
  config: OAuthConfig,
  body: Record<string, string>,
  fetchImpl: typeof fetch,
  now: number,
): Promise<SupabaseSession> {
  const response = await fetchImpl(new URL("/v1/oauth/token", SUPABASE_API), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
      Authorization: `Basic ${btoa(`${config.clientId}:${config.clientSecret}`)}`,
    },
    body: new URLSearchParams(body),
  });

  if (!response.ok) {
    throw new OAuthError(
      `Supabase refused the token request (${String(response.status)}).`,
    );
  }

  const payload: unknown = await response.json();

  if (
    !isRecord(payload) ||
    typeof payload["access_token"] !== "string" ||
    typeof payload["expires_in"] !== "number" ||
    (payload["refresh_token"] !== undefined &&
      typeof payload["refresh_token"] !== "string")
  ) {
    throw new OAuthError("Supabase sent a token response without a token.");
  }

  return {
    accessToken: payload["access_token"],
    refreshToken: payload["refresh_token"],
    expiresAt: now + payload["expires_in"] * 1000,
  };
}

/** Exchanges the authorization code from the callback for a session. */
export function exchangeCode(
  config: OAuthConfig,
  {
    code,
    verifier,
    redirectUri,
  }: { code: string; verifier: string; redirectUri: string },
  fetchImpl: typeof fetch = fetch,
  now: number = Date.now(),
): Promise<SupabaseSession> {
  return tokenRequest(
    config,
    {
      grant_type: "authorization_code",
      code,
      code_verifier: verifier,
      redirect_uri: redirectUri,
    },
    fetchImpl,
    now,
  );
}

/** Whether the access token expires within a minute. */
export function needsRefresh(session: SupabaseSession, now: number): boolean {
  return session.expiresAt - 60_000 <= now;
}

/** A new session from the refresh token; it keeps the old refresh token when Supabase sends none. */
export async function refreshSession(
  config: OAuthConfig,
  session: SupabaseSession,
  fetchImpl: typeof fetch = fetch,
  now: number = Date.now(),
): Promise<SupabaseSession> {
  if (session.refreshToken === undefined) {
    throw new OAuthError("The Supabase session expired. Connect again.");
  }

  const next = await tokenRequest(
    config,
    { grant_type: "refresh_token", refresh_token: session.refreshToken },
    fetchImpl,
    now,
  );

  return { ...next, refreshToken: next.refreshToken ?? session.refreshToken };
}
