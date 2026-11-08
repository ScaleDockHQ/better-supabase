import { createSupabase } from "better-supabase";

import { schema } from "../../../lib/supabase/generated-schema.ts";

export const betterSupabase = createSupabase(schema);
