import { createSupabase } from "better-supabase";
import { Temporal } from "temporal-polyfill";

import { schema } from "./generated";

export type { Functions, Models } from "./generated";

export const betterSupabase = createSupabase(schema, { temporal: Temporal });
