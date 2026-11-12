"use client";

import type { AuthSession } from "better-supabase/react";

import { SessionProvider } from "better-supabase/react";
import { useMemo } from "react";

import { useRouter } from "@/i18n/navigation";
import { useSupabase } from "@/lib/hooks";

import { refreshSessionCache } from "../islands-actions";

/**
 * Listens on the caller's `authz:<uid>` topic. When the authorization version
 * moves, the provider refreshes the token, this drops the caller's cached
 * entries, and the page re-renders in the background with the new claims.
 */
export function AuthzRefresh({ session }: { session: Promise<AuthSession> }) {
  const supabase = useSupabase();
  const router = useRouter();

  // The version function lives in the `api` schema; the provider calls `rpc`
  // on the client it gets, which would read `public` and answer 404.
  const client = useMemo(
    () => ({
      channel: supabase.channel.bind(supabase),
      auth: supabase.auth,
      rpc: (fn: "caller_authz_version") => supabase.schema("api").rpc(fn),
    }),
    [supabase],
  );

  return (
    <SessionProvider
      session={session}
      client={client}
      onAuthzChange={async () => {
        await refreshSessionCache();
        router.refresh();
      }}
    />
  );
}
