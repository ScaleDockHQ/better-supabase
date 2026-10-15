// Stands in for the `src/lib/supabase/index.ts` that `better-supabase init`
// writes, with an empty schema, so the items typecheck without an app.
import { defineSchema, defineSupabase } from "better-supabase";

export const betterSupabase = defineSupabase(
  defineSchema({
    version: 1,
    casing: "camel",
    tables: {},
    enums: {},
    functions: {},
  }),
);
