import type { ErrorResponse } from "better-supabase/create";

import {
  type ManagementClient,
  managementClient,
  ManagementError,
  COOKIE_PATH,
  needsRefresh,
  type OAuthConfig,
  OAuthError,
  refreshSession,
  seal,
  SESSION_COOKIE,
  SESSION_MAX_AGE,
  isSession,
  type SupabaseSession,
  unseal,
} from "better-supabase/create/supabase";
import { cookies } from "next/headers";

import { env } from "@/env";

/** The OAuth app settings, or `undefined` when deploying is turned off. */
export function oauthConfig(): OAuthConfig | undefined {
  const clientId = env.SUPABASE_OAUTH_CLIENT_ID;
  const clientSecret = env.SUPABASE_OAUTH_CLIENT_SECRET;
  const cookieSecret = env.SUPABASE_OAUTH_COOKIE_SECRET;

  return clientId === undefined ||
    clientSecret === undefined ||
    cookieSecret === undefined
    ? undefined
    : { clientId, clientSecret, cookieSecret };
}

export function errorResponse(
  error: ErrorResponse["error"],
  message: string,
  status: number,
): Response {
  const body: ErrorResponse = { error, message };

  return Response.json(body, { status });
}

/** The public origin the browser used, behind Portless or Vercel's proxy too. */
export function publicOrigin(request: Request): string {
  const url = new URL(request.url);
  const host = request.headers.get("x-forwarded-host") ?? url.host;

  const proto =
    request.headers.get("x-forwarded-proto") ?? url.protocol.slice(0, -1);

  return `${proto}://${host}`;
}

export function redirectUri(request: Request): string {
  return `${publicOrigin(request)}${COOKIE_PATH}/callback`;
}

/** Whether a state-changing request came from this site's own pages. */
export function sameOrigin(request: Request): boolean {
  return request.headers.get("origin") === publicOrigin(request);
}

export const cookieOptions = {
  httpOnly: true,
  secure: true,
  sameSite: "lax",
  path: COOKIE_PATH,
} as const;

export async function writeSession(
  config: OAuthConfig,
  session: SupabaseSession,
): Promise<void> {
  const jar = await cookies();

  jar.set(SESSION_COOKIE, await seal(session, config.cookieSecret), {
    ...cookieOptions,
    maxAge: SESSION_MAX_AGE,
  });
}

export async function clearSession(): Promise<void> {
  const jar = await cookies();
  jar.delete({ name: SESSION_COOKIE, path: COOKIE_PATH });
}

async function currentSession(
  config: OAuthConfig,
): Promise<SupabaseSession | undefined> {
  const jar = await cookies();

  const session = await unseal(
    jar.get(SESSION_COOKIE)?.value,
    config.cookieSecret,
    isSession,
  );

  if (session === undefined || !needsRefresh(session, Date.now())) {
    return session;
  }

  const next = await refreshSession(config, session);
  await writeSession(config, next);

  return next;
}

/**
 * Runs `handler` with a Management API client for the visitor's Supabase
 * session. A missing or revoked session answers `connect` (401), and a
 * Management API failure answers `supabase` with Supabase's message.
 */
export async function withSupabase(
  handler: (client: ManagementClient) => Promise<Response>,
): Promise<Response> {
  const config = oauthConfig();

  if (config === undefined) {
    return errorResponse(
      "invalid",
      "Deploying to Supabase is turned off.",
      404,
    );
  }

  try {
    const session = await currentSession(config);

    if (session === undefined) {
      return errorResponse("connect", "Connect your Supabase account.", 401);
    }

    return await handler(managementClient(session.accessToken));
  } catch (error) {
    if (
      error instanceof OAuthError ||
      (error instanceof ManagementError && error.status === 401)
    ) {
      await clearSession();

      return errorResponse("connect", error.message, 401);
    }

    if (error instanceof ManagementError) {
      return errorResponse(
        "supabase",
        error.message,
        error.status >= 400 && error.status < 500 ? error.status : 502,
      );
    }

    throw error;
  }
}
