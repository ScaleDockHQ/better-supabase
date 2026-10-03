import { defineSupabase } from "better-supabase";

import { schema } from "./generated";

export type { Functions, Models } from "./generated";

export const betterSupabase = defineSupabase(schema);
