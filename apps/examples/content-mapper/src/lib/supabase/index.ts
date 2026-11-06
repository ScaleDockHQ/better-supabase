import { createSupabase } from "better-supabase";

import { schema } from "./generated.ts";

export type { Database, Models, RowOf } from "./generated.ts";

export const betterSupabase = createSupabase(schema);
