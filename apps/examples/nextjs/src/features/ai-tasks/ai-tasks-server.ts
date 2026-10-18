import "server-only";
import { generatedOptions, type RpcClient } from "better-supabase/blocks";
import {
  type AiTasks,
  createAiTasks,
  rpcTransport,
} from "better-supabase/blocks/ai-tasks";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

const API_SCHEMA = blockConfig["ai-tasks"].api;

/**
 * The ai-tasks block acting as the caller. The service role sets each new
 * task's next run right after the save, instead of on the next tick.
 */
export function aiTasks(supabase: RpcClient): AiTasks {
  return createAiTasks({
    ...generatedOptions(blockConfig["ai-tasks"]),
    transport: rpcTransport(supabase, { schema: API_SCHEMA }),
    service: rpcTransport(bs.admin().$client, { schema: API_SCHEMA }),
  });
}
