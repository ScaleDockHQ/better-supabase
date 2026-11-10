import { createClient } from "@supabase/supabase-js";

import { env } from "@/env";

/** The service-role client for code that runs outside a request. */
export function serviceSupabase() {
  const url = env.NEXT_PUBLIC_SUPABASE_URL;
  const key = env.SUPABASE_SECRET_KEY;

  if (!url || !key) {
    throw new Error(
      "Workflow steps need NEXT_PUBLIC_SUPABASE_URL and SUPABASE_SECRET_KEY",
    );
  }

  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
