import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import {
  COOKIE_PATH,
  exchangeCode,
  FLOW_COOKIE,
  flowSchema,
  OAuthError,
  unseal,
  withDeployFlag,
} from "@/lib/supabase-oauth";
import {
  errorResponse,
  oauthConfig,
  publicOrigin,
  redirectUri,
  writeSession,
} from "@/lib/supabase-session";

/**
 * Supabase sends the browser here after the consent screen. A matching
 * state turns the code into a session cookie; either way the browser goes
 * back to `/create` with the deploy dialog open, and `deploy=error` when
 * the connection failed.
 */
export async function GET(request: Request): Promise<Response> {
  const config = oauthConfig();

  if (config === undefined) {
    return errorResponse(
      "invalid",
      "Deploying to Supabase is turned off.",
      404,
    );
  }

  const params = new URL(request.url).searchParams;
  const jar = await cookies();

  const flow = await unseal(
    jar.get(FLOW_COOKIE)?.value,
    config.cookieSecret,
    flowSchema,
  );

  jar.delete({ name: FLOW_COOKIE, path: COOKIE_PATH });

  const back = (path: string, failed: boolean): Response => {
    const url = new URL(withDeployFlag(path), publicOrigin(request));

    if (failed) {
      url.searchParams.set("deploy", "error");
    }

    return NextResponse.redirect(url);
  };

  const code = params.get("code");

  if (
    flow === undefined ||
    code === null ||
    params.get("state") !== flow.state
  ) {
    return back(flow?.returnTo ?? "/create", true);
  }

  try {
    const session = await exchangeCode(config, {
      code,
      verifier: flow.verifier,
      redirectUri: redirectUri(request),
    });

    await writeSession(config, session);
  } catch (error) {
    if (error instanceof OAuthError) {
      return back(flow.returnTo, true);
    }

    throw error;
  }

  return back(flow.returnTo, false);
}
