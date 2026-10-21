import type { BlockTransport } from "../core/block-transport.ts";
import type { GeneratedBlock } from "./block-config.ts";
import type { BlockEnv } from "./block-env.ts";

import { wrapTransport } from "../core/block-hooks.ts";
import { blockNames } from "../core/block-names.ts";
import { rpcTransport } from "../core/block-transport.ts";

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
