import {
  authorizeUrl,
  FLOW_COOKIE,
  FLOW_MAX_AGE,
  pkcePair,
  randomToken,
  returnPath,
  seal,
} from "better-supabase/create/supabase";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import * as v from "valibot";

import {
  cookieOptions,
  errorResponse,
  oauthConfig,
  redirectUri,
  sameOrigin,
} from "@/lib/supabase-session";

/**
 * Starts the Supabase OAuth flow: keeps the PKCE verifier, the state and the
 * `/create` URL to return to in a short-lived sealed cookie, then sends the
 * browser to Supabase's consent screen. The dialog posts a form here, so a
 * prefetch or a cross-site link can't start a flow.
 */
export async function POST(request: Request): Promise<Response> {
  const config = oauthConfig();

  if (config === undefined) {
    return errorResponse(
      "invalid",
      "Deploying to Supabase is turned off.",
      404,
    );
  }

  if (!sameOrigin(request)) {
    return errorResponse("invalid", "Cross-site request.", 403);
  }

  const { verifier, challenge } = await pkcePair();
  const state = randomToken(16);

  const form = await request.formData();
  const target = v.safeParse(v.string(), form.get("return"));
  const returnTo = returnPath(target.success ? target.output : null);

  const jar = await cookies();

  jar.set(
    FLOW_COOKIE,
    await seal({ state, verifier, returnTo }, config.cookieSecret),
    { ...cookieOptions, maxAge: FLOW_MAX_AGE },
  );

  return NextResponse.redirect(
    authorizeUrl({
      clientId: config.clientId,
      redirectUri: redirectUri(request),
      state,
      challenge,
    }),
    303,
  );
}
