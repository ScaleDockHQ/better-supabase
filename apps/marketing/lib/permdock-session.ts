import {
  isFlow,
  needsRefresh,
  OAuthError,
  seal,
  unseal,
  type SupabaseSession,
} from "better-supabase/create/supabase";
import { cookies } from "next/headers";
import * as v from "valibot";

import { env } from "@/env";

export const PERMDOCK_API = "https://permdock.com/api";
const PERMDOCK_SCOPE = "projects:read policy:read";
export const PERMDOCK_PATH = "/create/permdock";
const PERMDOCK_SESSION_COOKIE = "bs_permdock";
export const PERMDOCK_FLOW_COOKIE = "bs_permdock_flow";
const PERMDOCK_SESSION_MAX_AGE: number = 60 * 60 * 24 * 7;

export const permdockCookieOptions = {
  httpOnly: true,
  secure: true,
  sameSite: "lax",
  path: PERMDOCK_PATH,
} as const;

export interface PermdockConfig {
  readonly clientId: string;
  readonly cookieSecret: string;
}

/** The OAuth app settings, or `undefined` when the connection is turned off. */
export function permdockConfig(): PermdockConfig | undefined {
  const clientId = env.PERMDOCK_OAUTH_CLIENT_ID;
  const cookieSecret = env.PERMDOCK_OAUTH_COOKIE_SECRET;

  return clientId === undefined || cookieSecret === undefined
    ? undefined
    : { clientId, cookieSecret };
}

export function permdockRedirectUri(origin: string): string {
  return `${origin}${PERMDOCK_PATH}/callback`;
}

export function permdockAuthorizeUrl({
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
  const url = new URL("oauth/authorize", `${PERMDOCK_API}/`);

  url.search = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: PERMDOCK_SCOPE,
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  }).toString();

  return url.toString();
}

const tokenResponse = v.object({
  access_token: v.string(),
  expires_in: v.number(),
  refresh_token: v.optional(v.string()),
});

async function tokenRequest(
  body: Record<string, string>,
  clientId: string,
): Promise<SupabaseSession> {
  const response = await fetch(new URL("oauth/token", `${PERMDOCK_API}/`), {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams({ ...body, client_id: clientId }),
  });

  if (!response.ok) {
    throw new OAuthError(
      `The token request was refused (${String(response.status)}).`,
    );
  }

  const parsed = v.safeParse(tokenResponse, await response.json());

  if (!parsed.success) {
    throw new OAuthError("The token response had no access token.");
  }

  return {
    accessToken: parsed.output.access_token,
    refreshToken: parsed.output.refresh_token,
    expiresAt: Date.now() + parsed.output.expires_in * 1000,
  };
}

export function exchangePermdockCode(
  config: PermdockConfig,
  {
    code,
    verifier,
    redirectUri,
  }: { code: string; verifier: string; redirectUri: string },
): Promise<SupabaseSession> {
  return tokenRequest(
    {
      grant_type: "authorization_code",
      code,
      code_verifier: verifier,
      redirect_uri: redirectUri,
    },
    config.clientId,
  );
}

export async function writePermdockSession(
  config: PermdockConfig,
  session: SupabaseSession,
): Promise<void> {
  const jar = await cookies();

  jar.set(PERMDOCK_SESSION_COOKIE, await seal(session, config.cookieSecret), {
    ...permdockCookieOptions,
    maxAge: PERMDOCK_SESSION_MAX_AGE,
  });
}

export async function clearPermdockSession(): Promise<void> {
  const jar = await cookies();
  jar.delete({ name: PERMDOCK_SESSION_COOKIE, path: PERMDOCK_PATH });
}

export const isPermdockFlow = isFlow;

function isSession(value: unknown): value is SupabaseSession {
  return v.is(
    v.object({
      accessToken: v.string(),
      refreshToken: v.optional(v.string()),
      expiresAt: v.number(),
    }),
    value,
  );
}

async function currentSession(
  config: PermdockConfig,
): Promise<SupabaseSession | undefined> {
  const jar = await cookies();

  const session = await unseal(
    jar.get(PERMDOCK_SESSION_COOKIE)?.value,
    config.cookieSecret,
    isSession,
  );

  if (session === undefined || !needsRefresh(session, Date.now())) {
    return session;
  }

  if (session.refreshToken === undefined) {
    throw new OAuthError("The connection expired. Connect again.");
  }

  const next = await tokenRequest(
    { grant_type: "refresh_token", refresh_token: session.refreshToken },
    config.clientId,
  );

  const kept = {
    ...next,
    refreshToken: next.refreshToken ?? session.refreshToken,
  };

  await writePermdockSession(config, kept);

  return kept;
}

/** The visitor's access token, or `undefined` when they are not connected. */
export async function permdockAccessToken(
  config: PermdockConfig,
): Promise<string | undefined> {
  try {
    return (await currentSession(config))?.accessToken;
  } catch (error) {
    if (error instanceof OAuthError) {
      await clearPermdockSession();

      return undefined;
    }

    throw error;
  }
}
