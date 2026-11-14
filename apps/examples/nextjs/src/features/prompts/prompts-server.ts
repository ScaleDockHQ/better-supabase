import "server-only";
import type { AiAccess, Prompts } from "better-supabase/blocks/prompts";

import { generatedOptions } from "better-supabase/blocks";
import { createPrompts, rpcTransport } from "better-supabase/blocks/prompts";

import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsbCore } from "@/lib/supabase/server-core";

/**
 * The prompts block as the service role: templates can hold instructions, so
 * only the service role reads them and pass `access` and the block checks the
 * tenant and permission.
 */
export function promptsBlock(access?: AiAccess): Prompts {
  return createPrompts({
    ...generatedOptions(blockConfig.prompts),
    ...(access === undefined ? {} : { access }),
    transport: rpcTransport(bsbCore.admin().$client, {
      schema: blockConfig.prompts.api,
    }),
  });
}
