import { useContext, useMemo, useSyncExternalStore } from "react";

import type { BlockEnv } from "./block-env.ts";

import { ClientContext } from "../react/context.ts";
import { blockEnv } from "./block-env.ts";

export type { BlockEnv } from "./block-env.ts";

/**
 * The provider's client, session and ports; the topic port defaults to its
 * supabase-js client.
 */
export function useBlockEnv(): BlockEnv {
  const value = useContext(ClientContext);

  if (!value) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bs}>",
    );
  }

  const { client } = value;

  return useMemo(() => blockEnv(client), [client]);
}

/** The env's tenant, rendered again when the session changes. */
export function useBlockTenant(env: BlockEnv): string | undefined {
  return useSyncExternalStore(env.auth.subscribe, env.tenant, () =>
    env.tenant(),
  );
}
