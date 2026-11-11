import "server-only";
import type { Prompts } from "better-supabase/blocks/prompts";

import { generatedOptions } from "better-supabase/blocks";
import { createPrompts, rpcTransport } from "better-supabase/blocks/prompts";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The prompts block as the service role: templates can hold instructions, so
 * only the service role reads them and every caller checks the tenant first.
 */
export function promptsBlock(): Prompts {
  return createPrompts({
    ...generatedOptions(blockConfig.prompts),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig.prompts.api,
    }),
  });
}
