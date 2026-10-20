import {
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
  permdockAuthorizeUrl,
  permdockConfig,
  permdockCookieOptions,
  PERMDOCK_FLOW_COOKIE,
  permdockRedirectUri,
} from "@/lib/permdock-session";
import {
  errorResponse,
  publicOrigin,
  sameOrigin,
} from "@/lib/supabase-session";

/** Starts the OAuth flow for the hosted authorization service with PKCE. */
export async function POST(request: Request): Promise<Response> {
  const config = permdockConfig();

  if (config === undefined) {
    return errorResponse("invalid", "This connection is turned off.", 404);
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
    PERMDOCK_FLOW_COOKIE,
    await seal({ state, verifier, returnTo }, config.cookieSecret),
    { ...permdockCookieOptions, maxAge: FLOW_MAX_AGE },
  );

  return NextResponse.redirect(
    permdockAuthorizeUrl({
      clientId: config.clientId,
      redirectUri: permdockRedirectUri(publicOrigin(request)),
      state,
      challenge,
    }),
    303,
  );
}
