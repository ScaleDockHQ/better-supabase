import { withCors } from "@supabase/middleware/cors";
import { withSupabaseClient } from "@supabase/server/middleware/client";
import { withRequiredClaims } from "@supabase/server/middleware/required-claims";
import { toNextRoute } from "better-supabase/next";

/**
 * The customers the caller can see, through the Supabase middleware entries
 * instead of `bsb.route()`: RLS decides the rows.
 */
export const GET = toNextRoute(
  [
    withCors({ origin: "https://app.example.com" }),
    withRequiredClaims(),
    withSupabaseClient(),
  ],
  async (_request, ctx) => {
    const { data, error } = await ctx.supabase
      .from("customers")
      .select("id, name")
      .limit(20);

    return error
      ? Response.json({ error: error.message }, { status: 500 })
      : data;
  },
);
