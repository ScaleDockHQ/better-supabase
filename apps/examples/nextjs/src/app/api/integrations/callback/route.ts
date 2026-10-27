import {
  connectCredentials,
  integrationOf,
} from "../../../../features/integrations/integrations-server";
import { bsb } from "../../../../lib/supabase/server";

const SETTINGS_PATH = "/settings/integrations";

/**
 * `GET /api/integrations/callback`: where Vercel Connect returns the user after
 * consent. Connect stores the grant itself, so the route reads the token once,
 * skipping the cache, and sends the user back to the settings tab with the
 * outcome in the query.
 */
export const GET = bsb.route(async (request, { session }) => {
  const url = new URL(request.url);
  const id = url.searchParams.get("integration") ?? "";
  const integration = integrationOf(id);
  const back = new URL(SETTINGS_PATH, url);

  if (integration === undefined || session.kind !== "user") {
    back.searchParams.set("failed", id);

    return Response.redirect(back, 303);
  }

  const token = await connectCredentials().getToken(integration.ref, {
    subject: { type: "user", id: session.user.id },
    fresh: true,
  });

  back.searchParams.set(token.ok ? "connected" : "failed", integration.id);

  return Response.redirect(back, 303);
});
