import "server-only";
import type { AiGuardrails } from "better-supabase/blocks/ai-guardrails";

import { generatedOptions } from "better-supabase/blocks";
import {
  createAiGuardrails,
  rpcTransport,
} from "better-supabase/blocks/ai-guardrails";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/** The ai-guardrails block as the service role; callers check the tenant first. */
export function guardrailsBlock(): AiGuardrails {
  return createAiGuardrails({
    ...generatedOptions(blockConfig["ai-guardrails"]),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig["ai-guardrails"].api,
    }),
  });
}
