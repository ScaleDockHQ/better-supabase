import { sqlTransport } from "better-supabase/blocks/inbox";
import { createSupabaseState, maintain } from "better-supabase/chat-sdk";

import { env } from "@/env";
import { postgres } from "@/features/developer/postgres";
import { bsb } from "@/lib/supabase/server";

/**
 * The inbox's periodic work: reopens conversations whose snooze ended, sends
 * scheduled replies whose time came, purges processed webhook events and, with
 * `WORKFLOW_POSTGRES_URL` set, sweeps expired Chat SDK state. Call it every
 * minute from a cron (Vercel Cron sends `Authorization: Bearer $CRON_SECRET`).
 */
export async function GET(request: Request): Promise<Response> {
  const secret = env.CRON_SECRET;

  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const connection = postgres();

  const result = await maintain({
    inbox: bsb.admin().inbox,
    ...(connection && {
      state: createSupabaseState({ transport: sqlTransport(connection.admin) }),
    }),
  });

  return Response.json(result);
}
