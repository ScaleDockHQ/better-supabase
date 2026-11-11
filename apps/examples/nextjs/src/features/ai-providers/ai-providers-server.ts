import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { AiKeys } from "better-supabase/blocks/ai-keys";
import type { VaultCredentials } from "better-supabase/credentials";

import { generatedOptions } from "better-supabase/blocks";
import { createAiKeys, rpcTransport } from "better-supabase/blocks/ai-keys";
import { vaultCredentials } from "better-supabase/credentials";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

const API_SCHEMA = blockConfig["ai-keys"].api;

const service = () =>
  rpcTransport(bsbCore.admin().$client, { schema: API_SCHEMA });

/** Vault, as the service role: provider keys are stored per tenant. */
export function providerCredentials(): VaultCredentials {
  return vaultCredentials({ transport: service(), schema: API_SCHEMA });
}

/**
 * The ai-keys block acting as the caller; `ai_keys.manage` lists and saves
 * keys.
 */
export function aiProviders(supabase: RpcClient): AiKeys {
  return createAiKeys({
    ...generatedOptions(blockConfig["ai-keys"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: service(),
    credentials: providerCredentials(),
  });
}
