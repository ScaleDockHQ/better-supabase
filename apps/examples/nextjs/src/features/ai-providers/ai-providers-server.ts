import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { AiKeys } from "better-supabase/blocks/ai-keys";
import type { VaultCredentials } from "better-supabase/credentials";

import { generatedOptions } from "better-supabase/blocks";
import { createAiKeys, rpcTransport } from "better-supabase/blocks/ai-keys";
import { vaultCredentials } from "better-supabase/credentials";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["ai-keys"].api;

const service = () => rpcTransport(bsb.admin().$client, { schema: API_SCHEMA });

/** Vault, as the service role: provider keys are stored per tenant. */
export function providerCredentials(): VaultCredentials {
  return vaultCredentials({ transport: service(), schema: API_SCHEMA });
}

/** The ai-keys block acting as the caller; `ai.admin` lists and saves keys. */
export function aiProviders(supabase: RpcClient): AiKeys {
  return createAiKeys({
    ...generatedOptions(blockConfig["ai-keys"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: service(),
    credentials: providerCredentials(),
  });
}
