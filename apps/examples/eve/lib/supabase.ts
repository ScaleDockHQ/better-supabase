import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let client: SupabaseClient | undefined;

/** The browser client; its session lives in localStorage. */
export function browserClient(): SupabaseClient {
  client ??= createClient(
    process.env["NEXT_PUBLIC_SUPABASE_URL"] ?? "",
    process.env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"] ?? "",
  );
  return client;
}
