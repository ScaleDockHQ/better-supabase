import {
  isOAuthSession,
  type OAuthSession,
  OAuthError,
} from "../oauth/index.ts";
import { isRecord } from "./guards.ts";

export {
  DEFAULT_SEAL_INFO,
  isFlow,
  isOAuthSession,
  needsRefresh,
  OAuthError,
  pkcePair,
  randomToken,
  seal,
  unseal,
} from "../oauth/index.ts";

export type { OAuthFlow, OAuthSession } from "../oauth/index.ts";

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

/** A Supabase OAuth session; the same shape as `OAuthSession`. */
export type SupabaseSession = OAuthSession;

/** `isOAuthSession`, under its Supabase name. */
export const isSession: (value: unknown) => value is SupabaseSession =
  isOAuthSession;

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
