import { defineSupabase } from "better-supabase";

import { schema } from "./generated.ts";

export type { Database, Models, RowOf } from "./generated.ts";

export const betterSupabase = defineSupabase(schema);
