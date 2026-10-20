import { clearPermdockSession } from "@/lib/permdock-session";
import { errorResponse, sameOrigin } from "@/lib/supabase-session";

/** Forgets the connection. The OAuth app stays authorized on the service. */
export async function POST(request: Request): Promise<Response> {
  if (!sameOrigin(request)) {
    return errorResponse("invalid", "Cross-site request.", 403);
  }

  await clearPermdockSession();

  return new Response(null, { status: 204 });
}
