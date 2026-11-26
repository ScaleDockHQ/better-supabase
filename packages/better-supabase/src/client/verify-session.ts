import type { SupabaseClient } from "@supabase/supabase-js";

export async function verifySession(
  supabase: SupabaseClient,
  check: {
    readonly schema: string;
    readonly rpc: string;
    readonly isCurrent: () => boolean;
  },
): Promise<void> {
  const response: { readonly data: unknown; readonly error: unknown } =
    await supabase
      .schema(check.schema)
      .rpc(`bootstrap_${check.rpc}`, { args: {} });

  const { data } = response;

  if (
    response.error === null &&
    typeof data === "object" &&
    data !== null &&
    "session_active" in data &&
    data.session_active === false &&
    check.isCurrent()
  ) {
    await supabase.auth.signOut({ scope: "local" });
  }
}
