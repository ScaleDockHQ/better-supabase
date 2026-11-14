import "server-only";
import type { AiAccess, AiEvals } from "better-supabase/blocks/ai-evals";

import { generatedOptions } from "better-supabase/blocks";
import { createAiEvals, rpcTransport } from "better-supabase/blocks/ai-evals";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The ai-evals block as the service role; pass `access` and the block checks
 * the tenant and permission.
 */
export function evalsBlock(access?: AiAccess): AiEvals {
  return createAiEvals({
    ...generatedOptions(blockConfig["ai-evals"]),
    ...(access === undefined ? {} : { access }),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig["ai-evals"].api,
    }),
  });
}
