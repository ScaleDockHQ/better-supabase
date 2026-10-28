import { connection } from "next/server";

import { env } from "@/env";

import { sessionStats } from "../../../lib/supabase/server";

/**
 * The verified-session memo's counters, in a testing build only: a miss is a
 * render that verified a token. `tests/islands.spec.ts` reads them around a
 * page load.
 */
export async function GET(): Promise<Response> {
  await connection();

  if (env.EXPOSE_TESTING_API !== "1") {
    return Response.json(
      { error: "debug is off" },
      { status: 404, headers: { "cache-control": "no-store" } },
    );
  }

  return Response.json(sessionStats(), {
    headers: { "cache-control": "no-store" },
  });
}
