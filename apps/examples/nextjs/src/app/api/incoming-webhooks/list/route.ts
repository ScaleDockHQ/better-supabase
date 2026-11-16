import { loadAdminList } from "../../../../features/admin-lists/admin-list-load";
import { incomingWebhookList } from "../../../../features/incoming-webhooks/incoming-webhooks-list";
import { incomingWebhookSource } from "../../../../features/incoming-webhooks/incoming-webhooks-source";
import { bsbCore as bsb } from "../../../../lib/supabase/server-core";

/**
 * `GET /api/incoming-webhooks/list?q=&state=&verify=&sort=&after=`: one page of
 * incoming endpoints with the count per state and verification mode.
 */
export const GET = bsb.route(
  async (request, { session, tenant }) => {
    const query = incomingWebhookList.parse(request.nextUrl.searchParams);

    return Response.json(
      await loadAdminList({
        session,
        tenant,
        list: incomingWebhookList,
        source: incomingWebhookSource,
        access: "user",
        query: query.value,
      }),
    );
  },
  { requireTenant: true, permission: "webhooks.read" },
);
