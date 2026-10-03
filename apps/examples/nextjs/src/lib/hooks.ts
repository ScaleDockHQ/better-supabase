import { createHooks } from "better-supabase/react";

import type { bs } from "./supabase/client";

/** `useSession()` here types `session.claims` with `Claims` (src/lib/claims.ts). */
export const { useDb, useQueries, useAuth, useSupabase, useSession } =
  createHooks<typeof bs>();
