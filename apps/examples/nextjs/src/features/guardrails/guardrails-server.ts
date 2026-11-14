import "server-only";
import type {
  AiAccess,
  AiGuardrails,
} from "better-supabase/blocks/ai-guardrails";

import { generatedOptions } from "better-supabase/blocks";
import {
  createAiGuardrails,
  rpcTransport,
} from "better-supabase/blocks/ai-guardrails";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The ai-guardrails block as the service role; pass `access` and the block
 * checks the tenant and permission.
 */
export function guardrailsBlock(access?: AiAccess): AiGuardrails {
  return createAiGuardrails({
    ...generatedOptions(blockConfig["ai-guardrails"]),
    ...(access === undefined ? {} : { access }),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig["ai-guardrails"].api,
    }),
  });
}
