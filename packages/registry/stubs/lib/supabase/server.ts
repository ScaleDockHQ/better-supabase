// Stands in for the Next.js `src/lib/supabase/server.ts` from `better-supabase init`.
import { createNext } from "better-supabase/next";

import { betterSupabase } from "./index";

export const bsb = createNext(betterSupabase);
