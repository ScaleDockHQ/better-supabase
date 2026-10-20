import { OAuthError, unseal } from "better-supabase/create/supabase";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";

import {
  exchangePermdockCode,
  isPermdockFlow,
  permdockConfig,
  PERMDOCK_FLOW_COOKIE,
  PERMDOCK_PATH,
  permdockRedirectUri,
  writePermdockSession,
} from "@/lib/permdock-session";
import { errorResponse, publicOrigin } from "@/lib/supabase-session";

/** The browser returns here from the consent screen, then goes back to `/create`. */
export async function GET(request: Request): Promise<Response> {
  const config = permdockConfig();

  if (config === undefined) {
    return errorResponse("invalid", "This connection is turned off.", 404);
  }

  const params = new URL(request.url).searchParams;
  const jar = await cookies();

  const flow = await unseal(
    jar.get(PERMDOCK_FLOW_COOKIE)?.value,
    config.cookieSecret,
    isPermdockFlow,
  );

  jar.delete({ name: PERMDOCK_FLOW_COOKIE, path: PERMDOCK_PATH });

  const back = (path: string, failed: boolean): Response => {
    const url = new URL(path, publicOrigin(request));
    url.searchParams.set("permdock", failed ? "error" : "connected");

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
    const session = await exchangePermdockCode(config, {
      code,
      verifier: flow.verifier,
      redirectUri: permdockRedirectUri(publicOrigin(request)),
    });

    await writePermdockSession(config, session);
  } catch (error) {
    if (error instanceof OAuthError) {
      return back(flow.returnTo, true);
    }

    throw error;
  }

  return back(flow.returnTo, false);
}
