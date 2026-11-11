import "server-only";
import type { AiEvals } from "better-supabase/blocks/ai-evals";

import { generatedOptions } from "better-supabase/blocks";
import { createAiEvals, rpcTransport } from "better-supabase/blocks/ai-evals";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/** The ai-evals block as the service role; callers check the tenant first. */
export function evalsBlock(): AiEvals {
  return createAiEvals({
    ...generatedOptions(blockConfig["ai-evals"]),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig["ai-evals"].api,
    }),
  });
}
