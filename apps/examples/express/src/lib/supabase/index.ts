import { createSupabase } from "better-supabase";

import { schema } from "./generated-schema.ts";

export type { Functions, Models } from "./generated.ts";

export const betterSupabase = createSupabase(schema);
