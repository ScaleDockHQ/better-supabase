import { createHooks } from "better-supabase/react";

import type { browser } from "./supabase.browser";

export const { useDb, useQueries, useAuth, useSupabase } =
  createHooks<typeof browser>();
