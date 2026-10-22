import { createExpo } from "better-supabase/expo";

import { betterSupabase } from ".";

export const bsb = createExpo(betterSupabase);
