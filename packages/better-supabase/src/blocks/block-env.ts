import type { SupabaseClient } from "@supabase/supabase-js";

import type { ClientLike } from "../bindings/client.ts";
import type { ClientPorts } from "../client/ports.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { AuthPort } from "./controller.ts";

import { topicPort } from "../realtime/watch-topic.ts";

/** What the block bindings hand their controllers: the provider's client, session and ports. */
export interface BlockEnv {
  readonly supabase: SupabaseClient;
  readonly auth: AuthPort;
  readonly ports: ClientPorts & { readonly topic: TopicPort };
}

/** The client's session and ports; the topic port defaults to its supabase-js client. */
export function blockEnv(
  client: Pick<ClientLike, "supabase" | "auth" | "ports">,
): BlockEnv {
  return {
    supabase: client.supabase,
    auth: client.auth,
    ports: {
      ...client.ports,
      topic: client.ports?.topic ?? topicPort(client.supabase),
    },
  };
}

type EnvKey = "auth" | "ports";

/**
 * A controller's options as a binding takes them: `auth` and `ports` come
 * from the provider unless the caller passes its own.
 */
export type BlockOptions<O> = Omit<O, EnvKey> &
  Partial<Pick<O, Extract<keyof O, EnvKey>>>;

/**
 * Fills `auth` and `ports` from `env` when `options` leaves them out; `env`
 * runs only then. Without `env` the controller takes neither key.
 */
export function withEnv<O>(
  options: BlockOptions<O>,
  env: (() => BlockEnv) | undefined,
): O {
  const given = new Map<string, unknown>(Object.entries(options));

  if (
    env === undefined ||
    (given.get("auth") !== undefined && given.get("ports") !== undefined)
  ) {
    // SAFETY: the controller's options declare neither env key, or both are
    // present, so `options` is the full `O`.
    return options as O;
  }

  const { auth, ports } = env();

  // SAFETY: `BlockOptions<O>` is `O` without `auth` and `ports`, which the
  // spread adds; a controller ignores the keys its options don't declare.
  return { auth, ports, ...options } as O;
}
