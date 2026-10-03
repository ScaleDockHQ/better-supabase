import { createHooks } from "better-supabase/react";

import type { bs } from "./supabase/client";

export const { useDb, useQueries, useAuth, useSupabase } =
  createHooks<typeof bs>();
