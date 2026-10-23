import {
  type RpcClient,
  defineBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { identitiesBlock } from "better-supabase/blocks/identities";
import { notificationsBlock } from "better-supabase/blocks/notifications";
import { profilesBlock } from "better-supabase/blocks/profiles";
import { pushBlock } from "better-supabase/blocks/push";

import { blockConfig } from "./consumer.blocks.generated.ts";

/** The installed blocks, with the settings `better-supabase gen` writes from the config. */
export const blockSet = defineBlocks(blockConfig, {
  identities: identitiesBlock,
  notifications: notificationsBlock,
  profiles: profilesBlock,
  push: pushBlock,
});

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return blockSet.create({ transport: rpcTransport(supabase) });
}
