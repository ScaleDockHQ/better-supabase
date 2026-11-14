import { NextResponse } from "next/server";

import { bsbCore } from "@/lib/supabase/server-core";

/**
 * Where the sign-up confirmation link lands: exchanges its `?code=` and the
 * PKCE verifier cookie `signUp` wrote for a session, then opens `?next=`. A
 * code works once, so a second open goes to sign-in.
 */
export async function GET(request: Request): Promise<Response> {
  const params = new URL(request.url).searchParams;

  const result = await bsbCore.exchangeCodeForSession({
    code: params.get("code") ?? "",
    next: params.get("next"),
  });

  return NextResponse.redirect(
    new URL(result.ok ? result.data.redirectTo : "/login", request.url),
  );
}
