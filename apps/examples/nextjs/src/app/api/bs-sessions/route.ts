import { bsb } from "../../../lib/supabase/server";

/** The session memo's counters, for the e2e build only (`e2e/islands.spec.ts`). */
export function GET(): Response {
  if (process.env["EXPOSE_TESTING_API"] !== "1") {
    return Response.json({ error: "not found" }, { status: 404 });
  }

  return Response.json(bsb.sessions.stats(), {
    headers: { "cache-control": "no-store" },
  });
}
