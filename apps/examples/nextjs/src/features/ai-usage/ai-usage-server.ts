import "server-only";
import type { AiCache } from "better-supabase/blocks/ai-cache";

import { generatedOptions } from "better-supabase/blocks";
import { createAiCache, rpcTransport } from "better-supabase/blocks/ai-cache";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/** The ai-cache block as the service role: entries hold prompts and answers. */
export function aiCacheBlock(): AiCache {
  return createAiCache({
    ...generatedOptions(blockConfig["ai-cache"]),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig["ai-cache"].api,
    }),
  });
}
