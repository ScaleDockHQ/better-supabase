import { createSupabase } from "better-supabase";

import { schema } from "./generated-schema";

export type { Functions, Models } from "./generated";

export const betterSupabase = createSupabase(schema);
