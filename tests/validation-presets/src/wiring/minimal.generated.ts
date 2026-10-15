import {
  type RpcClient,
  createBlocks,
  rpcTransport,
} from "better-supabase/blocks";
import { profilesBlock } from "better-supabase/blocks/profiles";

/**
 * The blocks as typed clients, acting as the caller of `supabase`: its
 * token, so RLS and each function's checks apply.
 */
export function blocks(supabase: RpcClient) {
  return createBlocks(
    { transport: rpcTransport(supabase) },
    {
      profiles: profilesBlock,
    },
  );
}
