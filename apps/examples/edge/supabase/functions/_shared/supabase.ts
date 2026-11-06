import { createSupabase } from "better-supabase";

import { schema } from "../../../lib/supabase/generated.ts";

export const betterSupabase = createSupabase(schema);
