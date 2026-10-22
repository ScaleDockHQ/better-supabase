import { createHooks } from "better-supabase/react";

import type { bsb } from "./supabase/client";

export const { useDb, useQueries, useAuth, useSupabase } =
  createHooks<typeof bsb>();
