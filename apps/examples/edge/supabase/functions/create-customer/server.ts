import { createEdge } from "better-supabase/edge";

import { betterSupabase } from "../_shared/supabase.ts";

export const bs = createEdge(betterSupabase, { cors: true });
