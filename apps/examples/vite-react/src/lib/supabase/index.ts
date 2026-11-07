import { createSupabase } from "better-supabase";

import { clientSchema } from "./generated";

export type { Functions, Models } from "./generated";

export const betterSupabase = createSupabase(clientSchema);
