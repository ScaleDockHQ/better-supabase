import type { SupabaseClient } from "@supabase/supabase-js";

import { useContext, useMemo } from "react";

import type { ClientPorts } from "../client/ports.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { AuthPort } from "./controller.ts";

import { ClientContext } from "../react/context.ts";
import { topicPort } from "../realtime/watch-topic.ts";

/** What the block hooks hand their controllers: the provider's client, session and ports. */
export interface BlockEnv {
  readonly supabase: SupabaseClient;
  readonly auth: AuthPort;
  readonly ports: ClientPorts & { readonly topic: TopicPort };
}

/** The provider's client, session and ports; the topic port defaults to its supabase-js client. */
export function useBlockEnv(): BlockEnv {
  const value = useContext(ClientContext);
  if (!value) {
    throw new Error(
      "better-supabase: wrap your app in <BetterSupabaseProvider client={bs}>",
    );
  }
  const { client } = value;
  return useMemo(
    () => ({
      supabase: client.supabase,
      auth: client.auth,
      ports: {
        ...client.ports,
        topic: client.ports?.topic ?? topicPort(client.supabase),
      },
    }),
    [client],
  );
}
