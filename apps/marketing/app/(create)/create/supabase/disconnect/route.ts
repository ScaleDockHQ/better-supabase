import {
  clearSession,
  errorResponse,
  sameOrigin,
} from "@/lib/supabase-session";

/** Forgets the Supabase session. The OAuth app stays authorized in Supabase. */
export async function POST(request: Request): Promise<Response> {
  if (!sameOrigin(request)) {
    return errorResponse("invalid", "Cross-site request.", 403);
  }

  await clearSession();

  return new Response(null, { status: 204 });
}
