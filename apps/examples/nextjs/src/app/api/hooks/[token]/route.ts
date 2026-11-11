import { createIncomingWebhooks } from "better-supabase/blocks/webhooks";

import { postgres } from "../../../../features/developer/postgres";

/**
 * `POST /api/hooks/<token>`: the trigger URL of an incoming endpoint. The token
 * picks the endpoint, which verifies the signature and stores the delivery in
 * the webhook inbox. It reads with the database owner and checks the token
 * itself, so it needs no session.
 */
export async function POST(
  request: Request,
  context: RouteContext<"/api/hooks/[token]">,
): Promise<Response> {
  const connection = postgres();

  if (!connection) {
    return new Response("Set WORKFLOW_POSTGRES_URL to receive webhooks", {
      status: 503,
    });
  }

  const { token } = await context.params;

  return createIncomingWebhooks({ sql: connection.admin }).receive({
    request,
    token,
  });
}
