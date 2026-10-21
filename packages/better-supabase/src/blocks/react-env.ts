import { useContext, useMemo } from "react";

import { ClientContext } from "../react/context.ts";
import { blockEnv, type BlockEnv } from "./block-env.ts";

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
