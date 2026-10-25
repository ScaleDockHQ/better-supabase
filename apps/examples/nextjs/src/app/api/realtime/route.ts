import { liveRelayTopic, realtimeRelay } from "better-supabase/server";

import { postgres } from "../../../features/developer/postgres";
import { bsb } from "../../../lib/supabase/server";

let relay: ReturnType<typeof realtimeRelay> | undefined;

/**
 * Live queries for callers without a browser token (a support session): the
 * relay checks each channel's policies as the viewed user over Postgres.
 */
function relayRoute(): ReturnType<typeof realtimeRelay> | undefined {
  const pool = postgres();

  if (!pool) {
    return undefined;
  }

  relay ??= realtimeRelay(bsb, { topics: [liveRelayTopic], postgres: pool });

  return relay;
}

const unavailable = (): Response =>
  Response.json(
    { error: "Set WORKFLOW_POSTGRES_URL to relay Realtime" },
    { status: 503 },
  );

export function GET(request: Request): Promise<Response> | Response {
  return relayRoute()?.GET(request) ?? unavailable();
}

export function POST(request: Request): Promise<Response> | Response {
  return relayRoute()?.POST(request) ?? unavailable();
}
