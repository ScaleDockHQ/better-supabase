import { defineSupabase } from "better-supabase";

import { schema } from "./generated.ts";

export type { Functions, Models } from "./generated.ts";

export const betterSupabase = defineSupabase(schema);
