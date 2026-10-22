import "server-only";
import type { RpcClient } from "better-supabase/blocks";
import type { AiTasks } from "better-supabase/blocks/ai-tasks";

import { generatedOptions } from "better-supabase/blocks";
import { createAiTasks, rpcTransport } from "better-supabase/blocks/ai-tasks";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["ai-tasks"].api;

/**
 * The ai-tasks block acting as the caller. The service role sets each new
 * task's next run right after the save, instead of on the next tick.
 */
export function aiTasks(supabase: RpcClient): AiTasks {
  return createAiTasks({
    ...generatedOptions(blockConfig["ai-tasks"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: rpcTransport(bsb.admin().$client, { schema: API_SCHEMA }),
  });
}
