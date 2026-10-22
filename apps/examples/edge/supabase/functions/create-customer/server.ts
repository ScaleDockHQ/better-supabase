import { createEdge } from "better-supabase/edge";

import { betterSupabase } from "../_shared/supabase.ts";

export const bsb = createEdge(betterSupabase, { cors: true });
