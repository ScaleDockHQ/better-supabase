import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

/**
 * Reopens conversations whose snooze ended and sends scheduled replies whose
 * time came. Call it every minute from a cron (Vercel Cron sends
 * `Authorization: Bearer $CRON_SECRET`); a jobs handler on `inbox_schedule` can
 * call the same two methods instead.
 */
export async function GET(request: Request): Promise<Response> {
  const secret = process.env["CRON_SECRET"];

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const { inbox } = blocks(bs.admin().$client);
  const woken = await inbox.wakeSnoozed().orThrow();
  const published = await inbox.publishDue().orThrow();

  return Response.json({ woken, published });
}
