import type { SupabaseClient } from "@supabase/supabase-js";

import type { ClientLike } from "../bindings/client.ts";
import type { ClientPorts } from "../client/ports.ts";
import type { BlockTransport } from "../core/block-transport.ts";
import type { TopicPort } from "../realtime/watch-topic.ts";
import type { GeneratedBlock, GeneratedBlocks } from "./block-config.ts";
import type { AuthPort } from "./controller.ts";

import { claimedTenant } from "../bindings/keys.ts";
import { wrapTransport } from "../core/block-hooks.ts";
import { blockNames } from "../core/block-names.ts";
import { currentTenant } from "../core/block-tenant.ts";
import { rpcTransport } from "../core/block-transport.ts";
import { topicPort } from "../realtime/watch-topic.ts";

/**
 * What the block bindings hand their controllers: the provider's client,
 * session, ports, generated block config and tenant.
 */
export interface BlockEnv {
  readonly supabase: SupabaseClient;
  readonly auth: AuthPort;
  readonly ports: ClientPorts & { readonly topic: TopicPort };
  /** `blockConfig` from `blocks.generated.ts`, when the client has it. */
  readonly config: GeneratedBlocks | undefined;
  /**
   * The tenant the hooks act in now: the client's `tenant` option, then the
   * session's tenant claim.
   */
  readonly tenant: () => string | undefined;
}

/**
 * The client's session and ports; the topic port defaults to its supabase-js
 * client.
 */
export function blockEnv(
  client: Pick<ClientLike, "supabase" | "auth" | "ports"> &
    Partial<Pick<ClientLike, "betterSupabase" | "blocks" | "tenant">>,
): BlockEnv {
  return {
    supabase: client.supabase,
    auth: client.auth,
    ports: {
      ...client.ports,
      topic: client.ports?.topic ?? topicPort(client.supabase),
    },
    config: client.blocks,
    tenant: () =>
      client.tenant === undefined
        ? client.betterSupabase === undefined
          ? undefined
          : claimedTenant(client.auth.current(), client.betterSupabase.meta)
        : currentTenant(client.tenant),
  };
}

/** What a hook passes a block creator from the env. */
export interface EnvBlockOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
}

/**
 * A block's transport and schema for a hook: the supabase-js client calls the
 * schema and the function names `gen` wrote for `block` in `blockConfig`, or
 * the module defaults when the client has no config.
 */
export function envBlockOptions(env: BlockEnv, block: string): EnvBlockOptions {
  const entry = env.config?.[block];
  const transport = rpcTransport(env.supabase);

  return {
    transport:
      entry?.names === undefined
        ? transport
        : wrapTransport(transport, blockNames(entry.names)),
    ...(entry === undefined ? {} : { schema: entry.api ?? entry.schema }),
  };
}

/**
 * The options `gen` wrote for `block`, such as the reactions `topic`; empty
 * when the client has no config.
 */
export function envBlockSettings(
  env: BlockEnv,
  block: string,
): GeneratedBlock["options"] {
  return env.config?.[block]?.options ?? {};
}

type EnvKey = "auth" | "ports";

/**
 * A controller's options as a binding takes them: `auth` and `ports` come from
 * the provider unless the caller passes its own.
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
