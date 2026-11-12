import "server-only";
import type { Agents } from "better-supabase/blocks/agents";
import type { RpcClient } from "better-supabase/blocks/organizations";

import { generatedOptions } from "better-supabase/blocks";
import { createAgents, rpcTransport } from "better-supabase/blocks/agents";

import { blockConfig } from "@/lib/supabase/blocks.config";

const API_SCHEMA = blockConfig.agents.api;

/** The agents block acting as the caller; RLS and `agents.*` keys decide. */
export function agentsBlock(supabase: RpcClient): Agents {
  return createAgents({
    ...generatedOptions(blockConfig.agents),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
  });
}
